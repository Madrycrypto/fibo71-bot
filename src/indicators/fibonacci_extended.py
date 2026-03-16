"""
Extended Fibonacci Calculator for BMS Strategy

Implements Fibonacci levels according to PDF specification:
- Entry zone: 0.62 to 0.71 retracement
- TP1: Previous high/low (0% level)
- TP2: Fibonacci extension 1.27
- TP3: Fibonacci extension 1.62
"""

from dataclasses import dataclass
from typing import Tuple, Optional


@dataclass
class FibonacciExtendedLevels:
    """Extended Fibonacci retracement and extension levels."""
    swing_high: float
    swing_low: float
    range_size: float
    direction: str  # 'BUY' or 'SELL'

    # Retracement levels
    level_0: float       # TP1 - Previous high/low
    level_236: float     # 0.236
    level_382: float     # 0.382
    level_500: float     # 0.500
    level_618: float     # 0.618 - Entry zone start
    level_650: float     # 0.650
    level_710: float     # 0.710 - Entry zone end
    level_786: float     # 0.786
    level_1000: float    # 1.000 - SL level

    # Extension levels
    ext_127: float       # 1.27 extension - TP2
    ext_162: float       # 1.62 extension - TP3

    # Entry zone
    entry_zone_min: float  # 0.62
    entry_zone_max: float  # 0.71


