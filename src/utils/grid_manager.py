"""
Grid Order Manager for BMS Fibo Liquidity Strategy

Supports multiple entry points within the Fibonacci zone:
- Equal spacing: orders evenly distributed
- Fib spacing: orders at Fib levels
- Custom spacing: user-defined levels

Risk is distributed across all orders.
"""

from dataclasses import dataclass
from typing import List, Optional
from enum import Enum


class SpacingMode(Enum):
    EQUAL = "equal"          # Evenly spaced orders
    FIBONACCI = "fib"        # At Fibonacci levels
    CUSTOM = "custom"        # User-defined


class DistributionMode(Enum):
    EQUAL = "equal"          # Equal risk per order
    WEIGHTED = "weighted"    # More weight at better levels


@dataclass
class GridOrder:
    """Single grid order."""
    level: float           # Fibonacci level (0.62, 0.65, etc.)
    price: float          # Actual price
    risk_percent: float   # Risk % for this order
    lot_size: float       # Position size
    order_id: Optional[str] = None
    filled: bool = False


@dataclass
class GridConfig:
    """Grid configuration."""
    enabled: bool = True
    orders_count: int = 5
    spacing_mode: SpacingMode = SpacingMode.EQUAL
    distribution_mode: DistributionMode = DistributionMode.EQUAL
    custom_levels: Optional[List[float]] = None  # e.g., [0.62, 0.65, 0.68, 0.71]


