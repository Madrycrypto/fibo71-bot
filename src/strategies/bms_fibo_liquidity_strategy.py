"""
BMS Fibonacci Liquidity Strategy

Main trading strategy combining:
- Break of Market Structure (BMS) detection
- Fibonacci retracement (0.62-0.71 zone)
- Liquidity sweep detection
- Confirmation candle validation
- Trend, Volume, Volatility filters
- Risk management with 3 TP levels

According to PDF specification for BTCUSDT on 15m timeframe.
"""

import pandas as pd
from datetime import datetime
from dataclasses import dataclass, field
from typing import Optional, Dict, Any
from enum import Enum
from loguru import logger

from indicators.bms_detector import BMSDetector, BMSResult, TrendDirection
from indicators.fibonacci_extended import FibonacciExtendedCalculator, FibonacciExtendedLevels
from indicators.liquidity_sweep import LiquiditySweepDetector, LiquiditySweepResult
from indicators.filters import AllFilters, AllFiltersResult


class StrategyState(Enum):
    """Strategy state machine states."""
    IDLE = "idle"                          # Waiting for BMS
    BMS_DETECTED = "bms_detected"          # BMS found, waiting for retracement
    IN_FIB_ZONE = "in_fib_zone"            # Price in 0.62-0.71 zone
    SWEEP_DETECTED = "sweep_detected"      # Liquidity sweep found
    AWAITING_CONFIRMATION = "awaiting_confirmation"  # Waiting for confirmation candle
    IN_TRADE = "in_trade"                  # Position open


@dataclass
class TradeSetup:
    """Complete trade setup with all details."""
    symbol: str
    direction: str  # 'BUY' or 'SELL'
    entry_price: float
    sl_price: float
    tp1_price: float
    tp2_price: float
    tp3_price: float
    lot_size: float
    rr_ratio: float
    fib_levels: FibonacciExtendedLevels
    bms_result: BMSResult
    sweep_result: LiquiditySweepResult
    filters_result: AllFiltersResult
    timestamp: datetime
    state_before_entry: StrategyState


@dataclass
class StrategyStatus:
    """Current strategy status."""
    state: StrategyState
    last_bms: Optional[BMSResult]
    fib_levels: Optional[FibonacciExtendedLevels]
    current_price: float
    in_entry_zone: bool
    sweep_detected: bool
    filter_status: str
    message: str


