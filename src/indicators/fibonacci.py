"""
Fibonacci Retracement Calculator
"""

from dataclasses import dataclass
from typing import Tuple


@dataclass
class FibonacciLevels:
    """Fibonacci retracement levels."""
    swing_high: float
    swing_low: float
    level_0: float      # TP
    level_71: float     # Entry zone start
    level_75: float     # Entry zone middle
    level_79: float     # Entry zone end
    level_100: float    # SL
    direction: str = 'SELL'


class FibonacciCalculator:
    """Calculate Fibonacci levels for CP 2.0 strategy."""

    def __init__(self, entry_min: float = 0.71, entry_max: float = 0.79):
        self.entry_min = entry_min
        self.entry_max = entry_max

    def calculate_levels(self, swing_high: float, swing_low: float,
                         direction: str) -> FibonacciLevels:
        """Calculate Fibonacci levels."""
        direction = direction.upper()
        range_size = swing_high - swing_low

        if direction == 'SELL':
            # Bearish: price dropped from high to low
            level_0 = swing_low
            level_100 = swing_high
            level_71 = swing_low + range_size * self.entry_min
            level_75 = swing_low + range_size * 0.75
            level_79 = swing_low + range_size * self.entry_max
        else:  # BUY
            # Bullish: price rose from low to high
            level_0 = swing_high
            level_100 = swing_low
            level_71 = swing_high - range_size * self.entry_min
            level_75 = swing_high - range_size * 0.75
            level_79 = swing_high - range_size * self.entry_max

        return FibonacciLevels(
            swing_high=swing_high,
            swing_low=swing_low,
            level_0=level_0,
            level_71=level_71,
            level_75=level_75,
            level_79=level_79,
            level_100=level_100,
            direction=direction
        )

    def is_in_entry_zone(self, price: float, levels: FibonacciLevels) -> Tuple[bool, float]:
        """Check if price is in entry zone."""
        if levels.direction == 'SELL':
            if levels.level_79 <= price <= levels.level_71:
                return True, (price - levels.level_0) / (levels.level_100 - levels.level_0)
        else:
            if levels.level_79 <= price <= levels.level_71:
                return True, (levels.level_0 - price) / (levels.level_0 - levels.level_100)
        return False, 0.0
