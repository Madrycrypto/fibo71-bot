"""
Break of Market Structure (BMS) Detector

Detects BMS with momentum confirmation according to PDF specification:
- Swing detection (5-candle lookback)
- BMS condition: close > last_swing_high (bullish) or close < last_swing_low (bearish)
- Momentum filter: 3 consecutive candles in direction
- Each momentum candle body >= 60% of range
- Distance filter: (close - swing_point) > 0.5 * ATR(14)
"""

import pandas as pd
import numpy as np
from dataclasses import dataclass
from enum import Enum
from typing import Optional, List, Tuple


class TrendDirection(Enum):
    BULLISH = 1
    BEARISH = -1
    NEUTRAL = 0


@dataclass
class SwingPoint:
    """Represents a swing high or low"""
    index: int
    price: float
    is_high: bool
    timestamp: pd.Timestamp


@dataclass
class BMSResult:
    """Result of BMS detection"""
    detected: bool
    direction: TrendDirection
    swing_high_before_bms: Optional[SwingPoint]
    swing_low_before_bms: Optional[SwingPoint]
    breakout_candle_index: Optional[int]
    momentum_candles: int  # Number of consecutive momentum candles
    distance_atr: float  # Distance in ATR multiples
    message: str = ""


class BMSDetector:
    """
    Break of Market Structure Detector

    According to PDF specification:
    1. Swing High: high[i] > high[i-1] AND high[i] > high[i+1]
    2. Swing Low: low[i] < low[i-1] AND low[i] < low[i+1]
    3. Lookback window: 5 candles
    4. BMS condition: close > last_swing_high (bullish)
    5. Momentum filter: 3 consecutive bullish candles
    6. Body filter: each candle body >= 60% of range
    7. Distance filter: > 0.5 * ATR(14)
    """

    def __init__(self,
                 swing_lookback: int = 5,
                 momentum_candles_required: int = 3,
                 body_percent_threshold: float = 0.60,
                 distance_atr_threshold: float = 0.5,
                 atr_period: int = 14):
        """
        Initialize BMS Detector.

        Args:
            swing_lookback: Lookback window for swing detection (default 5)
            momentum_candles_required: Number of consecutive momentum candles (default 3)
            body_percent_threshold: Minimum body as % of range (default 0.60 = 60%)
            distance_atr_threshold: Minimum distance in ATR multiples (default 0.5)
            atr_period: ATR period for distance filter (default 14)
        """
        self.swing_lookback = swing_lookback
        self.momentum_candles_required = momentum_candles_required
        self.body_percent_threshold = body_percent_threshold
        self.distance_atr_threshold = distance_atr_threshold
        self.atr_period = atr_period

    def detect_bms(self, df: pd.DataFrame,
                   enable_momentum_filter: bool = True,
                   enable_body_filter: bool = True,
                   enable_distance_filter: bool = True) -> BMSResult:
        """
        Detect Break of Market Structure.

        Args:
            df: DataFrame with OHLCV data
            enable_momentum_filter: Enable/disable momentum filter
            enable_body_filter: Enable/disable body size filter
            enable_distance_filter: Enable/disable distance filter

        Returns:
            BMSResult with detection details
        """
        if len(df) < max(self.swing_lookback * 2, self.atr_period + 5):
            return BMSResult(
                detected=False,
                direction=TrendDirection.NEUTRAL,
                swing_high_before_bms=None,
                swing_low_before_bms=None,
                breakout_candle_index=None,
                momentum_candles=0,
                distance_atr=0.0,
                message="Insufficient data"
            )

        # Calculate ATR
        atr = self._calculate_atr(df)

        # Find swing points
        swing_highs, swing_lows = self._find_swings(df)

        if not swing_highs and not swing_lows:
            return BMSResult(
                detected=False,
                direction=TrendDirection.NEUTRAL,
                swing_high_before_bms=None,
                swing_low_before_bms=None,
                breakout_candle_index=None,
                momentum_candles=0,
                distance_atr=0.0,
                message="No swing points found"
            )

        current_idx = len(df) - 1

        # Try BULLISH BMS
        result = self._detect_bullish_bms(
            df, swing_highs, swing_lows, current_idx, atr,
            enable_momentum_filter, enable_body_filter, enable_distance_filter
        )
        if result.detected:
            return result

        # Try BEARISH BMS
        result = self._detect_bearish_bms(
            df, swing_highs, swing_lows, current_idx, atr,
            enable_momentum_filter, enable_body_filter, enable_distance_filter
        )
        if result.detected:
            return result

        return BMSResult(
            detected=False,
            direction=TrendDirection.NEUTRAL,
            swing_high_before_bms=None,
            swing_low_before_bms=None,
            breakout_candle_index=None,
            momentum_candles=0,
            distance_atr=0.0,
            message="No BMS detected"
        )

    def _detect_bullish_bms(self, df: pd.DataFrame,
                            swing_highs: List[SwingPoint],
                            swing_lows: List[SwingPoint],
                            current_idx: int,
                            atr: float,
                            enable_momentum: bool,
                            enable_body: bool,
                            enable_distance: bool) -> BMSResult:
        """Detect bullish BMS (close > last_swing_high)"""
        current = df.iloc[current_idx]

        # Get most recent swing high (not too recent, not too old)
        for swing_high in reversed(swing_highs):
            distance = current_idx - swing_high.index

            # Skip if too recent (< 3 candles) or too old (> lookback)
            if distance < 3 or distance > self.swing_lookback * 3:
                continue

            # BMS condition: close > swing_high
            if current['close'] <= swing_high.price:
                continue

            # Get swing low before this swing high
            swing_low_before = self._get_swing_low_before(swing_lows, swing_high.index)

            # Check momentum filter
            momentum_count = 0
            if enable_momentum:
                momentum_count = self._count_momentum_candles(
                    df, current_idx, TrendDirection.BULLISH, enable_body
                )
                if momentum_count < self.momentum_candles_required:
                    continue
            else:
                momentum_count = self._count_momentum_candles(
                    df, current_idx, TrendDirection.BULLISH, False
                )

            # Check distance filter
            distance_atr = (current['close'] - swing_high.price) / atr if atr > 0 else 0
            if enable_distance and distance_atr < self.distance_atr_threshold:
                continue

            return BMSResult(
                detected=True,
                direction=TrendDirection.BULLISH,
                swing_high_before_bms=swing_high,
                swing_low_before_bms=swing_low_before,
                breakout_candle_index=current_idx,
                momentum_candles=momentum_count,
                distance_atr=distance_atr,
                message=f"Bullish BMS: close ({current['close']:.5f}) > swing_high ({swing_high.price:.5f})"
            )

        return BMSResult(
            detected=False,
            direction=TrendDirection.NEUTRAL,
            swing_high_before_bms=None,
            swing_low_before_bms=None,
            breakout_candle_index=None,
            momentum_candles=0,
            distance_atr=0.0,
            message="No bullish BMS"
        )

    def _detect_bearish_bms(self, df: pd.DataFrame,
                            swing_highs: List[SwingPoint],
                            swing_lows: List[SwingPoint],
                            current_idx: int,
                            atr: float,
                            enable_momentum: bool,
                            enable_body: bool,
                            enable_distance: bool) -> BMSResult:
        """Detect bearish BMS (close < last_swing_low)"""
        current = df.iloc[current_idx]

        # Get most recent swing low
        for swing_low in reversed(swing_lows):
            distance = current_idx - swing_low.index

            if distance < 3 or distance > self.swing_lookback * 3:
                continue

            # BMS condition: close < swing_low
            if current['close'] >= swing_low.price:
                continue

            # Get swing high before this swing low
            swing_high_before = self._get_swing_high_before(swing_highs, swing_low.index)

            # Check momentum filter
            momentum_count = 0
            if enable_momentum:
                momentum_count = self._count_momentum_candles(
                    df, current_idx, TrendDirection.BEARISH, enable_body
                )
                if momentum_count < self.momentum_candles_required:
                    continue
            else:
                momentum_count = self._count_momentum_candles(
                    df, current_idx, TrendDirection.BEARISH, False
                )

            # Check distance filter
            distance_atr = (swing_low.price - current['close']) / atr if atr > 0 else 0
            if enable_distance and distance_atr < self.distance_atr_threshold:
                continue

            return BMSResult(
                detected=True,
                direction=TrendDirection.BEARISH,
                swing_high_before_bms=swing_high_before,
                swing_low_before_bms=swing_low,
                breakout_candle_index=current_idx,
                momentum_candles=momentum_count,
                distance_atr=distance_atr,
                message=f"Bearish BMS: close ({current['close']:.5f}) < swing_low ({swing_low.price:.5f})"
            )

        return BMSResult(
            detected=False,
            direction=TrendDirection.NEUTRAL,
            swing_high_before_bms=None,
            swing_low_before_bms=None,
            breakout_candle_index=None,
            momentum_candles=0,
            distance_atr=0.0,
            message="No bearish BMS"
        )

    def _find_swings(self, df: pd.DataFrame) -> Tuple[List[SwingPoint], List[SwingPoint]]:
        """
        Find swing highs and lows.

        Swing High: high[i] > high[i-1] AND high[i] > high[i+1]
        Swing Low: low[i] < low[i-1] AND low[i] < low[i+1]
        """
        highs, lows = [], []

        for i in range(1, len(df) - 1):
            # Swing high
            if (df['high'].iloc[i] > df['high'].iloc[i-1] and
                df['high'].iloc[i] > df['high'].iloc[i+1]):
                highs.append(SwingPoint(
                    index=i,
                    price=df['high'].iloc[i],
                    is_high=True,
                    timestamp=df.index[i] if hasattr(df.index[i], 'strftime') else pd.Timestamp.now()
                ))

            # Swing low
            if (df['low'].iloc[i] < df['low'].iloc[i-1] and
                df['low'].iloc[i] < df['low'].iloc[i+1]):
                lows.append(SwingPoint(
                    index=i,
                    price=df['low'].iloc[i],
                    is_high=False,
                    timestamp=df.index[i] if hasattr(df.index[i], 'strftime') else pd.Timestamp.now()
                ))

        return highs, lows

    def _get_swing_low_before(self, swing_lows: List[SwingPoint],
                               before_index: int) -> Optional[SwingPoint]:
        """Get the most recent swing low before a given index."""
        for swing_low in reversed(swing_lows):
            if swing_low.index < before_index:
                return swing_low
        return None

    def _get_swing_high_before(self, swing_highs: List[SwingPoint],
                                before_index: int) -> Optional[SwingPoint]:
        """Get the most recent swing high before a given index."""
        for swing_high in reversed(swing_highs):
            if swing_high.index < before_index:
                return swing_high
        return None

    def _count_momentum_candles(self, df: pd.DataFrame,
                                current_idx: int,
                                direction: TrendDirection,
                                check_body: bool) -> int:
        """
        Count consecutive momentum candles.

        Args:
            df: DataFrame
            current_idx: Current candle index
            direction: BULLISH or BEARISH
            check_body: Whether to check body size >= 60%

        Returns:
            Number of consecutive momentum candles
        """
        count = 0

        for i in range(current_idx, max(0, current_idx - 10), -1):
            candle = df.iloc[i]
            body = abs(candle['close'] - candle['open'])
            candle_range = candle['high'] - candle['low']

            # Check direction
            if direction == TrendDirection.BULLISH:
                if candle['close'] <= candle['open']:
                    break
            else:  # BEARISH
                if candle['close'] >= candle['open']:
                    break

            # Check body size if required
            if check_body and candle_range > 0:
                body_percent = body / candle_range
                if body_percent < self.body_percent_threshold:
                    break

            count += 1

        return count

    def _calculate_atr(self, df: pd.DataFrame) -> float:
        """Calculate Average True Range."""
        if len(df) < self.atr_period + 1:
            return 0.0

        high = df['high']
        low = df['low']
        close = df['close']

        tr1 = high - low
        tr2 = abs(high - close.shift(1))
        tr3 = abs(low - close.shift(1))

        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        atr = tr.rolling(window=self.atr_period).mean()

        return atr.iloc[-1] if not pd.isna(atr.iloc[-1]) else 0.0

    def find_swing_points(self, df: pd.DataFrame) -> Tuple[List[SwingPoint], List[SwingPoint]]:
        """Public method for finding swing points."""
        return self._find_swings(df)