class GridOrderManager:
    """
    Manages grid orders within Fibonacci entry zone.
    """

    def __init__(self, config: GridConfig):
        self.config = config
        self.orders: List[GridOrder] = []
        self.total_risk_percent = 0.0

    def calculate_grid_levels(self, entry_zone_min: float, entry_zone_max: float) -> List[float]:
        """
        Calculate Fibonacci levels for grid orders.

        Args:
            entry_zone_min: Minimum Fib level (e.g., 0.62)
            entry_zone_max: Maximum Fib level (e.g., 0.71)

        Returns:
            List of Fibonacci levels for orders
        """
        if self.config.spacing_mode == SpacingMode.CUSTOM and self.config.custom_levels:
            # Filter custom levels to be within zone
            return [l for l in self.config.custom_levels
                    if entry_zone_min <= l <= entry_zone_max]

        elif self.config.spacing_mode == SpacingMode.FIBONACCI:
            # Use Fibonacci levels within zone
            fib_levels = [0.382, 0.5, 0.618, 0.65, 0.70, 0.786]
            return [l for l in fib_levels
                    if entry_zone_min <= l <= entry_zone_max][:self.config.orders_count]

        else:  # EQUAL spacing
            if self.config.orders_count == 1:
                return [(entry_zone_min + entry_zone_max) / 2]

            step = (entry_zone_max - entry_zone_min) / (self.config.orders_count - 1)
            return [entry_zone_min + i * step for i in range(self.config.orders_count)]

    def calculate_risk_distribution(self, total_risk: float) -> List[float]:
        """
        Calculate risk per order.

        Args:
            total_risk: Total risk % for all orders (e.g., 1.0)

        Returns:
            List of risk % per order
        """
        count = len(self.orders) if self.orders else self.config.orders_count

        if self.config.distribution_mode == DistributionMode.WEIGHTED:
            # More weight at lower prices for LONG, higher for SHORT
            weights = [1.0 + (i * 0.2) for i in range(count)]
            total_weight = sum(weights)
            return [total_risk * w / total_weight for w in weights]
        else:  # EQUAL
            per_order = total_risk / count
            return [per_order] * count

    def create_grid_orders(self,
                           entry_zone_min: float,
                           entry_zone_max: float,
                           fib_high: float,
                           fib_low: float,
                           total_risk_percent: float,
                           direction: str) -> List[GridOrder]:
        """
        Create grid orders within the Fibonacci zone.

        Args:
            entry_zone_min: Min Fib level (0.62)
            entry_zone_max: Max Fib level (0.71)
            fib_high: High price for Fib calculation
            fib_low: Low price for Fib calculation
            total_risk_percent: Total risk % (e.g., 1.0)
            direction: 'BUY' or 'SELL'

        Returns:
            List of GridOrder objects
        """
        # Calculate levels
        levels = self.calculate_grid_levels(entry_zone_min, entry_zone_max)

        # Ensure we have the requested number of orders
        while len(levels) < self.config.orders_count:
            # Add intermediate levels
            if len(levels) >= 2:
                mid = (levels[-1] + levels[-2]) / 2
                levels.insert(-1, mid)
            else:
                levels.append((entry_zone_min + entry_zone_max) / 2)

        levels = levels[:self.config.orders_count]

        # Calculate prices from Fib levels
        fib_range = fib_high - fib_low
        prices = []
        for level in levels:
            # Fib level to price: higher level = lower price
            price = fib_high - (fib_range * level)
            prices.append(price)

        # Calculate risk distribution
        risks = self.calculate_risk_distribution(total_risk_percent)

        # Create orders
        self.orders = []
        for i, (level, price, risk) in enumerate(zip(levels, prices, risks)):
            order = GridOrder(
                level=level,
                price=price,
                risk_percent=risk,
                lot_size=0.0  # Will be calculated later
            )
            self.orders.append(order)

        self.total_risk_percent = total_risk_percent
        return self.orders

    def calculate_lot_sizes(self, account_balance: float,
                            sl_distance: float,
                            pip_value: float = 1.0) -> List[float]:
        """
        Calculate lot size for each grid order.

        Args:
            account_balance: Current account balance
            sl_distance: Distance to SL in price
            pip_value: Value per pip

        Returns:
            List of lot sizes
        """
        for order in self.orders:
            risk_amount = account_balance * order.risk_percent / 100
            if sl_distance > 0:
                order.lot_size = risk_amount / sl_distance / pip_value
                order.lot_size = max(0.01, round(order.lot_size, 2))
            else:
                order.lot_size = 0.01

        return [o.lot_size for o in self.orders]

    def get_order_at_price(self, current_price: float, tolerance: float = 0.001) -> Optional[GridOrder]:
        """
        Check if price has reached any grid order level.

        Args:
            current_price: Current market price
            tolerance: Price tolerance as decimal (0.001 = 0.1%)

        Returns:
            GridOrder if price is at level, None otherwise
        """
        for order in self.orders:
            if order.filled:
                continue
            price_diff = abs(current_price - order.price) / order.price
            if price_diff <= tolerance:
                return order
        return None

    def mark_order_filled(self, order: GridOrder):
        """Mark an order as filled."""
        order.filled = True

    def get_filled_count(self) -> int:
        """Get number of filled orders."""
        return sum(1 for o in self.orders if o.filled)

    def get_remaining_orders(self) -> List[GridOrder]:
        """Get unfilled orders."""
        return [o for o in self.orders if not o.filled]

    def get_total_risk_used(self) -> float:
        """Get total risk % used by filled orders."""
        return sum(o.risk_percent for o in self.orders if o.filled)

    def get_average_entry(self) -> float:
        """Get weighted average entry price of filled orders."""
        filled = [o for o in self.orders if o.filled]
        if not filled:
            return 0.0

        total_value = sum(o.price * o.lot_size for o in filled)
        total_lots = sum(o.lot_size for o in filled)

        return total_value / total_lots if total_lots > 0 else 0.0

    def reset(self):
        """Reset all orders."""
        self.orders = []
        self.total_risk_percent = 0.0

    def get_grid_summary(self) -> str:
        """Get human-readable summary of grid orders."""
        if not self.orders:
            return "No grid orders"

        lines = [f"Grid Orders ({len(self.orders)} total):"]
        for i, order in enumerate(self.orders, 1):
            status = "✅" if order.filled else "⏳"
            lines.append(f"  {i}. Fib {order.level:.3f} @ {order.price:.5f} "
                        f"(Risk: {order.risk_percent:.2f}%, Lot: {order.lot_size:.2f}) {status}")

        lines.append(f"Filled: {self.get_filled_count()}/{len(self.orders)}")
        lines.append(f"Total Risk Used: {self.get_total_risk_used():.2f}%")

        if self.get_filled_count() > 0:
            lines.append(f"Avg Entry: {self.get_average_entry():.5f}")

        return "\n".join(lines)
