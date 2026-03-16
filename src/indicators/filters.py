"""
Trading Filters Module

Implements trend, volume, and volatility filters according to PDF specification:
- Trend Filter: EMA50 > EMA200 (for LONG), EMA50 < EMA200 (for SHORT)
- Volume Filter: Current volume > average volume of last 20 candles
- Volatility Filter: ATR(14) > average ATR(20)
"""

import pandas as pd
import numpy as np
from dataclasses import dataclass
from typing import Tuple, Optional


@dataclass
class FilterResult:
    """Result of a filter check."""
    passed: bool
    value: float
    threshold: float
    message: str


@dataclass
class AllFiltersResult:
    """Result of all filter checks."""
    trend_filter: FilterResult
    volume_filter: FilterResult
    volatility_filter: FilterResult
    all_passed: bool
    blocked_by: Optional[str]


class TrendFilter:
    """
    EMA Trend Filter

    According to PDF:
    - LONG: EMA50 > EMA200 (uptrend)
    - SHORT: EMA50 < EMA200 (downtrend)
    """

    def __init__(self, fast_period: int = 50, slow_period: int = 200):
        """
        Initialize Trend Filter.

        Args:
            fast_period: Fast EMA period (default 50)
            slow_period: Slow EMA period (default 200)
        """
        self.fast_period = fast_period
        self.slow_period = slow_period

    def check(self, df: pd.DataFrame, direction: str) -> FilterResult:
        """
        Check trend filter.

        Args:
            df: DataFrame with OHLCV data (must have 'close' column)
            direction: 'BUY' or 'SELL'

        Returns:
            FilterResult with pass/fail status
        """
        if len(df) < self.slow_period + 1:
            return FilterResult(
                passed=False,
                value=0.0,
                threshold=0.0,
                message=f"Insufficient data (need {self.slow_period + 1} candles)"
            )

        # Calculate EMAs
        ema_fast = df['close'].ewm(span=self.fast_period, adjust=False).mean()
        ema_slow = df['close'].ewm(span=self.slow_period, adjust=False).mean()

        ema_fast_current = ema_fast.iloc[-1]
        ema_slow_current = ema_slow.iloc[-1]

        direction = direction.upper()

        if direction == 'BUY':
            # For LONG: EMA50 should be above EMA200
            passed = ema_fast_current > ema_slow_current
            message = (f"EMA50 ({ema_fast_current:.5f}) > EMA200 ({ema_slow_current:.5f})"
                      if passed else
                      f"EMA50 ({ema_fast_current:.5f}) <= EMA200 ({ema_slow_current:.5f}) - trend is BEARISH")
        else:  # SELL
            # For SHORT: EMA50 should be below EMA200
            passed = ema_fast_current < ema_slow_current
            message = (f"EMA50 ({ema_fast_current:.5f}) < EMA200 ({ema_slow_current:.5f})"
                      if passed else
                      f"EMA50 ({ema_fast_current:.5f}) >= EMA200 ({ema_slow_current:.5f}) - trend is BULLISH")

        return FilterResult(
            passed=passed,
            value=ema_fast_current,
            threshold=ema_slow_current,
            message=message
        )


class VolumeFilter:
    """
    Volume Filter

    According to PDF:
    - Current volume > average volume of last 20 candles
    """

    def __init__(self, lookback_period: int = 20):
        """
        Initialize Volume Filter.

        Args:
            lookback_period: Period for average volume calculation (default 20)
        """
        self.lookback_period = lookback_period

    def check(self, df: pd.DataFrame) -> FilterResult:
        """
        Check volume filter.

        Args:
            df: DataFrame with OHLCV data (must have 'volume' or 'tick_volume' column)

        Returns:
            FilterResult with pass/fail status
        """
        # Try different volume column names
        if 'volume' in df.columns:
            volume = df['volume']
        elif 'tick_volume' in df.columns:
            volume = df['tick_volume']
        elif 'Volume' in df.columns:
            volume = df['Volume']
        else:
            return FilterResult(
                passed=True,  # Skip if no volume data
                value=0.0,
                threshold=0.0,
                message="No volume data available - filter skipped"
            )

        if len(df) < self.lookback_period + 1:
            return FilterResult(
                passed=False,
                value=0.0,
                threshold=0.0,
                message=f"Insufficient data (need {self.lookback_period + 1} candles)"
            )

        current_volume = volume.iloc[-1]
        avg_volume = volume.iloc[-self.lookback_period-1:-1].mean()

        passed = current_volume > avg_volume

        message = (f"Volume ({current_volume:.0f}) > Avg({self.lookback_period}) ({avg_volume:.0f})"
                  if passed else
                  f"Volume ({current_volume:.0f}) <= Avg({self.lookback_period}) ({avg_volume:.0f})")

        return FilterResult(
            passed=passed,
            value=current_volume,
            threshold=avg_volume,
            message=message
        )