class FibonacciExtendedCalculator:
    """
    Extended Fibonacci Calculator for BMS Strategy.

    Entry Zone: 0.62 to 0.71 retracement
    TP1: Previous high (for LONG) or low (for SHORT) = 0% level
    TP2: 1.27 Fibonacci extension
    TP3: 1.62 Fibonacci extension
    SL: Below swing low (for LONG) or above swing high (for SHORT)
    """

    def __init__(self,
                 entry_zone_min: float = 0.62,
                 entry_zone_max: float = 0.71):
        """
        Initialize Fibonacci Calculator.

        Args:
            entry_zone_min: Minimum Fibonacci level for entry (default 0.62)
            entry_zone_max: Maximum Fibonacci level for entry (default 0.71)
        """
        self.entry_zone_min = entry_zone_min
        self.entry_zone_max = entry_zone_max

    def calculate_levels(self, swing_high: float, swing_low: float,
                         direction: str) -> FibonacciExtendedLevels:
        """
        Calculate all Fibonacci levels.

        Args:
            swing_high: Swing high price
            swing_low: Swing low price
            direction: 'BUY' or 'SELL'

        Returns:
            FibonacciExtendedLevels with all calculated levels
        """
        direction = direction.upper()
        range_size = swing_high - swing_low

        # Standard retracement levels (0 to 1)
        # For BUY (LONG): We expect price to retrace DOWN from swing_high
        # For SELL (SHORT): We expect price to retrace UP from swing_low

        if direction == 'BUY':
            # LONG: Price broke above swing_high, expecting retracement DOWN
            # 0% is at swing_high (where price broke from)
            # 100% is at swing_low (full retracement = SL)
            level_0 = swing_high
            level_1000 = swing_low

            # Retracement levels (going DOWN from high)
            level_236 = swing_high - range_size * 0.236
            level_382 = swing_high - range_size * 0.382
            level_500 = swing_high - range_size * 0.500
            level_618 = swing_high - range_size * 0.618
            level_650 = swing_high - range_size * 0.650
            level_710 = swing_high - range_size * 0.710
            level_786 = swing_high - range_size * 0.786

            # Extensions (going UP above high)
            ext_127 = swing_high + range_size * 0.27
            ext_162 = swing_high + range_size * 0.62

            # Entry zone
            entry_zone_min_price = level_618
            entry_zone_max_price = level_710

        else:  # SELL
            # SHORT: Price broke below swing_low, expecting retracement UP
            # 0% is at swing_low (where price broke from)
            # 100% is at swing_high (full retracement = SL)
            level_0 = swing_low
            level_1000 = swing_high

            # Retracement levels (going UP from low)
            level_236 = swing_low + range_size * 0.236
            level_382 = swing_low + range_size * 0.382
            level_500 = swing_low + range_size * 0.500
            level_618 = swing_low + range_size * 0.618
            level_650 = swing_low + range_size * 0.650
            level_710 = swing_low + range_size * 0.710
            level_786 = swing_low + range_size * 0.786

            # Extensions (going DOWN below low)
            ext_127 = swing_low - range_size * 0.27
            ext_162 = swing_low - range_size * 0.62

            # Entry zone
            entry_zone_min_price = level_618
            entry_zone_max_price = level_710

        return FibonacciExtendedLevels(
            swing_high=swing_high,
            swing_low=swing_low,
            range_size=range_size,
            direction=direction,
            level_0=level_0,
            level_236=level_236,
            level_382=level_382,
            level_500=level_500,
            level_618=level_618,
            level_650=level_650,
            level_710=level_710,
            level_786=level_786,
            level_1000=level_1000,
            ext_127=ext_127,
            ext_162=ext_162,
            entry_zone_min=entry_zone_min_price,
            entry_zone_max=entry_zone_max_price
        )

    def is_in_entry_zone(self, price: float, levels: FibonacciExtendedLevels) -> Tuple[bool, float]:
        """
        Check if price is in the Fibonacci entry zone (0.62 - 0.71).

        Args:
            price: Current price
            levels: FibonacciExtendedLevels object

        Returns:
            Tuple of (is_in_zone, fib_percentage)
        """
        if levels.direction == 'BUY':
            # For LONG: price should be between 0.71 and 0.62 (lower is deeper retracement)
            if levels.entry_zone_max <= price <= levels.entry_zone_min:
                # Calculate fib percentage
                if levels.range_size > 0:
                    fib_pct = (levels.swing_high - price) / levels.range_size
                else:
                    fib_pct = 0.0
                return True, fib_pct
        else:  # SELL
            # For SHORT: price should be between 0.62 and 0.71 (higher is deeper retracement)
            if levels.entry_zone_min <= price <= levels.entry_zone_max:
                if levels.range_size > 0:
                    fib_pct = (price - levels.swing_low) / levels.range_size
                else:
                    fib_pct = 0.0
                return True, fib_pct

        return False, 0.0

    def calculate_sl_with_buffer(self, levels: FibonacciExtendedLevels,
                                  buffer_percent: float = 0.1) -> float:
        """
        Calculate stop loss with buffer.

        Args:
            levels: FibonacciExtendedLevels object
            buffer_percent: Buffer as percentage of price (default 0.1%)

        Returns:
            SL price with buffer
        """
        if levels.direction == 'BUY':
            # For LONG: SL below swing_low
            sl = levels.swing_low * (1 - buffer_percent / 100)
        else:
            # For SHORT: SL above swing_high
            sl = levels.swing_high * (1 + buffer_percent / 100)

        return sl

    def calculate_rr_ratio(self, entry_price: float, sl_price: float,
                           tp_price: float) -> float:
        """
        Calculate Risk:Reward ratio.

        Args:
            entry_price: Entry price
            sl_price: Stop loss price
            tp_price: Take profit price

        Returns:
            R:R ratio (e.g., 2.0 means 1:2 risk:reward)
        """
        risk = abs(entry_price - sl_price)
        reward = abs(tp_price - entry_price)

        if risk <= 0:
            return 0.0

        return reward / risk

    def get_best_entry_price(self, levels: FibonacciExtendedLevels,
                             preferred_level: float = 0.65) -> float:
        """
        Get the best entry price within the zone.

        Args:
            levels: FibonacciExtendedLevels object
            preferred_level: Preferred Fibonacci level (default 0.65)

        Returns:
            Entry price
        """
        range_size = levels.range_size

        if levels.direction == 'BUY':
            entry = levels.swing_high - range_size * preferred_level
        else:
            entry = levels.swing_low + range_size * preferred_level

        return entry

    def get_tp_levels(self, levels: FibonacciExtendedLevels) -> dict:
        """
        Get all take profit levels with percentages.

        Returns:
            Dictionary with TP levels and close percentages
        """
        return {
            'TP1': {'price': levels.level_0, 'close_pct': 33, 'name': 'Previous High/Low'},
            'TP2': {'price': levels.ext_127, 'close_pct': 33, 'name': 'Fib 1.27 Extension'},
            'TP3': {'price': levels.ext_162, 'close_pct': 34, 'name': 'Fib 1.62 Extension'}
        }
