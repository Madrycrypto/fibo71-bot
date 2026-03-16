"""
BMS Fibonacci Liquidity Strategy

Main trading strategy combining:
- Break of Market Structure (BMS) detection
- Peak/Valley confirmation after BMS
- Fibonacci retracement (configurable zone)
- Liquidity sweep detection
- Confirmation candle validation
- Trend, Volume, Volatility filters
- Risk management with 3 TP levels
- GRID ORDERS support (multiple entries in Fib zone)

According to PDF specification for BTCUSDT on 15m timeframe.

CORRECTED ALGORITHM:
1. Detect BMS (break of swing high/low)
2. Track new extremum AFTER BMS (new high/low)
3. Wait for retracement back through BMS level (confirms extremum)
4. Calculate Fibonacci: swing_point → confirmed extremum
5. Wait for price to enter Fib zone (configurable: default 0.62-0.71)
6. Detect liquidity sweep (wick >= 2x body)
7. Wait for confirmation candle
8. Check all filters → Enter trade(s)
   - Single entry OR Grid orders (configurable)
"""

import pandas as pd
from datetime import datetime
from dataclasses import dataclass, field
from typing import Optional, Dict, Any, List
from enum import Enum
from loguru import logger

from indicators.bms_detector import BMSDetector, BMSResult, TrendDirection
from indicators.fibonacci_extended import FibonacciExtendedCalculator, FibonacciExtendedLevels
from indicators.liquidity_sweep import LiquiditySweepDetector, LiquiditySweepResult
from indicators.filters import AllFilters, AllFiltersResult
from utils.grid_manager import GridOrderManager, GridConfig, GridOrder, SpacingMode, DistributionMode


class StrategyState(Enum):
    """Strategy state machine states."""
    IDLE = "idle"                              # Waiting for BMS
    BMS_DETECTED = "bms_detected"              # BMS found, tracking new extremum
    TRACKING_EXTREMUM = "tracking_extremum"    # Tracking new high/low after BMS
    EXTREMUM_CONFIRMED = "extremum_confirmed"  # Price retraced through BMS level, Fib calculated
    IN_FIB_ZONE = "in_fib_zone"                # Price in 0.62-0.71 zone
    SWEEP_DETECTED = "sweep_detected"          # Liquidity sweep found
    IN_TRADE = "in_trade"                      # Position open


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
    confirmed_extremum_price: float  # The peak/valley that confirmed Fib levels
    # Grid order fields
    is_grid_order: bool = False
    grid_index: int = 0  # 0 = single entry, 1-5 = grid order index
    total_grid_orders: int = 1


@dataclass
class GridTradeSetup:
    """Complete grid trade setup with multiple orders."""
    symbol: str
    direction: str
    fib_levels: FibonacciExtendedLevels
    sl_price: float
    tp1_price: float
    tp2_price: float
    tp3_price: float
    bms_result: BMSResult
    sweep_result: LiquiditySweepResult
    filters_result: AllFiltersResult
    timestamp: datetime
    confirmed_extremum_price: float
    grid_orders: List[GridOrder] = field(default_factory=list)
    total_risk_percent: float = 1.0


@dataclass
class StrategyStatus:
    """Current strategy status."""
    state: StrategyState
    last_bms: Optional[BMSResult]
    fib_levels: Optional[FibonacciExtendedLevels]
    current_price: float
    confirmed_extremum: Optional[float]
    in_entry_zone: bool
    sweep_detected: bool
    filter_status: str
    message: str