class VolatilityFilter:
    """
    ATR Volatility Filter

    According to PDF:
    - ATR(14) > average ATR(20)
    """

    def __init__(self, atr_period: int = 14, avg_atr_period: int = 20):
        """
        Initialize Volatility Filter.

        Args:
            atr_period: ATR calculation period (default 14)
            avg_atr_period: Average ATR lookback period (default 20)
        """
        self.atr_period = atr_period
        self.avg_atr_period = avg_atr_period

    def check(self, df: pd.DataFrame) -> FilterResult:
        """
        Check volatility filter.

        Args:
            df: DataFrame with OHLCV data

        Returns:
            FilterResult with pass/fail status
        """
        if len(df) < self.atr_period + self.avg_atr_period + 1:
            return FilterResult(
                passed=False,
                value=0.0,
                threshold=0.0,
                message=f"Insufficient data (need {self.atr_period + self.avg_atr_period + 1} candles)"
            )

        # Calculate ATR series
        atr_series = self._calculate_atr_series(df)

        if atr_series is None or len(atr_series) < self.avg_atr_period + 1:
            return FilterResult(
                passed=False,
                value=0.0,
                threshold=0.0,
                message="Could not calculate ATR"
            )

        current_atr = atr_series.iloc[-1]
        avg_atr = atr_series.iloc[-self.avg_atr_period-1:-1].mean()

        passed = current_atr > avg_atr

        message = (f"ATR(14) ({current_atr:.5f}) > AvgATR({self.avg_atr_period}) ({avg_atr:.5f})"
                  if passed else
                  f"ATR(14) ({current_atr:.5f}) <= AvgATR({self.avg_atr_period}) ({avg_atr:.5f}) - low volatility")

        return FilterResult(
            passed=passed,
            value=current_atr,
            threshold=avg_atr,
            message=message
        )

    def _calculate_atr_series(self, df: pd.DataFrame) -> Optional[pd.Series]:
        """Calculate ATR series for the DataFrame."""
        high = df['high']
        low = df['low']
        close = df['close']

        tr1 = high - low
        tr2 = abs(high - close.shift(1))
        tr3 = abs(low - close.shift(1))

        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        atr = tr.rolling(window=self.atr_period).mean()

        return atr


class RiskRewardFilter:
    """
    Risk:Reward Filter

    According to PDF:
    - Minimum risk:reward ratio: 1:2
    """

    def __init__(self, min_rr_ratio: float = 2.0):
        """
        Initialize R:R Filter.

        Args:
            min_rr_ratio: Minimum reward:risk ratio (default 2.0 = 1:2)
        """
        self.min_rr_ratio = min_rr_ratio

    def check(self, entry_price: float, sl_price: float, tp_price: float) -> FilterResult:
        """
        Check R:R filter.

        Args:
            entry_price: Entry price
            sl_price: Stop loss price
            tp_price: Take profit price

        Returns:
            FilterResult with pass/fail status
        """
        risk = abs(entry_price - sl_price)
        reward = abs(tp_price - entry_price)

        if risk <= 0:
            return FilterResult(
                passed=False,
                value=0.0,
                threshold=self.min_rr_ratio,
                message="Invalid risk (entry == SL)"
            )

        rr_ratio = reward / risk
        passed = rr_ratio >= self.min_rr_ratio

        message = (f"R:R = 1:{rr_ratio:.1f} >= minimum 1:{self.min_rr_ratio}"
                  if passed else
                  f"R:R = 1:{rr_ratio:.1f} < minimum 1:{self.min_rr_ratio}")

        return FilterResult(
            passed=passed,
            value=rr_ratio,
            threshold=self.min_rr_ratio,
            message=message
        )


