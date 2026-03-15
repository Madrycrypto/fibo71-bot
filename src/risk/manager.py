"""
Risk Management Module

Implements 1% risk per trade rule with correlated pair reduction.
"""

import pandas as pd
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set
from datetime import datetime, date


@dataclass
class Position:
    """Represents an open position"""
    symbol: str
    ticket: int
    direction: str  # 'BUY' or 'SELL'
    lot_size: float
    entry_price: float
    sl: float
    tp: float
    open_time: datetime
    risk_percent: float


@dataclass
class DailyStats:
    """Daily trading statistics"""
    date: date
    trades_opened: int = 0
    trades_closed: int = 0
    pnl: float = 0.0
    max_risk_used: float = 0.0


class RiskManager:
    """
    Risk Manager for CP 2.0 strategy.

    - 1% risk per trade
    - 0.5% on correlated pairs
    - Max daily trades limit
    - Max open positions limit
    """

    # Correlated pairs groups
    CORRELATION_GROUPS = {
        'EUR': ['EURUSD', 'EURGBP', 'EURJPY', 'EURAUD', 'EURNZD', 'EURCAD', 'EURCHF'],
        'GBP': ['GBPUSD', 'EURGBP', 'GBPJPY', 'GBPAUD', 'GBPNZD', 'GBPCAD', 'GBPCHF'],
        'USD': ['EURUSD', 'GBPUSD', 'USDJPY', 'AUDUSD', 'NZDUSD', 'USDCAD', 'USDCHF'],
        'JPY': ['USDJPY', 'EURJPY', 'GBPJPY', 'AUDJPY', 'NZDJPY', 'CADJPY', 'CHFJPY'],
        'AUD': ['AUDUSD', 'EURAUD', 'GBPAUD', 'AUDJPY', 'AUDNZD', 'AUDCAD', 'AUDCHF'],
        'NZD': ['NZDUSD', 'EURNZD', 'GBPNZD', 'NZDJPY', 'AUDNZD', 'NZDCAD', 'NZDCHF'],
        'CAD': ['USDCAD', 'EURCAD', 'GBPCAD', 'CADJPY', 'AUDCAD', 'NZDCAD', 'CADCHF'],
        'CHF': ['USDCHF', 'EURCHF', 'GBPCHF', 'CHFJPY', 'AUDCHF', 'NZDCHF', 'CADCHF'],
    }

    def __init__(self,
                 risk_percent: float = 1.0,
                 correlated_risk_percent: float = 0.5,
                 max_daily_trades: int = 3,
                 max_open_positions: int = 2):
        """
        Initialize Risk Manager.

        Args:
            risk_percent: Standard risk per trade (default 1%)
            correlated_risk_percent: Risk when correlated pairs open (default 0.5%)
            max_daily_trades: Maximum trades per day
            max_open_positions: Maximum simultaneous positions
        """
        self.risk_percent = risk_percent
        self.correlated_risk_percent = correlated_risk_percent
        self.max_daily_trades = max_daily_trades
        self.max_open_positions = max_open_positions

        self.open_positions: Dict[str, Position] = {}
        self.daily_stats: Dict[date, DailyStats] = {}

    def get_correlated_pairs(self, symbol: str) -> Set[str]:
        """
        Find all correlated pairs for a given symbol.

        Args:
            symbol: Trading symbol (e.g., 'EURUSD')

        Returns:
            Set of correlated symbols
        """
        correlated = set()

        for currency, pairs in self.CORRELATION_GROUPS.items():
            if symbol in pairs:
                correlated.update(pairs)

        correlated.discard(symbol)  # Remove self
        return correlated

    def has_correlated_positions(self, symbol: str) -> bool:
        """
        Check if there are open positions on correlated pairs.

        Args:
            symbol: Trading symbol to check

        Returns:
            True if correlated positions exist
        """
        correlated = self.get_correlated_pairs(symbol)

        for pos_symbol in self.open_positions:
            if pos_symbol in correlated:
                return True

        return False

    def get_risk_for_trade(self, symbol: str) -> float:
        """
        Get appropriate risk percentage for a new trade.

        Args:
            symbol: Trading symbol

        Returns:
            Risk percentage to use
        """
        if self.has_correlated_positions(symbol):
            return self.correlated_risk_percent
        return self.risk_percent

    def can_open_trade(self, symbol: str) -> tuple[bool, str]:
        """
        Check if a new trade can be opened.

        Args:
            symbol: Trading symbol

        Returns:
            Tuple of (can_open, reason)
        """
        # Check max open positions
        if len(self.open_positions) >= self.max_open_positions:
            return False, f"Max open positions ({self.max_open_positions}) reached"

        # Check daily trade limit
        today = date.today()
        stats = self.daily_stats.get(today, DailyStats(date=today))

        if stats.trades_opened >= self.max_daily_trades:
            return False, f"Max daily trades ({self.max_daily_trades}) reached"

        # Check for existing position on same symbol
        if symbol in self.open_positions:
            return False, f"Position already open on {symbol}"

        return True, "OK"

    def register_position(self, position: Position):
        """
        Register a new open position.

        Args:
            position: Position object to register
        """
        self.open_positions[position.symbol] = position

        today = date.today()
        if today not in self.daily_stats:
            self.daily_stats[today] = DailyStats(date=today)

        self.daily_stats[today].trades_opened += 1
        self.daily_stats[today].max_risk_used = max(
            self.daily_stats[today].max_risk_used,
            position.risk_percent
        )

    def close_position(self, symbol: str, pnl: float):
        """
        Close a position and update statistics.

        Args:
            symbol: Symbol of position to close
            pnl: Profit/Loss from the trade
        """
        if symbol in self.open_positions:
            del self.open_positions[symbol]

        today = date.today()
        if today not in self.daily_stats:
            self.daily_stats[today] = DailyStats(date=today)

        self.daily_stats[today].trades_closed += 1
        self.daily_stats[today].pnl += pnl

    def get_daily_stats(self, day: Optional[date] = None) -> DailyStats:
        """
        Get statistics for a specific day.

        Args:
            day: Date to get stats for (default: today)

        Returns:
            DailyStats object
        """
        day = day or date.today()
        return self.daily_stats.get(day, DailyStats(date=day))

    def calculate_lot_size(self, account_balance: float,
                           entry_price: float,
                           sl_price: float,
                           symbol: str,
                           pip_value: float = 10.0) -> float:
        """
        Calculate appropriate lot size based on risk rules.

        Args:
            account_balance: Current account balance
            entry_price: Entry price
            sl_price: Stop loss price
            symbol: Trading symbol
            pip_value: Value per pip per lot

        Returns:
            Lot size to use
        """
        risk_pct = self.get_risk_for_trade(symbol)
        risk_amount = account_balance * (risk_pct / 100)

        sl_pips = abs(entry_price - sl_price) * 10000

        if sl_pips == 0:
            return 0.01

        lot_size = risk_amount / (sl_pips * pip_value)

        return max(0.01, round(lot_size, 2))
