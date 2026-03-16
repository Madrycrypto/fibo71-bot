"""
Liquidity Sweep Detector

Implements liquidity sweep detection according to PDF specification:
- low_current < low_previous (for bullish sweep)
- close_current > fib_0.62
- Wick length >= 2 * body size (ideal >= 3 * body)
"""

import pandas as pd
import numpy as np
from dataclasses import dataclass
from typing import Optional, Tuple
from enum import Enum


class SweepDirection(Enum):
    BULLISH = 1   # Sweep below, close above (long setup)
    BEARISH = -1  # Sweep above, close below (short setup)
    NONE = 0


@dataclass
class LiquiditySweepResult:
    """Result of liquidity sweep detection."""
    detected: bool
    direction: SweepDirection
    sweep_candle_index: int
    sweep_low: float  # The lowest point of the sweep
    sweep_high: float  # The highest point of the sweep
    close_price: float
    body_size: float
    wick_size: float
    wick_to_body_ratio: float
    is_ideal: bool  # Wick >= 3 * body
    message: str = ""


class LiquiditySweepDetector:
    """
    Liquidity Sweep Detector

    According to PDF specification:
    - For LONG: low_current < low_previous AND close_current > fib_0.62
    - Wick length >= 2 * body size (minimum)
    - Wick length >= 3 * body size (ideal)

    The sweep indicates that stop losses below a swing low have been triggered,
    and price has quickly reversed back up - a classic liquidity grab.
    """

    def __init__(self,
                 min_wick_to_body_ratio: float = 2.0,
                 ideal_wick_to_body_ratio: float = 3.0,
                 lookback_candles: int = 5):
        """
        Initialize Liquidity Sweep Detector.

        Args:
            min_wick_to_body_ratio: Minimum wick/body ratio (default 2.0)
            ideal_wick_to_body_ratio: Ideal wick/body ratio (default 3.0)
            lookback_candles: How many candles back to check for new low/high (default 5)
        """
        self.min_wick_to_body_ratio = min_wick_to_body_ratio
        self.ideal_wick_to_body_ratio = ideal_wick_to_body_ratio
        self.lookback_candles = lookback_candles

    def detect_sweep(self, df: pd.DataFrame,
                     fib_062_level: float,
                     direction: str,
                     enable_wick_filter: bool = True) -> LiquiditySweepResult:
        """
        Detect liquidity sweep.

        Args:
            df: DataFrame with OHLCV data
            fib_062_level: The Fibonacci 0.62 level price
            direction: 'BUY' or 'SELL' (direction of expected trade)
            enable_wick_filter: Enable/disable wick size filter

        Returns:
            LiquiditySweepResult with detection details
        """
        if len(df) < self.lookback_candles + 1:
            return LiquiditySweepResult(
                detected=False,
                direction=SweepDirection.NONE,
                sweep_candle_index=-1,
                sweep_low=0.0,
                sweep_high=0.0,
                close_price=0.0,
                body_size=0.0,
                wick_size=0.0,
                wick_to_body_ratio=0.0,
                is_ideal=False,
                message="Insufficient data"
            )

        current_idx = len(df) - 1
        current = df.iloc[current_idx]

        direction = direction.upper()

        if direction == 'BUY':
            return self._detect_bullish_sweep(
                df, current_idx, fib_062_level, enable_wick_filter
            )
        else:
            return self._detect_bearish_sweep(
                df, current_idx, fib_062_level, enable_wick_filter
            )

    def _detect_bullish_sweep(self, df: pd.DataFrame,
                              current_idx: int,
                              fib_062_level: float,
                              enable_wick_filter: bool) -> LiquiditySweepResult:
        """
        Detect bullish liquidity sweep (for LONG entries).

        Conditions:
        1. Current low < previous low (new low made)
        2. Current close > fib_0.62 (closed back above Fib level)
        3. Wick (lower) >= 2 * body (minimum)
        4. Wick (lower) >= 3 * body (ideal)
        """
        current = df.iloc[current_idx]
        previous = df.iloc[current_idx - 1]

        # Condition 1: Current low < previous low (made new low)
        if current['low'] >= previous['low']:
            return LiquiditySweepResult(
                detected=False,
                direction=SweepDirection.NONE,
                sweep_candle_index=current_idx,
                sweep_low=current['low'],
                sweep_high=current['high'],
                close_price=current['close'],
                body_size=0.0,
                wick_size=0.0,
                wick_to_body_ratio=0.0,
                is_ideal=False,
                message="No new low made"
            )

        # Condition 2: Close > fib_0.62
        if current['close'] <= fib_062_level:
            return LiquiditySweepResult(
                detected=False,
                direction=SweepDirection.NONE,
                sweep_candle_index=current_idx,
                sweep_low=current['low'],
                sweep_high=current['high'],
                close_price=current['close'],
                body_size=0.0,
                wick_size=0.0,
                wick_to_body_ratio=0.0,
                is_ideal=False,
                message=f"Close ({current['close']:.5f}) not above fib_0.62 ({fib_062_level:.5f})"
            )

        # Calculate candle metrics
        body_size = abs(current['close'] - current['open'])
        lower_wick = min(current['open'], current['close']) - current['low']
        upper_wick = current['high'] - max(current['open'], current['close'])

        # For bullish sweep, we care about the lower wick
        wick_size = lower_wick

        # Avoid division by zero
        if body_size == 0:
            body_size = 0.00001  # Small value to avoid division by zero

        wick_to_body = wick_size / body_size

        # Condition 3: Wick filter
        if enable_wick_filter:
            if wick_to_body < self.min_wick_to_body_ratio:
                return LiquiditySweepResult(
                    detected=False,
                    direction=SweepDirection.NONE,
                    sweep_candle_index=current_idx,
                    sweep_low=current['low'],
                    sweep_high=current['high'],
                    close_price=current['close'],
                    body_size=body_size,
                    wick_size=wick_size,
                    wick_to_body_ratio=wick_to_body,
                    is_ideal=False,
                    message=f"Wick/body ratio ({wick_to_body:.2f}) < minimum ({self.min_wick_to_body_ratio})"
                )

        # Check if ideal
        is_ideal = wick_to_body >= self.ideal_wick_to_body_ratio

        return LiquiditySweepResult(
            detected=True,
            direction=SweepDirection.BULLISH,
            sweep_candle_index=current_idx,
            sweep_low=current['low'],
            sweep_high=current['high'],
            close_price=current['close'],
            body_size=body_size,
            wick_size=wick_size,
            wick_to_body_ratio=wick_to_body,
            is_ideal=is_ideal,
            message=f"Bullish sweep detected at {current['low']:.5f}, wick/body: {wick_to_body:.2f}x"
        )

    def _detect_bearish_sweep(self, df: pd.DataFrame,
                              current_idx: int,
                              fib_062_level: float,
                              enable_wick_filter: bool) -> LiquiditySweepResult:
        """
        Detect bearish liquidity sweep (for SHORT entries).

        Conditions:
        1. Current high > previous high (new high made)
        2. Current close < fib_0.62 (closed back below Fib level)
        3. Wick (upper) >= 2 * body (minimum)
        4. Wick (upper) >= 3 * body (ideal)
        """
        current = df.iloc[current_idx]
        previous = df.iloc[current_idx - 1]

        # Condition 1: Current high > previous high (made new high)
        if current['high'] <= previous['high']:
            return LiquiditySweepResult(
                detected=False,
                direction=SweepDirection.NONE,
                sweep_candle_index=current_idx,
                sweep_low=current['low'],
                sweep_high=current['high'],
                close_price=current['close'],
                body_size=0.0,
                wick_size=0.0,
                wick_to_body_ratio=0.0,
                is_ideal=False,
                message="No new high made"
            )

        # Condition 2: Close < fib_0.62
        if current['close'] >= fib_062_level:
            return LiquiditySweepResult(
                detected=False,
                direction=SweepDirection.NONE,
                sweep_candle_index=current_idx,
                sweep_low=current['low'],
                sweep_high=current['high'],
                close_price=current['close'],
                body_size=0.0,
                wick_size=0.0,
                wick_to_body_ratio=0.0,
                is_ideal=False,
                message=f"Close ({current['close']:.5f}) not below fib_0.62 ({fib_062_level:.5f})"
            )

        # Calculate candle metrics
        body_size = abs(current['close'] - current['open'])
        lower_wick = min(current['open'], current['close']) - current['low']
        upper_wick = current['high'] - max(current['open'], current['close'])

        # For bearish sweep, we care about the upper wick
        wick_size = upper_wick

        # Avoid division by zero
        if body_size == 0:
            body_size = 0.00001

        wick_to_body = wick_size / body_size

        # Condition 3: Wick filter
        if enable_wick_filter:
            if wick_to_body < self.min_wick_to_body_ratio:
                return LiquiditySweepResult(
                    detected=False,
                    direction=SweepDirection.NONE,
                    sweep_candle_index=current_idx,
                    sweep_low=current['low'],
                    sweep_high=current['high'],
                    close_price=current['close'],
                    body_size=body_size,
                    wick_size=wick_size,
                    wick_to_body_ratio=wick_to_body,
                    is_ideal=False,
                    message=f"Wick/body ratio ({wick_to_body:.2f}) < minimum ({self.min_wick_to_body_ratio})"
                )

        # Check if ideal
        is_ideal = wick_to_body >= self.ideal_wick_to_body_ratio

        return LiquiditySweepResult(
            detected=True,
            direction=SweepDirection.BEARISH,
            sweep_candle_index=current_idx,
            sweep_low=current['low'],
            sweep_high=current['high'],
            close_price=current['close'],
            body_size=body_size,
            wick_size=wick_size,
            wick_to_body_ratio=wick_to_body,
            is_ideal=is_ideal,
            message=f"Bearish sweep detected at {current['high']:.5f}, wick/body: {wick_to_body:.2f}x"
        )

    def check_confirmation_candle(self, df: pd.DataFrame,
                                  direction: str,
                                  min_body_percent: float = 0.50) -> Tuple[bool, str]:
        """
        Check if the current candle is a valid confirmation candle.

        According to PDF:
        - Bullish candle required (close > open)
        - Body >= 50% of candle range

        Args:
            df: DataFrame with OHLCV data
            direction: 'BUY' or 'SELL'
            min_body_percent: Minimum body as % of range (default 50%)

        Returns:
            Tuple of (is_valid, message)
        """
        if len(df) < 1:
            return False, "No data"

        current = df.iloc[-1]
        body = abs(current['close'] - current['open'])
        candle_range = current['high'] - current['low']

        direction = direction.upper()

        # Check direction
        if direction == 'BUY':
            if current['close'] <= current['open']:
                return False, "Not a bullish candle (close <= open)"
        else:  # SELL
            if current['close'] >= current['open']:
                return False, "Not a bearish candle (close >= open)"

        # Check body size
        if candle_range > 0:
            body_percent = body / candle_range
            if body_percent < min_body_percent:
                return False, f"Body ({body_percent*100:.1f}%) < required ({min_body_percent*100:.1f}%)"
        else:
            return False, "Candle range is zero"

        return True, f"Valid confirmation candle (body: {body/candle_range*100:.1f}%)"
