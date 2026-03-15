"""
Fibo 71 Bot - Improved Backtesting with Relaxed Filters

Diagnoses why backtest catches too few trades and tests with looser conditions.
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass, field
import sys
import yfinance as yf

sys.path.insert(0, str(__file__).replace('/backtest_improved.py', ''))

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
    pnl_pips: float
    result: str
    fib_zone: str


class ImprovedBacktester:
    """Backtester with diagnostics and relaxed filters."""

    def __init__(self, df: pd.DataFrame, symbol: str = "EURUSD",
                 timeframe: str = "H1", risk_percent: float = 1.0,
                 fib_entry_min: float = 0.50, fib_entry_max: float = 0.62,
                 pip_size: float = 0.0001, spread_pips: float = 1.5,
                 require_imbalance: bool = False,  # Default OFF
                 cooldown: int = 5,  # Reduced cooldown
                 min_swing_distance: int = 3):  # Min candles from swing to current

        # Normalize columns
        df.columns = [c.lower().replace(' ', '_') for c in df.columns]
        self.df = df.copy()

        self.symbol = symbol
        self.timeframe = timeframe
        self.fib_entry_min = fib_entry_min
        self.fib_entry_max = fib_entry_max
        self.require_imbalance = require_imbalance
        self.cooldown = cooldown
        self.min_swing_distance = min_swing_distance
        self.pip_size = pip_size
        self.spread_pips = spread_pips

        self.bos_detector = BOSDetector(lookback=50, min_imbalance_pips=3.0)
        self.fib_calc = FibonacciCalculator(fib_entry_min, fib_entry_max)

        self.trades: List[Trade] = []
        self.diagnostics = {
            'bos_detected': 0,
            'imbalance_passed': 0,
            'entry_triggered': 0,
            'trades_completed': 0
        }

    def run(self, verbose: bool = False) -> Dict:
        """Run the backtest with diagnostics."""

        print(f"\n{'='*60}")
        print(f"📊 IMPROVED BACKTEST - {self.symbol} ({self.timeframe})")
        print(f"{'='*60}")
        print(f"📅 Period: {self.df.index[0]} to {self.df.index[-1]}")
        print(f"📈 Candles: {len(self.df)}")
        print(f"📍 Entry Zone: {self.fib_entry_min*100:.0f}% - {self.fib_entry_max*100:.0f}%")
        print(f"🔧 Require Imbalance: {self.require_imbalance}")
        print(f"🔧 Cooldown: {self.cooldown} candles")
        print(f"{'='*60}\n")

        active_setup = None
        last_setup_idx = -100

        lookback = 50
        for i in range(lookback, len(self.df)):

            # Check for entry if we have pending setup
            if active_setup:
                entry_result = self._check_entry(i, active_setup, verbose)
                if entry_result:
                    self.trades.append(entry_result)
                    active_setup = None
                    continue

            # Look for new setup with cooldown
            if i - last_setup_idx >= self.cooldown:
                setup = self._detect_setup(i, verbose)
                if setup:
                    active_setup = setup
                    last_setup_idx = i

        return self._calculate_results()

    def _detect_setup(self, idx: int, verbose: bool) -> Optional[Dict]:
        """Detect BOS setup with relaxed logic."""

        # Get data slice
        df_slice = self.df.iloc[max(0, idx-60):idx+1]

        # Detect BOS
        bos = self.bos_detector.detect_bos(df_slice, require_imbalance=self.require_imbalance)

        if not bos.detected:
            return None

        self.diagnostics['bos_detected'] += 1

        if self.require_imbalance and not bos.imbalance_start:
            return None

        self.diagnostics['imbalance_passed'] += 1

        # Get swing points
        swing_idx = bos.swing_point.index

        # For the actual swing high/low, look back further
        if bos.direction == TrendDirection.BEARISH:
            swing_low_price = bos.swing_point.price
            # Find swing high from the move before this low
            lookback_start = max(0, swing_idx - 30)
            swing_high_price = self.df.iloc[lookback_start:swing_idx+1]['high'].max()
        else:
            swing_high_price = bos.swing_point.price
            # Find swing low from the move before this high
            lookback_start = max(0, swing_idx - 30)
            swing_low_price = self.df.iloc[lookback_start:swing_idx+1]['low'].min()

        direction = 'SELL' if bos.direction == TrendDirection.BEARISH else 'BUY'

        # Calculate Fibonacci levels
        range_size = swing_high_price - swing_low_price

        if direction == 'SELL':
            # For SELL: we expect price to retrace UP to entry zone
            entry_top = swing_low_price + range_size * self.fib_entry_min
            entry_bottom = swing_low_price + range_size * self.fib_entry_max
            tp = swing_low_price
            sl = swing_high_price
        else:
            # For BUY: we expect price to retrace DOWN to entry zone
            entry_top = swing_high_price - range_size * self.fib_entry_min
            entry_bottom = swing_high_price - range_size * self.fib_entry_max
            tp = swing_high_price
            sl = swing_low_price

        if verbose:
            emoji = "🔴" if direction == "SELL" else "🟢"
            print(f"[{self.df.index[idx]}] {emoji} BOS: {direction}")
            print(f"   Swing High: {swing_high_price:.5f}, Low: {swing_low_price:.5f}")
            print(f"   Entry Zone: {entry_top:.5f} - {entry_bottom:.5f}")
            print(f"   TP: {tp:.5f}, SL: {sl:.5f}")

        return {
            'direction': direction,
            'swing_high': swing_high_price,
            'swing_low': swing_low_price,
            'entry_top': entry_top,
            'entry_bottom': entry_bottom,
            'tp': tp,
            'sl': sl,
            'setup_idx': idx
        }

    def _check_entry(self, idx: int, setup: Dict, verbose: bool) -> Optional[Trade]:
        """Check if price entered the zone and execute trade."""
        candle = self.df.iloc[idx]
        direction = setup['direction']

        # Entry zone check
        if direction == 'SELL':
            # For SELL, price must retrace UP into the zone
            in_zone = candle['high'] >= setup['entry_top'] and candle['low'] <= setup['entry_bottom']
            # Entry at the top of zone (first touch)
            if candle['high'] >= setup['entry_top']:
                entry_price = min(candle['high'], setup['entry_bottom']) + self.spread_pips * self.pip_size
            else:
                in_zone = False
        else:
            # For BUY, price must retrace DOWN into the zone
            in_zone = candle['low'] <= setup['entry_bottom'] and candle['high'] >= setup['entry_top']
            # Entry at the bottom of zone (first touch)
            if candle['low'] <= setup['entry_bottom']:
                entry_price = max(candle['low'], setup['entry_top']) - self.spread_pips * self.pip_size
            else:
                in_zone = False

        if not in_zone:
            return None

        self.diagnostics['entry_triggered'] += 1

        if verbose:
            print(f"[{self.df.index[idx]}] ✅ ENTRY: {direction} @ {entry_price:.5f}")

        # Find exit (TP or SL)
        sl = setup['sl']
        tp = setup['tp']

        for j in range(idx + 1, len(self.df)):
            exit_candle = self.df.iloc[j]
            exit_time = self.df.index[j]

            exit_price = None
            result = None

            if direction == 'SELL':
                if exit_candle['low'] <= tp:
                    exit_price = tp
                    result = 'WIN'
                elif exit_candle['high'] >= sl:
                    exit_price = sl
                    result = 'LOSS'
            else:
                if exit_candle['high'] >= tp:
                    exit_price = tp
                    result = 'WIN'
                elif exit_candle['low'] <= sl:
                    exit_price = sl
                    result = 'LOSS'

            if exit_price and result:
                if direction == 'SELL':
                    pnl_pips = (entry_price - exit_price) / self.pip_size
                else:
                    pnl_pips = (exit_price - entry_price) / self.pip_size

                pnl_pips -= self.spread_pips

                zone_name = f"{self.fib_entry_min*100:.0f}-{self.fib_entry_max*100:.0f}%"

                trade = Trade(
                    entry_time=self.df.index[idx],
                    exit_time=exit_time,
                    direction=direction,
                    entry_price=entry_price,
                    exit_price=exit_price,
                    sl=sl,
                    tp=tp,
                    pnl_pips=pnl_pips,
                    result=result,
                    fib_zone=zone_name
                )

                self.diagnostics['trades_completed'] += 1
                return trade

        return None

    def _calculate_results(self) -> Dict:
        """Calculate final statistics."""

        if not self.trades:
            return {
                'trades': 0,
                'wins': 0,
                'losses': 0,
                'win_rate': 0,
                'total_pips': 0,
                'profit_factor': 0,
                'diagnostics': self.diagnostics
            }

        wins = [t for t in self.trades if t.result == 'WIN']
        losses = [t for t in self.trades if t.result == 'LOSS']

        total_pips = sum(t.pnl_pips for t in self.trades)
        win_rate = len(wins) / len(self.trades) * 100

        gross_profit = sum(t.pnl_pips for t in wins)
        gross_loss = abs(sum(t.pnl_pips for t in losses))
        profit_factor = gross_profit / gross_loss if gross_loss > 0 else 999

        return {
            'trades': len(self.trades),
            'wins': len(wins),
            'losses': len(losses),
            'win_rate': win_rate,
            'total_pips': total_pips,
            'profit_factor': profit_factor,
            'avg_win': np.mean([t.pnl_pips for t in wins]) if wins else 0,
            'avg_loss': np.mean([t.pnl_pips for t in losses]) if losses else 0,
            'diagnostics': self.diagnostics,
            'trade_list': self.trades
        }


def download_data(symbol: str, interval: str, days: int):
    """Download data from Yahoo Finance."""
    try:
        end = datetime.now()
        start = end - timedelta(days=days)

        ticker = yf.Ticker(f"{symbol}=X")
        df = ticker.history(start=start.strftime('%Y-%m-%d'), end=end.strftime('%Y-%m-%d'), interval=interval)

        if df.empty:
            return None
        df.columns = [c.lower() for c in df.columns]
        return df
    except Exception as e:
        print(f"Error downloading {symbol}: {e}")
        return None


def main():
    print("=" * 80)
    print("📊 FIBO 71 - IMPROVED BACKTEST WITH DIAGNOSTICS")
    print("=" * 80)

    # Test configurations
    ENTRY_ZONES = {
        '38-50%': (0.38, 0.50),
        '50-62%': (0.50, 0.62),
        '62-71%': (0.62, 0.71),
        '71-79%': (0.71, 0.79),
    }

    PAIRS = ['EURUSD', 'GBPUSD', 'USDJPY']

    # Timeframe mapping (Yahoo Finance limits)
    # Note: H4 not available, use 1h and aggregate or use 1d
    TIMEFRAMES = {
        'H1': ('1h', 730),  # Max 730 days for 1h
        'H4': ('1d', 730),  # Use daily as H4 proxy
    }

    all_results = []

    for pair in PAIRS:
        print(f"\n{'='*60}")
        print(f"💱 {pair}")
        print(f"{'='*60}")

        pip_size = 0.01 if 'JPY' in pair else 0.0001

        for tf_name, (tf_yf, days) in TIMEFRAMES.items():
            print(f"\n📈 {tf_name}...", end=" ", flush=True)

            df = download_data(pair, tf_yf, days)

            if df is None or len(df) < 100:
                print("❌ Brak danych")
                continue

            print(f"({len(df)} świec)")

            for zone_name, (fib_min, fib_max) in ENTRY_ZONES.items():
                # Test WITHOUT imbalance requirement
                bt = ImprovedBacktester(
                    df=df,
                    symbol=pair,
                    timeframe=tf_name,
                    fib_entry_min=fib_min,
                    fib_entry_max=fib_max,
                    pip_size=pip_size,
                    require_imbalance=False,  # RELAXED
                    cooldown=5  # REDUCED
                )

                result = bt.run(verbose=False)

                if result['trades'] > 0:
                    all_results.append({
                        'pair': pair,
                        'tf': tf_name,
                        'zone': zone_name,
                        'trades': result['trades'],
                        'win_rate': result['win_rate'],
                        'pips': result['total_pips'],
                        'pf': result['profit_factor'],
                        'diagnostics': result['diagnostics']
                    })

                    emoji = "✅" if result['profit_factor'] >= 1.2 else "⚠️" if result['profit_factor'] >= 1.0 else "❌"
                    print(f"   {zone_name}: {result['trades']} trades, WR: {result['win_rate']:.1f}%, "
                          f"Pips: {result['total_pips']:+.1f}, PF: {result['profit_factor']:.2f} {emoji}")
                    print(f"      📊 BOS: {result['diagnostics']['bos_detected']}, "
                          f"Entries: {result['diagnostics']['entry_triggered']}, "
                          f"Completed: {result['diagnostics']['trades_completed']}")

    # Summary
    print("\n" + "=" * 80)
    print("🏆 TOP 15 RESULTS (by Profit Factor)")
    print("=" * 80)

    sorted_results = sorted(all_results, key=lambda x: x['pf'] if x['pf'] < 999 else 0, reverse=True)

    print(f"\n{'Para':<10} {'TF':<5} {'Strefa':<10} {'Trades':>7} {'WR%':>7} {'Pips':>8} {'PF':>7}")
    print("-" * 60)

    for r in sorted_results[:15]:
        if r['trades'] >= 3:
            print(f"{r['pair']:<10} {r['tf']:<5} {r['zone']:<10} {r['trades']:>7} "
                  f"{r['win_rate']:>6.1f}% {r['pips']:>+7.1f} {r['pf']:>7.2f}")

    print("\n" + "=" * 80)
    print("📊 CONFIGURATION TABLE FOR SETTINGS.JSON")
    print("=" * 80)
    print("""
"entry_zones": {
    "aggressive": {"min": 0.38, "max": 0.50},
    "balanced": {"min": 0.50, "max": 0.62},  // RECOMMENDED
    "conservative": {"min": 0.62, "max": 0.71},
    "cp20_original": {"min": 0.71, "max": 0.79}
}
""")


if __name__ == "__main__":
    main()
