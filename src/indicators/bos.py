"""
Break of Structure (BOS) Indicator

Detects impulsive moves that break previous swing highs/lows
with confirmation of Imbalance (IPA) and optional Liquidity Sweep.
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
class BOSResult:
    """Result of BOS detection"""
    detected: bool
    direction: TrendDirection
    swing_point: Optional[SwingPoint]
    breakout_candle: Optional[int]
    imbalance_start: Optional[float]
    imbalance_end: Optional[float]
    liquidity_sweep: bool


class BOSDetector:
    """
    Break of Structure Detector
    """

    def __init__(self, lookback: int = 50, min_imbalance_pips: float = 5.0):
        self.lookback = lookback
        self.min_imbalance_pips = min_imbalance_pips

    def detect_bos(self, df: pd.DataFrame, require_imbalance: bool = True) -> BOSResult:
        """Detect Break of Structure."""
        if len(df) < self.lookback:
            return BOSResult(False, TrendDirection.NEUTRAL, None, None, None, None, False)

        # Find swing points
        swing_highs, swing_lows = self._find_swings(df)

        current_idx = len(df) - 1
        current = df.iloc[current_idx]

        # Bearish BOS
        for swing in reversed(swing_lows):
            if current_idx - swing.index > self.lookback or current_idx - swing.index < 3:
                continue
            if current['close'] < swing.price:
                has_imb, imb_s, imb_e = self._check_imbalance(df, current_idx)
                if require_imbalance and not has_imb:
                    continue
                liq = self._check_liquidity(df, swing, current_idx)
                return BOSResult(True, TrendDirection.BEARISH, swing, current_idx,
                                imb_s if has_imb else None, imb_e if has_imb else None, liq)

        # Bullish BOS
        for swing in reversed(swing_highs):
            if current_idx - swing.index > self.lookback or current_idx - swing.index < 3:
                continue
            if current['close'] > swing.price:
                has_imb, imb_s, imb_e = self._check_imbalance(df, current_idx)
                if require_imbalance and not has_imb:
                    continue
                liq = self._check_liquidity(df, swing, current_idx)
                return BOSResult(True, TrendDirection.BULLISH, swing, current_idx,
                                imb_s if has_imb else None, imb_e if has_imb else None, liq)

        return BOSResult(False, TrendDirection.NEUTRAL, None, None, None, None, False)

    def _find_swings(self, df: pd.DataFrame) -> Tuple[List[SwingPoint], List[SwingPoint]]:
        """Find swing highs and lows."""
        highs, lows = [], []
        for i in range(2, len(df) - 2):
            h, l = df['high'].iloc[i], df['low'].iloc[i]
            # Swing high
            if (h > df['high'].iloc[i-1] and h > df['high'].iloc[i-2] and
                h > df['high'].iloc[i+1] and h > df['high'].iloc[i+2]):
                highs.append(SwingPoint(i, h, True, df.index[i]))
            # Swing low
            if (l < df['low'].iloc[i-1] and l < df['low'].iloc[i-2] and
                l < df['low'].iloc[i+1] and l < df['low'].iloc[i+2]):
                lows.append(SwingPoint(i, l, False, df.index[i]))
        return highs, lows

    def _check_imbalance(self, df: pd.DataFrame, idx: int) -> Tuple[bool, Optional[float], Optional[float]]:
        """Check for imbalance (IPA)."""
        if idx < 2:
            return False, None, None
        c1, c3 = df.iloc[idx-2], df.iloc[idx]
        min_gap = self.min_imbalance_pips * 0.0001
        # Bearish gap
        if c1['low'] > c3['high'] and (c1['low'] - c3['high']) >= min_gap:
            return True, c1['low'], c3['high']
        # Bullish gap
        if c3['low'] > c1['high'] and (c3['low'] - c1['high']) >= min_gap:
            return True, c1['high'], c3['low']
        return False, None, None

    def _check_liquidity(self, df: pd.DataFrame, swing: SwingPoint, idx: int) -> bool:
        """Check for liquidity sweep."""
        for i in range(max(0, idx-5), idx):
            c = df.iloc[i]
            if swing.is_high:
                if c['high'] > swing.price and c['close'] < swing.price:
                    return True
            else:
                if c['low'] < swing.price and c['close'] > swing.price:
                    return True
        return False

    def find_swing_points(self, df: pd.DataFrame) -> Tuple[List[SwingPoint], List[SwingPoint]]:
        """Public method for finding swing points."""
        return self._find_swings(df)

    def detect_imbalance(self, df: pd.DataFrame, idx: int) -> Tuple[bool, Optional[float], Optional[float]]:
        """Public method for imbalance detection."""
        return self._check_imbalance(df, idx)

    def detect_liquidity_sweep(self, df: pd.DataFrame, swing: SwingPoint, idx: int) -> bool:
        """Public method for liquidity sweep detection."""
        return self._check_liquidity(df, swing, idx)