class BMSFiboLiquidityStrategy:
    """
    BMS Fibonacci Liquidity Strategy

    Algorithm (per PDF):
    1. Detect BMS with momentum filter
    2. Calculate Fibonacci levels (0.62-0.71 zone)
    3. Wait for retracement into Fibonacci zone
    4. Detect liquidity sweep (wick >= 2x body)
    5. Wait for confirmation candle
    6. Check all filters (trend, volume, volatility)
    7. Enter trade with 3 TP levels
    8. Manage position (partial closes at TP1, TP2, TP3)
    """

    def __init__(self,
                 symbol: str,
                 timeframe: str = 'M15',
                 risk_percent: float = 1.0,
                 max_daily_trades: int = 3,
                 # BMS Settings
                 bms_swing_lookback: int = 5,
                 bms_momentum_candles: int = 3,
                 bms_body_threshold: float = 0.60,
                 bms_distance_atr: float = 0.5,
                 # Fibonacci Settings
                 fib_entry_min: float = 0.62,
                 fib_entry_max: float = 0.71,
                 # Liquidity Sweep Settings
                 sweep_min_wick_ratio: float = 2.0,
                 sweep_ideal_wick_ratio: float = 3.0,
                 # Confirmation Candle
                 confirmation_body_pct: float = 0.50,
                 # SL Buffer
                 sl_buffer_percent: float = 0.1,
                 # Filter toggles
                 enable_trend_filter: bool = True,
                 enable_volume_filter: bool = True,
                 enable_volatility_filter: bool = True,
                 enable_rr_filter: bool = True,
                 # Filter parameters
                 ema_fast: int = 50,
                 ema_slow: int = 200,
                 volume_lookback: int = 20,
                 min_rr_ratio: float = 2.0):
        """
        Initialize BMS Fibonacci Liquidity Strategy.

        Args:
            symbol: Trading symbol
            timeframe: Chart timeframe
            risk_percent: Risk per trade (%)
            max_daily_trades: Maximum trades per day
            bms_swing_lookback: Swing detection lookback
            bms_momentum_candles: Required momentum candles
            bms_body_threshold: Body size threshold (%)
            bms_distance_atr: Minimum distance in ATR
            fib_entry_min: Min Fibonacci entry level
            fib_entry_max: Max Fibonacci entry level
            sweep_min_wick_ratio: Min wick/body ratio
            sweep_ideal_wick_ratio: Ideal wick/body ratio
            confirmation_body_pct: Min confirmation candle body %
            sl_buffer_percent: SL buffer percentage
            enable_trend_filter: Enable trend filter
            enable_volume_filter: Enable volume filter
            enable_volatility_filter: Enable volatility filter
            enable_rr_filter: Enable R:R filter
            ema_fast: Fast EMA period
            ema_slow: Slow EMA period
            volume_lookback: Volume lookback period
            min_rr_ratio: Minimum R:R ratio
        """
        self.symbol = symbol
        self.timeframe = timeframe
        self.risk_percent = risk_percent
        self.max_daily_trades = max_daily_trades

        # Initialize components
        self.bms_detector = BMSDetector(
            swing_lookback=bms_swing_lookback,
            momentum_candles_required=bms_momentum_candles,
            body_percent_threshold=bms_body_threshold,
            distance_atr_threshold=bms_distance_atr
        )

        self.fib_calculator = FibonacciExtendedCalculator(
            entry_zone_min=fib_entry_min,
            entry_zone_max=fib_entry_max
        )

        self.sweep_detector = LiquiditySweepDetector(
            min_wick_to_body_ratio=sweep_min_wick_ratio,
            ideal_wick_to_body_ratio=sweep_ideal_wick_ratio
        )

        self.filters = AllFilters(
            enable_trend_filter=enable_trend_filter,
            enable_volume_filter=enable_volume_filter,
            enable_volatility_filter=enable_volatility_filter,
            enable_rr_filter=enable_rr_filter,
            ema_fast=ema_fast,
            ema_slow=ema_slow,
            volume_lookback=volume_lookback,
            min_rr_ratio=min_rr_ratio
        )

        # Settings
        self.confirmation_body_pct = confirmation_body_pct
        self.sl_buffer_percent = sl_buffer_percent
        self.min_rr_ratio = min_rr_ratio

        # Filter toggles (for reference)
        self.enable_trend_filter = enable_trend_filter
        self.enable_volume_filter = enable_volume_filter
        self.enable_volatility_filter = enable_volatility_filter
        self.enable_rr_filter = enable_rr_filter

        # State
        self.state = StrategyState.IDLE
        self.pending_setup: Optional[TradeSetup] = None
        self.current_bms: Optional[BMSResult] = None
        self.current_fib_levels: Optional[FibonacciExtendedLevels] = None
        self.current_sweep: Optional[LiquiditySweepResult] = None
        self.daily_trades = 0
        self.last_trade_date = None

        logger.info(f"BMS Fibo Liquidity Strategy initialized for {symbol} on {timeframe}")
        logger.info(f"Filters: Trend={enable_trend_filter}, Volume={enable_volume_filter}, "
                   f"Volatility={enable_volatility_filter}, R:R={enable_rr_filter}")

    def analyze(self, df: pd.DataFrame) -> Optional[TradeSetup]:
        """
        Analyze market data for trade opportunities.

        Main entry point for strategy logic.

        Args:
            df: DataFrame with OHLCV data

        Returns:
            TradeSetup if opportunity found, None otherwise
        """
        current_price = df['close'].iloc[-1]
        current_idx = len(df) - 1

        # Check daily trade limit
        today = datetime.now().date()
        if self.last_trade_date != today:
            self.daily_trades = 0
            self.last_trade_date = today

        if self.daily_trades >= self.max_daily_trades:
            logger.debug(f"Daily trade limit reached ({self.max_daily_trades})")
            return None

        # State machine logic
        if self.state == StrategyState.IDLE:
            return self._check_for_bms(df)

        elif self.state == StrategyState.BMS_DETECTED:
            return self._check_fib_zone(df, current_price)

        elif self.state == StrategyState.IN_FIB_ZONE:
            return self._check_liquidity_sweep(df)

        elif self.state == StrategyState.SWEEP_DETECTED:
            return self._check_confirmation_candle(df)

        elif self.state == StrategyState.IN_TRADE:
            # Position management handled externally
            return None

        return None

    def _check_for_bms(self, df: pd.DataFrame) -> Optional[TradeSetup]:
        """Check for Break of Market Structure."""
        bms_result = self.bms_detector.detect_bms(
            df,
            enable_momentum_filter=True,
            enable_body_filter=True,
            enable_distance_filter=True
        )

        if not bms_result.detected:
            return None

        logger.info(f"BMS detected: {bms_result.message}")

        # Store BMS result
        self.current_bms = bms_result

        # Calculate Fibonacci levels
        swing_high = bms_result.swing_high_before_bms.price if bms_result.swing_high_before_bms else df['high'].max()
        swing_low = bms_result.swing_low_before_bms.price if bms_result.swing_low_before_bms else df['low'].min()

        direction = 'BUY' if bms_result.direction == TrendDirection.BULLISH else 'SELL'

        fib_levels = self.fib_calculator.calculate_levels(
            swing_high=swing_high,
            swing_low=swing_low,
            direction=direction
        )

        self.current_fib_levels = fib_levels
        self.state = StrategyState.BMS_DETECTED

        logger.info(f"Fibonacci levels calculated: Entry zone {fib_levels.entry_zone_min:.5f} - {fib_levels.entry_zone_max:.5f}")

        return None

    def _check_fib_zone(self, df: pd.DataFrame, current_price: float) -> Optional[TradeSetup]:
        """Check if price has entered Fibonacci zone."""
        if not self.current_fib_levels:
            self.state = StrategyState.IDLE
            return None

        is_in_zone, fib_pct = self.fib_calculator.is_in_entry_zone(
            current_price, self.current_fib_levels
        )

        if is_in_zone:
            logger.info(f"Price entered Fib zone: {current_price:.5f} (Fib: {fib_pct:.3f})")
            self.state = StrategyState.IN_FIB_ZONE

        return None

    def _check_liquidity_sweep(self, df: pd.DataFrame) -> Optional[TradeSetup]:
        """Check for liquidity sweep."""
        if not self.current_fib_levels or not self.current_bms:
            self.state = StrategyState.IDLE
            return None

        direction = 'BUY' if self.current_bms.direction == TrendDirection.BULLISH else 'SELL'

        sweep_result = self.sweep_detector.detect_sweep(
            df,
            fib_062_level=self.current_fib_levels.level_618,
            direction=direction,
            enable_wick_filter=True
        )

        if not sweep_result.detected:
            # Check if price left the zone (reset)
            current_price = df['close'].iloc[-1]
            is_in_zone, _ = self.fib_calculator.is_in_entry_zone(
                current_price, self.current_fib_levels
            )
            if not is_in_zone:
                logger.debug("Price left Fib zone, resetting to BMS_DETECTED")
                self.state = StrategyState.BMS_DETECTED
                self.current_sweep = None
            return None

        logger.info(f"Liquidity sweep detected: {sweep_result.message}")
        self.current_sweep = sweep_result
        self.state = StrategyState.SWEEP_DETECTED

        return None

    def _check_confirmation_candle(self, df: pd.DataFrame) -> Optional[TradeSetup]:
        """Check for confirmation candle and execute trade."""
        if not self.current_fib_levels or not self.current_bms or not self.current_sweep:
            self.state = StrategyState.IDLE
            return None

        direction = 'BUY' if self.current_bms.direction == TrendDirection.BULLISH else 'SELL'

        # Check confirmation candle
        is_confirmed, msg = self.sweep_detector.check_confirmation_candle(
            df, direction, self.confirmation_body_pct
        )

        if not is_confirmed:
            logger.debug(f"Confirmation candle check: {msg}")
            return None

        logger.info(f"Confirmation candle: {msg}")

        # Check all filters
        entry_price = df['close'].iloc[-1]
        sl_price = self.fib_calculator.calculate_sl_with_buffer(
            self.current_fib_levels, self.sl_buffer_percent
        )
        tp_price = self.current_fib_levels.level_0  # TP1 for R:R calculation

        filters_result = self.filters.check_all(
            df, direction, entry_price, sl_price, tp_price
        )

        if not filters_result.all_passed:
            logger.info(f"Trade blocked by {filters_result.blocked_by}")
            self.state = StrategyState.IDLE
            return None

        # Create trade setup
        setup = TradeSetup(
            symbol=self.symbol,
            direction=direction,
            entry_price=entry_price,
            sl_price=sl_price,
            tp1_price=self.current_fib_levels.level_0,
            tp2_price=self.current_fib_levels.ext_127,
            tp3_price=self.current_fib_levels.ext_162,
            lot_size=0.01,  # Will be calculated by risk manager
            rr_ratio=self.fib_calculator.calculate_rr_ratio(entry_price, sl_price, tp_price),
            fib_levels=self.current_fib_levels,
            bms_result=self.current_bms,
            sweep_result=self.current_sweep,
            filters_result=filters_result,
            timestamp=datetime.now(),
            state_before_entry=self.state
        )

        logger.info(f"Trade setup created: {direction} @ {entry_price:.5f}, "
                   f"SL: {sl_price:.5f}, TP1: {setup.tp1_price:.5f}, R:R: 1:{setup.rr_ratio:.1f}")

        # Reset state for next setup
        self.state = StrategyState.IN_TRADE
        self.daily_trades += 1

        return setup

    def reset_state(self):
        """Reset strategy state (after trade close or timeout)."""
        self.state = StrategyState.IDLE
        self.current_bms = None
        self.current_fib_levels = None
        self.current_sweep = None
        self.pending_setup = None
        logger.info("Strategy state reset to IDLE")

    def get_status(self) -> StrategyStatus:
        """Get current strategy status."""
        filter_status = "Filters active"

        return StrategyStatus(
            state=self.state,
            last_bms=self.current_bms,
            fib_levels=self.current_fib_levels,
            current_price=0.0,  # Will be updated externally
            in_entry_zone=self.state in [StrategyState.IN_FIB_ZONE, StrategyState.SWEEP_DETECTED, StrategyState.AWAITING_CONFIRMATION],
            sweep_detected=self.current_sweep is not None and self.current_sweep.detected,
            filter_status=filter_status,
            message=f"State: {self.state.value}"
        )

    def update_price(self, price: float):
        """Update current price in status."""
        pass  # Status is generated on demand

    def get_config(self) -> Dict[str, Any]:
        """Get current configuration."""
        return {
            'symbol': self.symbol,
            'timeframe': self.timeframe,
            'risk_percent': self.risk_percent,
            'max_daily_trades': self.max_daily_trades,
            'filters': {
                'trend': self.enable_trend_filter,
                'volume': self.enable_volume_filter,
                'volatility': self.enable_volatility_filter,
                'rr': self.enable_rr_filter
            }
        }