class AllFilters:
    """
    Combined filter checker for all trading filters.
    """

    def __init__(self,
                 enable_trend_filter: bool = True,
                 enable_volume_filter: bool = True,
                 enable_volatility_filter: bool = True,
                 enable_rr_filter: bool = True,
                 ema_fast: int = 50,
                 ema_slow: int = 200,
                 volume_lookback: int = 20,
                 atr_period: int = 14,
                 avg_atr_period: int = 20,
                 min_rr_ratio: float = 2.0):
        """
        Initialize All Filters.

        Args:
            enable_trend_filter: Enable/disable trend filter
            enable_volume_filter: Enable/disable volume filter
            enable_volatility_filter: Enable/disable volatility filter
            enable_rr_filter: Enable/disable R:R filter
            ema_fast: Fast EMA period
            ema_slow: Slow EMA period
            volume_lookback: Volume average lookback
            atr_period: ATR period
            avg_atr_period: Average ATR period
            min_rr_ratio: Minimum R:R ratio
        """
        self.enable_trend_filter = enable_trend_filter
        self.enable_volume_filter = enable_volume_filter
        self.enable_volatility_filter = enable_volatility_filter
        self.enable_rr_filter = enable_rr_filter

        self.trend_filter = TrendFilter(fast_period=ema_fast, slow_period=ema_slow)
        self.volume_filter = VolumeFilter(lookback_period=volume_lookback)
        self.volatility_filter = VolatilityFilter(atr_period=atr_period, avg_atr_period=avg_atr_period)
        self.rr_filter = RiskRewardFilter(min_rr_ratio=min_rr_ratio)

    def check_all(self, df: pd.DataFrame, direction: str,
                  entry_price: float = None, sl_price: float = None,
                  tp_price: float = None) -> AllFiltersResult:
        """
        Check all enabled filters.

        Args:
            df: DataFrame with OHLCV data
            direction: 'BUY' or 'SELL'
            entry_price: Entry price (for R:R filter)
            sl_price: Stop loss price (for R:R filter)
            tp_price: Take profit price (for R:R filter)

        Returns:
            AllFiltersResult with all filter results
        """
        # Default pass results for disabled filters
        default_pass = FilterResult(passed=True, value=0.0, threshold=0.0, message="Filter disabled")

        # Check trend filter
        if self.enable_trend_filter:
            trend_result = self.trend_filter.check(df, direction)
        else:
            trend_result = FilterResult(passed=True, value=0.0, threshold=0.0, message="Trend filter disabled")

        # Check volume filter
        if self.enable_volume_filter:
            volume_result = self.volume_filter.check(df)
        else:
            volume_result = FilterResult(passed=True, value=0.0, threshold=0.0, message="Volume filter disabled")

        # Check volatility filter
        if self.enable_volatility_filter:
            volatility_result = self.volatility_filter.check(df)
        else:
            volatility_result = FilterResult(passed=True, value=0.0, threshold=0.0, message="Volatility filter disabled")

        # Check R:R filter
        if self.enable_rr_filter and entry_price and sl_price and tp_price:
            rr_result = self.rr_filter.check(entry_price, sl_price, tp_price)
        else:
            rr_result = FilterResult(passed=True, value=0.0, threshold=0.0, message="R:R filter disabled/skipped")

        # Determine if all passed
        all_passed = (trend_result.passed and
                     volume_result.passed and
                     volatility_result.passed and
                     rr_result.passed)

        # Find what blocked if any
        blocked_by = None
        if not all_passed:
            if not trend_result.passed:
                blocked_by = "Trend Filter"
            elif not volume_result.passed:
                blocked_by = "Volume Filter"
            elif not volatility_result.passed:
                blocked_by = "Volatility Filter"
            elif not rr_result.passed:
                blocked_by = "R:R Filter"

        return AllFiltersResult(
            trend_filter=trend_result,
            volume_filter=volume_result,
            volatility_filter=volatility_result,
            all_passed=all_passed,
            blocked_by=blocked_by
        )

    def get_filter_status(self, result: AllFiltersResult) -> str:
        """Get a formatted status string of all filters."""
        status = []
        status.append(f"Trend: {'✅' if result.trend_filter.passed else '❌'}")
        status.append(f"Volume: {'✅' if result.volume_filter.passed else '❌'}")
        status.append(f"Volatility: {'✅' if result.volatility_filter.passed else '❌'}")

        return " | ".join(status)