class BMSFiboLiquidityStrategy:
    """
    BMS Fibonacci Liquidity Strategy

    Algorithm (CORRECTED):
    1. Detect BMS with momentum filter
    2. Track new extremum after BMS (new high for bullish, new low for bearish)
    3. Wait for retracement through BMS level (confirms extremum)
    4. Calculate Fibonacci: swing_point → confirmed_extremum
    5. Wait for retracement into 0.62-0.71 zone
    6. Detect liquidity sweep (wick >= 2x body)
    7. Wait for confirmation candle
    8. Check all filters (trend, volume, volatility)
    9. Enter trade with 3 TP levels
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
                 # Fibonacci Settings (CONFIGURABLE ZONE!)
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
                 min_rr_ratio: float = 2.0,
                 # Extremum tracking
                 min_extremum_candles: int = 1,
                 # GRID ORDER SETTINGS (NEW!)
                 enable_grid: bool = False,
                 grid_orders_count: int = 5,
                 grid_spacing_mode: str = "equal",  # "equal", "fib", "custom"
                 grid_distribution: str = "equal"):  # "equal", "weighted"
        """
        Initialize BMS Fibonacci Liquidity Strategy.

        Grid Order Parameters:
            enable_grid: Enable multiple entry orders in Fib zone
            grid_orders_count: Number of orders to place (default 5)
            grid_spacing_mode: How to space orders ("equal", "fib", "custom")
            grid_distribution: How to distribute risk ("equal", "weighted")
        """
        self.symbol = symbol
        self.timeframe = timeframe
        self.risk_percent = risk_percent
        self.max_daily_trades = max_daily_trades
        self.min_extremum_candles = min_extremum_candles

        # Store Fib zone settings for reference
        self.fib_entry_min = fib_entry_min
        self.fib_entry_max = fib_entry_max

        # Grid order configuration
        self.enable_grid = enable_grid
        self.grid_config = GridConfig(
            enabled=enable_grid,
            orders_count=grid_orders_count,
            spacing_mode=SpacingMode(grid_spacing_mode),
            distribution_mode=DistributionMode(grid_distribution)
        )
        self.grid_manager: Optional[GridOrderManager] = None

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

        # Filter toggles
        self.enable_trend_filter = enable_trend_filter
        self.enable_volume_filter = enable_volume_filter
        self.enable_volatility_filter = enable_volatility_filter
        self.enable_rr_filter = enable_rr_filter

        # State
        self.state = StrategyState.IDLE
        self.current_bms: Optional[BMSResult] = None
        self.current_fib_levels: Optional[FibonacciExtendedLevels] = None
        self.current_sweep: Optional[LiquiditySweepResult] = None

        # Extremum tracking
        self.confirmed_extremum: Optional[float] = None  # The peak/valley price
        self.bms_level: Optional[float] = None  # The BMS breakout level
        self.best_extremum_after_bms: Optional[float] = None  # Best high/low since BMS
        self.candles_since_bms: int = 0

        self.daily_trades = 0
        self.last_trade_date = None

        # Grid order manager
        if self.enable_grid:
            self.grid_manager = GridOrderManager(self.grid_config)
        else:
            self.grid_manager = None

        logger.info(f"BMS Fibo Liquidity Strategy initialized for {symbol} on {timeframe}")
        logger.info(f"Filters: Trend={enable_trend_filter}, Volume={enable_volume_filter}, "
                   f"Volatility={enable_volatility_filter}, R:R={enable_rr_filter}")
        if self.enable_grid:
            logger.info(f"Grid: ENABLED ({grid_orders_count} orders)")

    def analyze(self, df: pd.DataFrame) -> Optional[TradeSetup]:
        """
        Analyze market data for trade opportunities.
        """
        current_price = df['close'].iloc[-1]

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
            return self._track_extremum(df, current_price)

        elif self.state == StrategyState.TRACKING_EXTREMUM:
            return self._check_extremum_confirmation(df, current_price)

        elif self.state == StrategyState.EXTREMUM_CONFIRMED:
            return self._check_fib_zone(df, current_price)

        elif self.state == StrategyState.IN_FIB_ZONE:
            return self._check_liquidity_sweep(df)

        elif self.state == StrategyState.SWEEP_DETECTED:
            return self._check_confirmation_candle(df)

        elif self.state == StrategyState.IN_TRADE:
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
        self.candles_since_bms = 0

        # Set the BMS level (the level that was broken)
        if bms_result.direction == TrendDirection.BULLISH:
            self.bms_level = bms_result.swing_high_before_bms.price
            self.best_extremum_after_bms = df['high'].iloc[-1]  # Start tracking highs
        else:
            self.bms_level = bms_result.swing_low_before_bms.price
            self.best_extremum_after_bms = df['low'].iloc[-1]  # Start tracking lows

        self.state = StrategyState.BMS_DETECTED
        logger.info(f"BMS level set: {self.bms_level:.5f}, tracking extremum...")

        return None

    def _track_extremum(self, df: pd.DataFrame, current_price: float) -> Optional[TradeSetup]:
        """Track new extremum after BMS."""
        self.candles_since_bms += 1

        # Update best extremum
        if self.current_bms.direction == TrendDirection.BULLISH:
            # For bullish BMS, track the highest high
            current_high = df['high'].iloc[-1]
            if current_high > self.best_extremum_after_bms:
                self.best_extremum_after_bms = current_high
                logger.debug(f"New high after BMS: {current_high:.5f}")
        else:
            # For bearish BMS, track the lowest low
            current_low = df['low'].iloc[-1]
            if current_low < self.best_extremum_after_bms:
                self.best_extremum_after_bms = current_low
                logger.debug(f"New low after BMS: {current_low:.5f}")

        # Need at least N candles to confirm extremum
        if self.candles_since_bms < self.min_extremum_candles:
            return None

        # Move to tracking state
        self.state = StrategyState.TRACKING_EXTREMUM
        return None

    def _check_extremum_confirmation(self, df: pd.DataFrame, current_price: float) -> Optional[TradeSetup]:
        """Check if price has retraced through BMS level, confirming the extremum."""
        self.candles_since_bms += 1

        # Continue tracking best extremum
        if self.current_bms.direction == TrendDirection.BULLISH:
            current_high = df['high'].iloc[-1]
            if current_high > self.best_extremum_after_bms:
                self.best_extremum_after_bms = current_high
                logger.debug(f"Updated high: {current_high:.5f}")
        else:
            current_low = df['low'].iloc[-1]
            if current_low < self.best_extremum_after_bms:
                self.best_extremum_after_bms = current_low
                logger.debug(f"Updated low: {current_low:.5f}")

        # Check for confirmation: price retraces through BMS level
        confirmed = False

        if self.current_bms.direction == TrendDirection.BULLISH:
            # Bullish BMS: wait for price to drop back below BMS level (swing_high)
            if current_price < self.bms_level:
                confirmed = True
                self.confirmed_extremum = self.best_extremum_after_bms
                logger.info(f"BULLISH extremum confirmed at {self.confirmed_extremum:.5f}, "
                           f"price below BMS level {self.bms_level:.5f}")
        else:
            # Bearish BMS: wait for price to rise back above BMS level (swing_low)
            if current_price > self.bms_level:
                confirmed = True
                self.confirmed_extremum = self.best_extremum_after_bms
                logger.info(f"BEARISH extremum confirmed at {self.confirmed_extremum:.5f}, "
                           f"price above BMS level {self.bms_level:.5f}")

        if not confirmed:
            # Timeout check - if too many candles, reset
            if self.candles_since_bms > 50:
                logger.warning("Extremum tracking timeout, resetting to IDLE")
                self.reset_state()
            return None

        # NOW calculate Fibonacci levels
        # For BULLISH: Fib from swing_low to confirmed high
        # For BEARISH: Fib from swing_high to confirmed low
        if self.current_bms.direction == TrendDirection.BULLISH:
            swing_low = self.current_bms.swing_low_before_bms.price
            fib_levels = self.fib_calculator.calculate_levels(
                swing_high=self.confirmed_extremum,  # The new high
                swing_low=swing_low,
                direction='BUY'
            )
        else:
            swing_high = self.current_bms.swing_high_before_bms.price
            fib_levels = self.fib_calculator.calculate_levels(
                swing_high=swing_high,
                swing_low=self.confirmed_extremum,  # The new low
                direction='SELL'
            )

        self.current_fib_levels = fib_levels
        self.state = StrategyState.EXTREMUM_CONFIRMED

        logger.info(f"Fibonacci levels calculated:")
        logger.info(f"  Swing point: {swing_low if self.current_bms.direction == TrendDirection.BULLISH else swing_high:.5f}")
        logger.info(f"  Confirmed extremum: {self.confirmed_extremum:.5f}")
        logger.info(f"  Entry zone: {fib_levels.entry_zone_min:.5f} - {fib_levels.entry_zone_max:.5f}")

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
                logger.debug("Price left Fib zone, going back to EXTREMUM_CONFIRMED")
                self.state = StrategyState.EXTREMUM_CONFIRMED
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
            confirmed_extremum_price=self.confirmed_extremum
        )

        logger.info(f"Trade setup created: {direction} @ {entry_price:.5f}, "
                   f"SL: {sl_price:.5f}, TP1: {setup.tp1_price:.5f}, R:R: 1:{setup.rr_ratio:.1f}")
        logger.info(f"Confirmed extremum used: {self.confirmed_extremum:.5f}")

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
        self.confirmed_extremum = None
        self.bms_level = None
        self.best_extremum_after_bms = None
        self.candles_since_bms = 0
        logger.info("Strategy state reset to IDLE")

    def get_status(self) -> StrategyStatus:
        """Get current strategy status."""
        return StrategyStatus(
            state=self.state,
            last_bms=self.current_bms,
            fib_levels=self.current_fib_levels,
            current_price=0.0,
            confirmed_extremum=self.confirmed_extremum,
            in_entry_zone=self.state in [StrategyState.IN_FIB_ZONE, StrategyState.SWEEP_DETECTED],
            sweep_detected=self.current_sweep is not None and self.current_sweep.detected,
            filter_status="Filters active",
            message=f"State: {self.state.value}"
        )

    def get_config(self) -> Dict[str, Any]:
        """Get current configuration."""
        return {
            'symbol': self.symbol,
            'timeframe': self.timeframe,
            'risk_percent': self.risk_percent,
            'max_daily_trades': self.max_daily_trades,
            'fib_zone': {
                'min': self.fib_entry_min,
                'max': self.fib_entry_max
            },
            'grid': {
                'enabled': self.enable_grid,
                'orders_count': self.grid_config.orders_count if self.enable_grid else 1
            },
            'filters': {
                'trend': self.enable_trend_filter,
                'volume': self.enable_volume_filter,
                'volatility': self.enable_volatility_filter,
                'rr': self.enable_rr_filter
            }
        }

    def create_grid_orders(self, account_balance: float = 10000.0) -> Optional[GridTradeSetup]:
        """
        Create grid orders within the Fibonacci zone.

        Call this after confirmation candle and filters pass.
        Returns GridTradeSetup with all order levels.

        Args:
            account_balance: Account balance for lot calculation

        Returns:
            GridTradeSetup with all grid orders, or None if grid disabled/no Fib levels
        """
        if not self.enable_grid or not self.current_fib_levels:
            return None

        if not self.grid_manager:
            return None

        # Create grid orders
        direction = 'BUY' if self.current_bms.direction == TrendDirection.BULLISH else 'SELL'

        self.grid_manager.create_grid_orders(
            entry_zone_min=self.fib_entry_min,
            entry_zone_max=self.fib_entry_max,
            fib_high=self.current_fib_levels.swing_high,
            fib_low=self.current_fib_levels.swing_low,
            total_risk_percent=self.risk_percent,
            direction=direction
        )

        # Calculate lot sizes
        sl_price = self.fib_calculator.calculate_sl_with_buffer(
            self.current_fib_levels, self.sl_buffer_percent
        )
        entry_price = self.grid_manager.orders[0].price if self.grid_manager.orders else 0
        sl_distance = abs(entry_price - sl_price)

        self.grid_manager.calculate_lot_sizes(
            account_balance=account_balance,
            sl_distance=sl_distance,
            pip_value=1.0
        )

        # Create grid trade setup
        filters_result = self.filters.check_all(
            pd.DataFrame(), direction, entry_price, sl_price, self.current_fib_levels.level_0
        )

        grid_setup = GridTradeSetup(
            symbol=self.symbol,
            direction=direction,
            fib_levels=self.current_fib_levels,
            sl_price=sl_price,
            tp1_price=self.current_fib_levels.level_0,
            tp2_price=self.current_fib_levels.ext_127,
            tp3_price=self.current_fib_levels.ext_162,
            bms_result=self.current_bms,
            sweep_result=self.current_sweep,
            filters_result=filters_result,
            timestamp=datetime.now(),
            confirmed_extremum_price=self.confirmed_extremum,
            grid_orders=self.grid_manager.orders.copy(),
            total_risk_percent=self.risk_percent
        )

        logger.info(f"Grid orders created: {len(self.grid_manager.orders)} orders")
        logger.info(self.grid_manager.get_grid_summary())

        return grid_setup

    def check_grid_fill(self, current_price: float) -> Optional[GridOrder]:
        """
        Check if any grid order level has been hit.

        Args:
            current_price: Current market price

        Returns:
            GridOrder if level hit, None otherwise
        """
        if not self.grid_manager:
            return None

        return self.grid_manager.get_order_at_price(current_price, tolerance=0.001)

    def get_grid_summary(self) -> str:
        """Get summary of current grid orders."""
        if not self.grid_manager or not self.grid_manager.orders:
            return "No grid orders"
        return self.grid_manager.get_grid_summary()
