"""
Fibo 71 Bot - Backtesting with Real Data (Fixed Version)

Tests CP 2.0 strategy logic on historical data from Yahoo Finance.
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass, field
import sys

sys.path.insert(0, str(__file__).replace('/backtest_real_data.py', ''))

from indicators.bos import BOSDetector, TrendDirection, BOSResult, SwingPoint
from indicators.fibonacci import FibonacciCalculator, FibonacciLevels


@dataclass
class Trade:
    """Completed trade"""
    entry_time: datetime
    exit_time: datetime
    direction: str
    entry_price: float
    exit_price: float
    sl: float
    tp: float
    lot_size: float
    pnl_pips: float
    pnl_money: float
    result: str
    swing_high: float
    swing_low: float


@dataclass
class BacktestResult:
    """Backtest results"""
    symbol: str
    timeframe: str
    start_date: datetime
    end_date: datetime
    total_trades: int
    wins: int
    losses: int
    win_rate: float
    total_pnl: float
    total_pnl_percent: float
    avg_win: float
    avg_loss: float
    profit_factor: float
    max_drawdown: float
    max_consecutive_wins: int
    max_consecutive_losses: int
    avg_rr_ratio: float
    expectancy: float
    trades: List[Trade] = field(default_factory=list)
    equity_curve: List[float] = field(default_factory=list)


class RealDataBacktester:
    """Backtester for CP 2.0 strategy."""

    def __init__(self, df: pd.DataFrame, symbol: str = "EURUSD",
                 timeframe: str = "H1", risk_percent: float = 1.0,
                 initial_balance: float = 10000, fib_entry_min: float = 0.71,
                 fib_entry_max: float = 0.79, require_imbalance: bool = True,
                 require_liquidity_sweep: bool = True, pip_value: float = 10.0,
                 spread_pips: float = 1.5, commission: float = 7.0):

        # Normalize columns
        df.columns = [c.lower().replace(' ', '_') for c in df.columns]
        self.df = df.copy()

        self.symbol = symbol
        self.timeframe = timeframe
        self.risk_percent = risk_percent
        self.initial_balance = initial_balance
        self.balance = initial_balance
        self.equity_curve = [initial_balance]

        self.fib_entry_min = fib_entry_min
        self.fib_entry_max = fib_entry_max
        self.require_imbalance = require_imbalance
        self.require_liquidity_sweep = require_liquidity_sweep
        self.pip_value = pip_value
        self.spread_pips = spread_pips
        self.commission = commission

        # Pip size based on symbol
        if 'JPY' in symbol:
            self.pip_size = 0.01
        elif 'XAU' in symbol or 'GOLD' in symbol.upper():
            self.pip_size = 0.1
        else:
            self.pip_size = 0.0001

        self.bos_detector = BOSDetector(lookback=50, min_imbalance_pips=5.0)
        self.fib_calc = FibonacciCalculator(fib_entry_min, fib_entry_max)

        self.trades: List[Trade] = []
        self.active_setup = None
        self.last_setup_idx = -100  # Prevent too frequent setups

    def run(self, verbose: bool = False) -> BacktestResult:
        """Run the backtest."""

        print(f"\n{'='*60}")
        print(f"📊 FIBO 71 BACKTEST - {self.symbol} ({self.timeframe})")
        print(f"{'='*60}")
        print(f"📅 Period: {self.df.index[0]} to {self.df.index[-1]}")
        print(f"📈 Candles: {len(self.df)}")
        print(f"💰 Balance: ${self.initial_balance:,.0f} | Risk: {self.risk_percent}%")
        print(f"📍 Entry Zone: {self.fib_entry_min*100:.0f}% - {self.fib_entry_max*100:.0f}%")
        print(f"{'='*60}\n")

        lookback = 50
        for i in range(lookback, len(self.df)):
            # Check active setup for entry
            if self.active_setup:
                self._check_entry(i)

            # Look for new setup
            self._detect_setup(i, verbose)

        return self._calculate_results()

    def _detect_setup(self, idx: int, verbose: bool):
        """Detect BOS setup."""
        if self.active_setup:
            return

        # Cooldown between setups
        if idx - self.last_setup_idx < 10:
            return

        # Get data slice
        df_slice = self.df.iloc[max(0, idx-60):idx+1]

        # Detect BOS
        bos = self.bos_detector.detect_bos(df_slice, require_imbalance=self.require_imbalance)

        if not bos.detected:
            return

        if self.require_liquidity_sweep and not bos.liquidity_sweep:
            return

        # Get swing points from the chart
        # For BOS detection, we need to find the actual swing high/low
        current = self.df.iloc[idx]
        swing_idx = bos.swing_point.index

        # Get actual swing point from the chart
        if bos.direction == TrendDirection.BEARISH:
            # Bearish BOS - price broke below swing low
            swing_low_price = bos.swing_point.price
            # Find the swing high that preceded this move
            lookback_start = max(0, swing_idx - 20)
            swing_high_price = self.df.iloc[lookback_start:swing_idx+1]['high'].max()
        else:
            # Bullish BOS - price broke above swing high
            swing_high_price = bos.swing_point.price
            # Find the swing low that preceded this move
            lookback_start = max(0, swing_idx - 20)
            swing_low_price = self.df.iloc[lookback_start:swing_idx+1]['low'].min()

        direction = 'SELL' if bos.direction == TrendDirection.BEARISH else 'BUY'

        # Calculate Fibonacci levels
        fib = self.fib_calc.calculate_levels(swing_high_price, swing_low_price, direction)

        self.active_setup = {
            'direction': direction,
            'fib': fib,
            'swing_high': swing_high_price,
            'swing_low': swing_low_price,
            'setup_idx': idx
        }
        self.last_setup_idx = idx

        if verbose:
            emoji = "🔴" if direction == "SELL" else "🟢"
            print(f"[{self.df.index[idx]}] {emoji} BOS: {direction}")
            print(f"   High: {swing_high_price:.5f}, Low: {swing_low_price:.5f}")
            print(f"   Entry: {fib.level_79:.5f} - {fib.level_71:.5f}")

    def _check_entry(self, idx: int):
        """Check if price entered the zone."""
        if not self.active_setup:
            return

        candle = self.df.iloc[idx]
        direction = self.active_setup['direction']
        fib = self.active_setup['fib']

        # Check if price touched entry zone
        if direction == 'SELL':
            # Price needs to retrace UP to entry zone
            in_zone = candle['high'] >= fib.level_79 and candle['high'] <= fib.level_71
        else:
            # Price needs to retrace DOWN to entry zone
            in_zone = candle['low'] <= fib.level_71 and candle['low'] >= fib.level_79

        if in_zone:
            self._execute_trade(idx)
            self.active_setup = None

    def _execute_trade(self, entry_idx: int):
        """Execute and track trade to TP/SL."""
        setup = self.active_setup
        direction = setup['direction']
        fib = setup['fib']

        candle = self.df.iloc[entry_idx]
        entry_time = self.df.index[entry_idx]

        # Entry price with spread
        spread = self.spread_pips * self.pip_size
        if direction == 'SELL':
            entry_price = min(candle['high'], fib.level_71) + spread
        else:
            entry_price = max(candle['low'], fib.level_79) - spread

        sl = fib.level_100
        tp = fib.level_0

        # Calculate lot size
        sl_pips = abs(entry_price - sl) / self.pip_size
        if sl_pips < 1:
            return  # Invalid setup

        risk = self.balance * (self.risk_percent / 100)
        lot = max(0.01, round(risk / (sl_pips * self.pip_value), 2))

        # Find exit
        for i in range(entry_idx + 1, len(self.df)):
            exit_candle = self.df.iloc[i]
            exit_time = self.df.index[i]

            exit_price = None
            result = None

            if direction == 'SELL':
                # Check TP (price went down)
                if exit_candle['low'] <= tp:
                    exit_price = tp
                    result = 'WIN'
                # Check SL (price went up)
                elif exit_candle['high'] >= sl:
                    exit_price = sl
                    result = 'LOSS'
            else:  # BUY
                # Check TP (price went up)
                if exit_candle['high'] >= tp:
                    exit_price = tp
                    result = 'WIN'
                # Check SL (price went down)
                elif exit_candle['low'] <= sl:
                    exit_price = sl
                    result = 'LOSS'

            if exit_price and result:
                # Calculate P/L
                if direction == 'SELL':
                    pnl_pips = (entry_price - exit_price) / self.pip_size
                else:
                    pnl_pips = (exit_price - entry_price) / self.pip_size

                pnl_pips -= self.spread_pips  # Deduct spread
                pnl_money = pnl_pips * self.pip_value * lot
                pnl_money -= self.commission * lot  # Commission

                self.balance += pnl_money
                self.equity_curve.append(self.balance)

                trade = Trade(
                    entry_time=entry_time,
                    exit_time=exit_time,
                    direction=direction,
                    entry_price=entry_price,
                    exit_price=exit_price,
                    sl=sl,
                    tp=tp,
                    lot_size=lot,
                    pnl_pips=pnl_pips,
                    pnl_money=pnl_money,
                    result=result,
                    swing_high=setup['swing_high'],
                    swing_low=setup['swing_low']
                )
                self.trades.append(trade)
                break

    def _calculate_results(self) -> BacktestResult:
        """Calculate final statistics."""

        if not self.trades:
            return BacktestResult(
                symbol=self.symbol, timeframe=self.timeframe,
                start_date=self.df.index[0], end_date=self.df.index[-1],
                total_trades=0, wins=0, losses=0, win_rate=0,
                total_pnl=0, total_pnl_percent=0, avg_win=0, avg_loss=0,
                profit_factor=0, max_drawdown=0, max_consecutive_wins=0,
                max_consecutive_losses=0, avg_rr_ratio=0, expectancy=0
            )

        wins = [t for t in self.trades if t.result == 'WIN']
        losses = [t for t in self.trades if t.result == 'LOSS']

        total_pnl = sum(t.pnl_money for t in self.trades)
        avg_win = np.mean([t.pnl_money for t in wins]) if wins else 0
        avg_loss = np.mean([t.pnl_money for t in losses]) if losses else 0

        gross_profit = sum(t.pnl_money for t in wins)
        gross_loss = abs(sum(t.pnl_money for t in losses))
        profit_factor = gross_profit / gross_loss if gross_loss > 0 else 999

        # Max drawdown
        equity = np.array(self.equity_curve)
        running_max = np.maximum.accumulate(equity)
        drawdowns = (running_max - equity) / running_max * 100
        max_dd = np.max(drawdowns) if len(drawdowns) > 0 else 0

        # Consecutive
        max_wins = max_losses = curr_wins = curr_losses = 0
        for t in self.trades:
            if t.result == 'WIN':
                curr_wins += 1
                curr_losses = 0
                max_wins = max(max_wins, curr_wins)
            else:
                curr_losses += 1
                curr_wins = 0
                max_losses = max(max_losses, curr_losses)

        win_rate = len(wins) / len(self.trades) * 100
        avg_rr = abs(avg_win / avg_loss) if avg_loss != 0 else 0
        expectancy = (win_rate/100 * avg_win) - ((1-win_rate/100) * abs(avg_loss))

        return BacktestResult(
            symbol=self.symbol, timeframe=self.timeframe,
            start_date=self.df.index[0], end_date=self.df.index[-1],
            total_trades=len(self.trades), wins=len(wins), losses=len(losses),
            win_rate=win_rate, total_pnl=total_pnl,
            total_pnl_percent=total_pnl / self.initial_balance * 100,
            avg_win=avg_win, avg_loss=avg_loss, profit_factor=profit_factor,
            max_drawdown=max_dd, max_consecutive_wins=max_wins,
            max_consecutive_losses=max_losses, avg_rr_ratio=avg_rr,
            expectancy=expectancy, trades=self.trades, equity_curve=self.equity_curve
        )


def print_results(result: BacktestResult, show_trades: int = 10):
    """Print results nicely."""

    print("\n" + "="*70)
    print("📊 FIBO 71 - CP 2.0 STRATEGY BACKTEST RESULTS")
    print("="*70)
    print(f"\n📌 {result.symbol} | {result.timeframe}")
    print(f"📅 {result.start_date.date()} → {result.end_date.date()}")

    print("\n┌" + "─"*66 + "┐")
    print("│" + " TRADING STATISTICS".center(66) + "│")
    print("├" + "─"*66 + "┤")
    print(f"│ Total Trades:     {result.total_trades:>6}                                        │")
    print(f"│ Wins:             {result.wins:>6}  ({result.win_rate:.1f}%)                          │")
    print(f"│ Losses:           {result.losses:>6}                                        │")
    print("├" + "─"*66 + "┤")
    print(f"│ Total P/L:        ${result.total_pnl:>+10,.2f}  ({result.total_pnl_percent:>+.1f}%)              │")
    print(f"│ Avg Win:          ${result.avg_win:>+10,.2f}                              │")
    print(f"│ Avg Loss:         ${result.avg_loss:>+10,.2f}                              │")
    print(f"│ Profit Factor:    {result.profit_factor:>10,.2f}                              │")
    print("├" + "─"*66 + "┤")
    print(f"│ Max Drawdown:     {result.max_drawdown:>10,.1f}%                              │")
    print(f"│ Expectancy:       ${result.expectancy:>+10,.2f}                              │")
    print(f"│ Avg R:R:          {result.avg_rr_ratio:>10,.2f}                              │")
    print(f"│ Max Consec Wins:  {result.max_consecutive_wins:>10}                              │")
    print(f"│ Max Consec Loss:  {result.max_consecutive_losses:>10}                              │")
    print("└" + "─"*66 + "┘")

    # Rating
    if result.win_rate >= 70 and result.profit_factor >= 2:
        rating = "⭐⭐⭐⭐⭐ EXCELLENT"
    elif result.win_rate >= 60 and result.profit_factor >= 1.5:
        rating = "⭐⭐⭐⭐ GOOD"
    elif result.win_rate >= 50 and result.profit_factor >= 1.2:
        rating = "⭐⭐⭐ AVERAGE"
    else:
        rating = "⭐⭐ NEEDS WORK"

    print(f"\n🏆 Rating: {rating}")

    if result.trades and show_trades > 0:
        n = min(show_trades, len(result.trades))
        print(f"\n📋 Last {n} Trades:")
        print("-" * 85)
        print(f"{'Date':<12} {'Dir':<6} {'Entry':<10} {'Exit':<10} {'SL':<10} {'TP':<10} {'P/L':<12} {'Res':<6}")
        print("-" * 85)

        for t in result.trades[-n:]:
            emoji = "🔴" if t.direction == "SELL" else "🟢"
            res = "✅" if t.result == "WIN" else "❌"
            print(f"{t.entry_time.strftime('%Y-%m-%d'):<12} {emoji} {t.direction:<4} "
                  f"{t.entry_price:<10.5f} {t.exit_price:<10.5f} {t.sl:<10.5f} {t.tp:<10.5f} "
                  f"${t.pnl_money:>+9,.2f} {res}")


def main():
    import yfinance as yf

    print("📥 Downloading EURUSD data...")
    end = datetime.now()
    start = end - timedelta(days=365)

    ticker = yf.Ticker("EURUSD=X")
    df = ticker.history(start=start.strftime('%Y-%m-%d'), end=end.strftime('%Y-%m-%d'), interval='1h')

    if df.empty:
        print("❌ No data!")
        return

    print(f"✅ Downloaded {len(df)} candles\n")

    bt = RealDataBacktester(
        df=df, symbol="EURUSD", timeframe="H1",
        risk_percent=1.0, initial_balance=10000,
        require_imbalance=True, require_liquidity_sweep=False
    )

    result = bt.run(verbose=False)
    print_results(result, show_trades=20)


if __name__ == "__main__":
    main()
