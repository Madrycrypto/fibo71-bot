"""
Fibo 71 Bot - Backtesting Module

Tests CP 2.0 strategy logic on historical data.
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass, field
from loguru import logger
import sys

# Add src to path
sys.path.insert(0, str(__file__).replace('/backtest.py', ''))

from indicators.bos import BOSDetector, TrendDirection
from indicators.fibonacci import FibonacciCalculator, FibonacciLevels


@dataclass
class Trade:
    """Represents a completed trade"""
    entry_time: datetime
    exit_time: datetime
    direction: str  # 'BUY' or 'SELL'
    entry_price: float
    exit_price: float
    sl: float
    tp: float
    lot_size: float
    pnl_pips: float
    pnl_money: float
    result: str  # 'WIN', 'LOSS', 'BREAKEVEN'
    fib_entry_pct: float


@dataclass
class BacktestResult:
    """Backtest results summary"""
    start_date: datetime
    end_date: datetime
    total_trades: int
    wins: int
    losses: int
    win_rate: float
    total_pnl: float
    avg_win: float
    avg_loss: float
    profit_factor: float
    max_drawdown: float
    max_consecutive_wins: int
    max_consecutive_losses: int
    avg_rr_ratio: float
    trades: List[Trade] = field(default_factory=list)


class Backtester:
    """
    Backtester for CP 2.0 strategy.

    Simulates:
    1. BOS detection
    2. Fibonacci level calculation
    3. Limit order placement at 71-79%
    4. TP/SL execution (Set and Forget)
    """

    def __init__(self,
                 df: pd.DataFrame,
                 risk_percent: float = 1.0,
                 initial_balance: float = 10000,
                 fib_entry_min: float = 0.71,
                 fib_entry_max: float = 0.79,
                 bos_lookback: int = 50,
                 min_imbalance_pips: float = 10.0,
                 require_imbalance: bool = True,
                 require_liquidity_sweep: bool = True,
                 pip_value: float = 10.0,
                 spread_pips: float = 1.5):
        """
        Initialize backtester.

        Args:
            df: DataFrame with OHLCV data (indexed by datetime)
            risk_percent: Risk per trade (%)
            initial_balance: Starting balance
            fib_entry_min: Minimum Fibonacci entry level
            fib_entry_max: Maximum Fibonacci entry level
            bos_lookback: Lookback for BOS detection
            min_imbalance_pips: Minimum imbalance in pips
            require_imbalance: Require imbalance filter
            require_liquidity_sweep: Require liquidity sweep
            pip_value: Value per pip per lot
            spread_pips: Spread in pips
        """
        self.df = df.copy()
        self.risk_percent = risk_percent
        self.initial_balance = initial_balance
        self.balance = initial_balance
        self.equity_curve = [initial_balance]

        self.fib_entry_min = fib_entry_min
        self.fib_entry_max = fib_entry_max

        self.bos_detector = BOSDetector(
            lookback=bos_lookback,
            min_imbalance_pips=min_imbalance_pips
        )
        self.fib_calculator = FibonacciCalculator(
            entry_min=fib_entry_min,
            entry_max=fib_entry_max
        )

        self.require_imbalance = require_imbalance
        self.require_liquidity_sweep = require_liquidity_sweep
        self.pip_value = pip_value
        self.spread_pips = spread_pips
        self.pip_size = 0.0001  # For most forex pairs

        self.trades: List[Trade] = []
        self.pending_setup: Optional[Dict] = None

    def run(self) -> BacktestResult:
        """
        Run backtest on historical data.

        Returns:
            BacktestResult with performance metrics
        """
        logger.info(f"Starting backtest on {len(self.df)} candles...")
        logger.info(f"Date range: {self.df.index[0]} to {self.df.index[-1]}")

        # Process each candle
        for i in range(50, len(self.df)):  # Start after lookback period
            current_df = self.df.iloc[:i+1]
            current_candle = self.df.iloc[i]
            current_time = self.df.index[i]

            # Check pending orders first
            if self.pending_setup:
                self._check_pending_order(current_candle, current_time)

            # Detect new setups
            self._detect_setup(current_df, current_candle, current_time)

        # Calculate results
        result = self._calculate_results()

        return result

    def _detect_setup(self, df: pd.DataFrame, current_candle: pd.Series, current_time: datetime):
        """Detect BOS and create pending setup."""

        # Run BOS detection
        bos_result = self.bos_detector.detect_bos(df)

        if not bos_result.detected:
            return

        # Check filters
        if self.require_imbalance and not bos_result.imbalance_start:
            return

        if self.require_liquidity_sweep and not bos_result.liquidity_sweep:
            return

        # Determine direction
        direction = 'SELL' if bos_result.direction == TrendDirection.BEARISH else 'BUY'

        # Get swing points
        if direction == 'SELL':
            swing_high = current_candle['high']
            swing_low = bos_result.swing_point.price
        else:
            swing_high = bos_result.swing_point.price
            swing_low = current_candle['low']

        # Calculate Fibonacci levels
        fib_levels = self.fib_calculator.calculate_levels(
            swing_high=swing_high,
            swing_low=swing_low,
            direction=direction
        )

        # Store pending setup
        self.pending_setup = {
            'direction': direction,
            'fib_levels': fib_levels,
            'setup_time': current_time,
            'bos_result': bos_result
        }

        logger.debug(f"[{current_time}] {direction} BOS detected at {bos_result.swing_point.price:.5f}")

    def _check_pending_order(self, current_candle: pd.Series, current_time: datetime):
        """Check if price reached entry zone and manage open positions."""

        if not self.pending_setup:
            return

        direction = self.pending_setup['direction']
        fib = self.pending_setup['fib_levels']

        # Check if price is in entry zone
        in_zone, fib_pct = self.fib_calculator.is_in_entry_zone(
            current_candle['low'] if direction == 'BUY' else current_candle['high'],
            fib
        )

        # For SELL, check if high touched entry zone (price retraced up)
        # For BUY, check if low touched entry zone (price retraced down)
        if direction == 'SELL':
            touched_zone = current_candle['high'] >= fib.level_79
            entry_price = min(current_candle['high'], fib.level_71)
        else:
            touched_zone = current_candle['low'] <= fib.level_71
            entry_price = max(current_candle['low'], fib.level_79)

        if touched_zone:
            # Simulate entry
            self._simulate_entry(fib, current_candle, current_time, direction)
            self.pending_setup = None

    def _simulate_entry(self, fib: FibonacciLevels, candle: pd.Series,
                        entry_time: datetime, direction: str):
        """Simulate trade entry and manage until TP/SL."""

        # Add spread
        spread = self.spread_pips * self.pip_size

        if direction == 'SELL':
            entry_price = min(candle['high'], fib.level_71) + spread
        else:
            entry_price = max(candle['low'], fib.level_79) - spread

        entry_price = round(entry_price, 5)
        sl = round(fib.level_100, 5)
        tp = round(fib.level_0, 5)

        # Calculate lot size based on risk
        sl_pips = abs(entry_price - sl) / self.pip_size
        risk_amount = self.balance * (self.risk_percent / 100)
        lot_size = risk_amount / (sl_pips * self.pip_value)
        lot_size = max(0.01, round(lot_size, 2))

        # Find exit candle (scan forward)
        setup_idx = self.df.index.get_loc(entry_time)

        for i in range(setup_idx + 1, len(self.df)):
            exit_candle = self.df.iloc[i]
            exit_time = self.df.index[i]

            exit_price = None
            result = None

            if direction == 'SELL':
                # Check TP first (price went down)
                if exit_candle['low'] <= tp:
                    exit_price = tp
                    result = 'WIN'
                # Check SL (price went up)
                elif exit_candle['high'] >= sl:
                    exit_price = sl
                    result = 'LOSS'
            else:  # BUY
                # Check TP first (price went up)
                if exit_candle['high'] >= tp:
                    exit_price = tp
                    result = 'WIN'
                # Check SL (price went down)
                elif exit_candle['low'] <= sl:
                    exit_price = sl
                    result = 'LOSS'

            if exit_price:
                # Calculate P/L
                if direction == 'SELL':
                    pnl_pips = (entry_price - exit_price) / self.pip_size
                else:
                    pnl_pips = (exit_price - entry_price) / self.pip_size

                pnl_money = pnl_pips * self.pip_value * lot_size
                self.balance += pnl_money
                self.equity_curve.append(self.balance)

                # Calculate actual Fibonacci percentage
                if direction == 'SELL':
                    fib_entry_pct = (entry_price - fib.level_0) / (fib.level_100 - fib.level_0)
                else:
                    fib_entry_pct = (fib.level_0 - entry_price) / (fib.level_0 - fib.level_100)

                trade = Trade(
                    entry_time=entry_time,
                    exit_time=exit_time,
                    direction=direction,
                    entry_price=entry_price,
                    exit_price=exit_price,
                    sl=sl,
                    tp=tp,
                    lot_size=lot_size,
                    pnl_pips=pnl_pips,
                    pnl_money=pnl_money,
                    result=result,
                    fib_entry_pct=fib_entry_pct
                )

                self.trades.append(trade)

                logger.debug(f"[{exit_time}] {result}: {direction} {pnl_pips:.1f} pips (${pnl_money:.2f})")
                break

    def _calculate_results(self) -> BacktestResult:
        """Calculate backtest performance metrics."""

        if not self.trades:
            logger.warning("No trades executed during backtest")
            return BacktestResult(
                start_date=self.df.index[0],
                end_date=self.df.index[-1],
                total_trades=0,
                wins=0,
                losses=0,
                win_rate=0,
                total_pnl=0,
                avg_win=0,
                avg_loss=0,
                profit_factor=0,
                max_drawdown=0,
                max_consecutive_wins=0,
                max_consecutive_losses=0,
                avg_rr_ratio=0
            )

        wins = [t for t in self.trades if t.result == 'WIN']
        losses = [t for t in self.trades if t.result == 'LOSS']

        total_pnl = sum(t.pnl_money for t in self.trades)
        avg_win = np.mean([t.pnl_money for t in wins]) if wins else 0
        avg_loss = np.mean([t.pnl_money for t in losses]) if losses else 0

        gross_profit = sum(t.pnl_money for t in wins)
        gross_loss = abs(sum(t.pnl_money for t in losses))
        profit_factor = gross_profit / gross_loss if gross_loss > 0 else float('inf')

        # Calculate max drawdown
        equity = np.array(self.equity_curve)
        running_max = np.maximum.accumulate(equity)
        drawdowns = (running_max - equity) / running_max * 100
        max_drawdown = np.max(drawdowns)

        # Calculate consecutive wins/losses
        max_consec_wins = 0
        max_consec_losses = 0
        current_wins = 0
        current_losses = 0

        for trade in self.trades:
            if trade.result == 'WIN':
                current_wins += 1
                current_losses = 0
                max_consec_wins = max(max_consec_wins, current_wins)
            else:
                current_losses += 1
                current_wins = 0
                max_consec_losses = max(max_consec_losses, current_losses)

        # Calculate average R:R ratio
        avg_rr = abs(avg_win / avg_loss) if avg_loss != 0 else 0

        return BacktestResult(
            start_date=self.df.index[0],
            end_date=self.df.index[-1],
            total_trades=len(self.trades),
            wins=len(wins),
            losses=len(losses),
            win_rate=len(wins) / len(self.trades) * 100 if self.trades else 0,
            total_pnl=total_pnl,
            avg_win=avg_win,
            avg_loss=avg_loss,
            profit_factor=profit_factor,
            max_drawdown=max_drawdown,
            max_consecutive_wins=max_consec_wins,
            max_consecutive_losses=max_consec_losses,
            avg_rr_ratio=avg_rr,
            trades=self.trades
        )


def print_results(result: BacktestResult):
    """Print backtest results in formatted table."""

    print("\n" + "=" * 60)
    print("📊 FIBO 71 - CP 2.0 STRATEGY BACKTEST RESULTS")
    print("=" * 60)

    print(f"\n📅 Period: {result.start_date.date()} to {result.end_date.date()}")

    print("\n┌─────────────────────────────────────────────────────────┐")
    print("│                    📈 PERFORMANCE                        │")
    print("├─────────────────────────────────────────────────────────┤")
    print(f"│ Total Trades:        {result.total_trades:>10}                       │")
    print(f"│ Wins:                {result.wins:>10}                       │")
    print(f"│ Losses:              {result.losses:>10}                       │")
    print(f"│ Win Rate:            {result.win_rate:>9.1f}%                       │")
    print("├─────────────────────────────────────────────────────────┤")
    print(f"│ Total P/L:           ${result.total_pnl:>9.2f}                      │")
    print(f"│ Avg Win:             ${result.avg_win:>9.2f}                      │")
    print(f"│ Avg Loss:            ${result.avg_loss:>9.2f}                      │")
    print(f"│ Profit Factor:       {result.profit_factor:>10.2f}                      │")
    print("├─────────────────────────────────────────────────────────┤")
    print(f"│ Max Drawdown:        {result.max_drawdown:>9.1f}%                       │")
    print(f"│ Max Consec Wins:     {result.max_consecutive_wins:>10}                       │")
    print(f"│ Max Consec Losses:   {result.max_consecutive_losses:>10}                       │")
    print(f"│ Avg R:R Ratio:       {result.avg_rr_ratio:>10.2f}                      │")
    print("└─────────────────────────────────────────────────────────┘")

    # Rating
    if result.win_rate >= 70 and result.profit_factor >= 2.0:
        rating = "⭐⭐⭐⭐⭐ EXCELLENT"
    elif result.win_rate >= 60 and result.profit_factor >= 1.5:
        rating = "⭐⭐⭐⭐ GOOD"
    elif result.win_rate >= 50 and result.profit_factor >= 1.2:
        rating = "⭐⭐⭐ AVERAGE"
    elif result.win_rate >= 40 and result.profit_factor >= 1.0:
        rating = "⭐⭐ BELOW AVERAGE"
    else:
        rating = "⭐ POOR"

    print(f"\n🏆 Strategy Rating: {rating}")

    # Recent trades
    if result.trades:
        print("\n📋 Last 10 Trades:")
        print("-" * 80)
        print(f"{'Time':<12} {'Dir':<5} {'Entry':<10} {'Exit':<10} {'P/L':<8} {'Result':<8}")
        print("-" * 80)

        for trade in result.trades[-10:]:
            direction_emoji = "🔴" if trade.direction == "SELL" else "🟢"
            result_emoji = "✅" if trade.result == "WIN" else "❌"
            print(f"{trade.entry_time.strftime('%Y-%m-%d'):<12} "
                  f"{direction_emoji} {trade.direction:<3} "
                  f"{trade.entry_price:<10.5f} "
                  f"{trade.exit_price:<10.5f} "
                  f"${trade.pnl_money:<7.2f} "
                  f"{result_emoji} {trade.result}")


def generate_sample_data(days: int = 365, symbol: str = 'EURUSD') -> pd.DataFrame:
    """
    Generate sample OHLCV data for testing.

    In real use, replace with data from MT5 or other source.
    """
    np.random.seed(42)

    dates = pd.date_range(end=datetime.now(), periods=days * 24, freq='h')

    # Generate realistic price movements
    returns = np.random.normal(0, 0.0005, len(dates))

    # Add trend and volatility
    trend = np.linspace(0, 0.02, len(dates))
    volatility = 0.001 * (1 + 0.5 * np.sin(np.linspace(0, 10 * np.pi, len(dates))))

    prices = 1.1000 * np.exp(np.cumsum(returns + trend * 0.0001))
    prices = prices + volatility * np.random.randn(len(dates))

    df = pd.DataFrame({
        'open': prices,
        'high': prices * (1 + np.abs(np.random.normal(0, 0.001, len(dates)))),
        'low': prices * (1 - np.abs(np.random.normal(0, 0.001, len(dates)))),
        'close': prices + np.random.normal(0, 0.0005, len(dates)),
        'volume': np.random.randint(100, 1000, len(dates))
    }, index=dates)

    # Ensure high > low and proper ordering
    df['high'] = df[['open', 'high', 'close']].max(axis=1)
    df['low'] = df[['open', 'low', 'close']].min(axis=1)

    return df


def run_backtest_with_sample():
    """Run backtest with sample data."""

    print("\n🔄 Generating sample data...")
    df = generate_sample_data(days=365)

    print(f"📊 Data: {len(df)} candles from {df.index[0].date()} to {df.index[-1].date()}")

    # Run backtest
    backtester = Backtester(
        df=df,
        risk_percent=1.0,
        initial_balance=10000,
        fib_entry_min=0.71,
        fib_entry_max=0.79,
        bos_lookback=50,
        min_imbalance_pips=10.0,
        require_imbalance=True,
        require_liquidity_sweep=True
    )

    result = backtester.run()
    print_results(result)

    return result


if __name__ == "__main__":
    run_backtest_with_sample()
