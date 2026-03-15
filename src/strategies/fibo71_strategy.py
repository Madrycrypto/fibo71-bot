"""
CP 2.0 Strategy - Main Trading Logic

Combines BOS detection, Fibonacci levels, and risk management
to execute the CP 2.0 trading strategy.
"""

import pandas as pd
import MetaTrader5 as mt5
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from dataclasses import dataclass
from loguru import logger

from indicators.bos import BOSDetector, BOSResult, TrendDirection
from indicators.fibonacci import FibonacciCalculator, FibonacciLevels
from risk.manager import RiskManager, Position
from utils.mt5_utils import get_candles, place_order, close_position


@dataclass
class TradeSetup:
    """Represents a potential trade setup"""
    symbol: str
    direction: str
    entry_price: float
    sl: float
    tp: float
    lot_size: float
    fib_levels: FibonacciLevels
    bos_result: BOSResult
    timestamp: datetime


class CP2Strategy:
    """
    CP 2.0 Strategy Implementation

    Entry Rules:
    1. Detect BOS (Break of Structure) with Imbalance
    2. Calculate Fibonacci levels from the impulse
    3. Place limit order at 71-79% retracement
    4. Set TP at 0% and SL at 100%

    Exit Rules:
    - Set and Forget - no manual adjustments
    - TP or SL hit automatically
    """

    def __init__(self,
                 symbol: str,
                 timeframe: str = 'H4',
                 risk_percent: float = 1.0,
                 fib_entry_min: float = 0.71,
                 fib_entry_max: float = 0.79,
                 bos_lookback: int = 50,
                 min_imbalance_pips: float = 5.0,
                 enable_liquidity_sweep: bool = True):
        """
        Initialize CP 2.0 Strategy.

        Args:
            symbol: Trading symbol
            timeframe: Chart timeframe (default H4)
            risk_percent: Risk per trade (default 1%)
            fib_entry_min: Minimum Fibonacci entry level (default 0.71)
            fib_entry_max: Maximum Fibonacci entry level (default 0.79)
            bos_lookback: Lookback period for BOS detection
            min_imbalance_pips: Minimum imbalance in pips
            enable_liquidity_sweep: Use liquidity sweep filter
        """
        self.symbol = symbol
        self.timeframe = timeframe
        self.risk_percent = risk_percent

        # Initialize components
        self.bos_detector = BOSDetector(
            lookback=bos_lookback,
            min_imbalance_pips=min_imbalance_pips
        )
        self.fib_calculator = FibonacciCalculator(
            entry_min=fib_entry_min,
            entry_max=fib_entry_max
        )
        self.risk_manager = RiskManager(
            risk_percent=risk_percent,
            correlated_risk_percent=0.5,
            max_daily_trades=3,
            max_open_positions=2
        )

        self.enable_liquidity_sweep = enable_liquidity_sweep
        self.pending_setup: Optional[TradeSetup] = None
        self.order_placed = False

        logger.info(f"CP 2.0 Strategy initialized for {symbol} on {timeframe}")

    def analyze(self, df: pd.DataFrame) -> Optional[TradeSetup]:
        """
        Analyze market data for trade opportunities.

        Args:
            df: DataFrame with OHLCV data

        Returns:
            TradeSetup if opportunity found, None otherwise
        """
        # Step 1: Detect BOS
        bos_result = self.bos_detector.detect_bos(df)

        if not bos_result.detected:
            return None

        # Step 2: Check liquidity sweep filter if enabled
        if self.enable_liquidity_sweep and not bos_result.liquidity_sweep:
            logger.debug("BOS detected but no liquidity sweep - skipping")
            return None

        # Step 3: Calculate Fibonacci levels
        direction = 'SELL' if bos_result.direction == TrendDirection.BEARISH else 'BUY'

        swing_high = df['high'].iloc[bos_result.swing_point.index] if bos_result.swing_point.is_high else df['high'].max()
        swing_low = df['low'].iloc[bos_result.swing_point.index] if not bos_result.swing_point.is_high else df['low'].min()

        # Get swing points from BOS result
        if direction == 'SELL':
            swing_high = df.iloc[bos_result.breakout_candle]['high']
            swing_low = bos_result.swing_point.price
        else:
            swing_high = bos_result.swing_point.price
            swing_low = df.iloc[bos_result.breakout_candle]['low']

        fib_levels = self.fib_calculator.calculate_levels(
            swing_high=swing_high,
            swing_low=swing_low,
            direction=direction
        )

        # Step 4: Check risk management
        can_trade, reason = self.risk_manager.can_open_trade(self.symbol)
        if not can_trade:
            logger.info(f"Trade blocked: {reason}")
            return None

        # Step 5: Create trade setup
        entry_price = self.fib_calculator.get_entry_price(fib_levels, preferred_level=0.75)

        risk_pct = self.risk_manager.get_risk_for_trade(self.symbol)
        lot_size = self.fib_calculator.calculate_position_size(
            account_balance=mt5.account_info().balance,
            entry_price=entry_price,
            sl_price=fib_levels.level_100,
            risk_percent=risk_pct
        )

        setup = TradeSetup(
            symbol=self.symbol,
            direction=direction,
            entry_price=entry_price,
            sl=fib_levels.level_100,
            tp=fib_levels.level_0,
            lot_size=lot_size,
            fib_levels=fib_levels,
            bos_result=bos_result,
            timestamp=datetime.now()
        )

        logger.info(f"Trade setup found: {direction} @ {entry_price:.5f}, "
                   f"SL: {fib_levels.level_100:.5f}, TP: {fib_levels.level_0:.5f}")

        return setup

    def place_limit_order(self, setup: TradeSetup) -> bool:
        """
        Place a pending limit order based on setup.

        Args:
            setup: TradeSetup object

        Returns:
            True if order placed successfully
        """
        order_type = mt5.ORDER_TYPE_BUY_LIMIT if setup.direction == 'BUY' else mt5.ORDER_TYPE_SELL_LIMIT

        request = {
            "action": mt5.TRADE_ACTION_PENDING,
            "symbol": setup.symbol,
            "volume": setup.lot_size,
            "type": order_type,
            "price": setup.entry_price,
            "sl": setup.sl,
            "tp": setup.tp,
            "deviation": 20,
            "magic": 710071,
            "comment": "CP2.0 Fibo71",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = mt5.order_send(request)

        if result.retcode != mt5.TRADE_RETCODE_DONE:
            logger.error(f"Order failed: {result.comment}")
            return False

        logger.info(f"Order placed: {setup.direction} {setup.lot_size} @ {setup.entry_price:.5f}")
        return True

    def on_tick(self, df: pd.DataFrame) -> Optional[TradeSetup]:
        """
        Process new tick data.

        Args:
            df: DataFrame with latest OHLCV data

        Returns:
            TradeSetup if new setup detected
        """
        # If we have a pending setup, check if it's still valid
        if self.pending_setup and not self.order_placed:
            # Check if price has reached entry zone
            current_price = df['close'].iloc[-1]

            is_in_zone, fib_pct = self.fib_calculator.is_in_entry_zone(
                current_price,
                self.pending_setup.fib_levels
            )

            if is_in_zone:
                if self.place_limit_order(self.pending_setup):
                    self.order_placed = True
                    return self.pending_setup

        # Look for new setups
        setup = self.analyze(df)

        if setup:
            self.pending_setup = setup
            self.order_placed = False

            # Try to place order immediately
            current_price = df['close'].iloc[-1]
            is_in_zone, _ = self.fib_calculator.is_in_entry_zone(
                current_price,
                setup.fib_levels
            )

            if is_in_zone:
                if self.place_limit_order(setup):
                    self.order_placed = True
                    return setup

        return None

    def get_status(self) -> Dict[str, Any]:
        """
        Get current strategy status.

        Returns:
            Dictionary with status information
        """
        return {
            "symbol": self.symbol,
            "timeframe": self.timeframe,
            "pending_setup": self.pending_setup is not None,
            "order_placed": self.order_placed,
            "open_positions": len(self.risk_manager.open_positions),
            "daily_trades": self.risk_manager.get_daily_stats().trades_opened
        }
