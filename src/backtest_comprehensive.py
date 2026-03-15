"""
Fibo 71 Bot - Comprehensive Backtest

Tests the strategy across multiple pairs, timeframes, and entry zones.
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from dataclasses import dataclass
import sys
import yfinance as yf

sys.path.insert(0, str(__file__).replace('/backtest_comprehensive.py', ''))

from indicators.bos import BOSDetector, TrendDirection


@dataclass
class Trade:
    entry_time: datetime
    exit_time: datetime
    direction: str
    entry_price: float
    exit_price: float
    sl: float
    tp: float
    pnl_pips: float
    result: str


def download_data(symbol: str, interval: str, days: int):
    """Download data from Yahoo Finance."""
    try:
        # Use period string for reliability
        if interval == '1h':
            period = '2y'  # Yahoo max for hourly
        elif interval == '1d':
            period = '2y'
        else:
            period = f'{days}d'

        ticker = yf.Ticker(f"{symbol}=X")
        df = ticker.history(period=period, interval=interval)

        if df.empty:
            return None
        df.columns = [c.lower() for c in df.columns]
        return df
    except Exception as e:
        print(f"Error: {e}")
        return None


def run_backtest(df, symbol, tf_name, fib_min, fib_max, pip_size, min_range_pips=30):
    """Run backtest and return results."""
    bos_det = BOSDetector(lookback=50, min_imbalance_pips=3.0)
    trades = []
    active_setup = None
    last_setup_idx = -100

    for i in range(60, len(df)):
        current = df.iloc[i]

        # Check for entry
        if active_setup:
            direction = active_setup['direction']
            entry_zone_top = active_setup['entry_zone_top']
            entry_zone_bottom = active_setup['entry_zone_bottom']
            tp = active_setup['tp']
            sl = active_setup['sl']

            entry_price = None

            if direction == 'SELL':
                if current['high'] >= entry_zone_top:
                    entry_price = min(current['high'], entry_zone_bottom)
            else:
                if current['low'] <= entry_zone_bottom:
                    entry_price = max(current['low'], entry_zone_top)

            if entry_price:
                for j in range(i + 1, min(i + 100, len(df))):
                    exit_candle = df.iloc[j]

                    if direction == 'SELL':
                        if exit_candle['low'] <= tp:
                            exit_price = tp
                            pnl_pips = (entry_price - exit_price) / pip_size
                            trades.append(Trade(df.index[i], df.index[j], direction,
                                              entry_price, exit_price, sl, tp, pnl_pips, 'WIN'))
                            break
                        elif exit_candle['high'] >= sl:
                            exit_price = sl
                            pnl_pips = (entry_price - exit_price) / pip_size
                            trades.append(Trade(df.index[i], df.index[j], direction,
                                              entry_price, exit_price, sl, tp, pnl_pips, 'LOSS'))
                            break
                    else:
                        if exit_candle['high'] >= tp:
                            exit_price = tp
                            pnl_pips = (exit_price - entry_price) / pip_size
                            trades.append(Trade(df.index[i], df.index[j], direction,
                                              entry_price, exit_price, sl, tp, pnl_pips, 'WIN'))
                            break
                        elif exit_candle['low'] <= sl:
                            exit_price = sl
                            pnl_pips = (exit_price - entry_price) / pip_size
                            trades.append(Trade(df.index[i], df.index[j], direction,
                                              entry_price, exit_price, sl, tp, pnl_pips, 'LOSS'))
                            break
                active_setup = None

        # Look for new setup
        if active_setup is None and i - last_setup_idx >= 5:
            slice_df = df.iloc[:i+1].copy()
            bos = bos_det.detect_bos(slice_df, require_imbalance=False)

            if bos.detected:
                direction = 'SELL' if bos.direction == TrendDirection.BEARISH else 'BUY'
                swing_idx = bos.swing_point.index

                if direction == 'SELL':
                    swing_low = bos.swing_point.price
                    lookback = max(0, swing_idx - 30)
                    swing_high = df.iloc[lookback:swing_idx+1]['high'].max()
                else:
                    swing_high = bos.swing_point.price
                    lookback = max(0, swing_idx - 30)
                    swing_low = df.iloc[lookback:swing_idx+1]['low'].min()

                range_size = swing_high - swing_low

                if direction == 'SELL':
                    entry_zone_top = swing_low + range_size * fib_min
                    entry_zone_bottom = swing_low + range_size * fib_max
                    tp = swing_low
                    sl = swing_high
                else:
                    entry_zone_top = swing_high - range_size * fib_min
                    entry_zone_bottom = swing_high - range_size * fib_max
                    tp = swing_high
                    sl = swing_low

                # Validate setup
                if direction == 'SELL':
                    valid = tp < entry_zone_top <= entry_zone_bottom < sl
                else:
                    valid = sl < entry_zone_bottom <= entry_zone_top < tp

                if valid and range_size / pip_size >= min_range_pips:
                    active_setup = {
                        'direction': direction,
                        'swing_high': swing_high,
                        'swing_low': swing_low,
                        'entry_zone_top': entry_zone_top,
                        'entry_zone_bottom': entry_zone_bottom,
                        'tp': tp,
                        'sl': sl,
                    }
                    last_setup_idx = i

    if not trades:
        return None

    wins = [t for t in trades if t.result == 'WIN']
    losses = [t for t in trades if t.result == 'LOSS']

    total_pips = sum(t.pnl_pips for t in trades)
    win_rate = len(wins) / len(trades) * 100

    gross_profit = sum(t.pnl_pips for t in wins)
    gross_loss = abs(sum(t.pnl_pips for t in losses))
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else 999

    return {
        'pair': symbol,
        'tf': tf_name,
        'zone': f"{fib_min*100:.0f}-{fib_max*100:.0f}%",
        'trades': len(trades),
        'win_rate': win_rate,
        'total_pips': total_pips,
        'pf': profit_factor,
        'avg_win': np.mean([t.pnl_pips for t in wins]) if wins else 0,
        'avg_loss': np.mean([t.pnl_pips for t in losses]) if losses else 0,
    }


def main():
    print("=" * 80)
    print("📊 FIBO 71 - COMPREHENSIVE BACKTEST")
    print("=" * 80)

    ENTRY_ZONES = {
        '38-50%': (0.38, 0.50),
        '50-62%': (0.50, 0.62),
        '62-71%': (0.62, 0.71),
        '71-79%': (0.71, 0.79),
    }

    PAIRS = ['EURUSD', 'GBPUSD', 'USDJPY', 'AUDUSD', 'USDCAD', 'NZDUSD']

    # Use valid Yahoo Finance timeframes
    # Note: '1h' only works for last 730 days, but API is strict
    TIMEFRAMES = {
        'H1': ('1h', 700),   # Hourly - ~700 days to be safe
        'D1': ('1d', 730),   # Daily - 2 years
    }

    all_results = []

    for pair in PAIRS:
        print(f"\n💱 {pair}")

        pip_size = 0.01 if 'JPY' in pair else 0.0001

        for tf_name, (tf_yf, days) in TIMEFRAMES.items():
            print(f"  📈 {tf_name}...", end=" ", flush=True)

            df = download_data(pair, tf_yf, days)

            if df is None or len(df) < 100:
                print("❌ Brak danych")
                continue

            print(f"({len(df)} świec)", flush=True)

            for zone_name, (fib_min, fib_max) in ENTRY_ZONES.items():
                result = run_backtest(df, pair, tf_name, fib_min, fib_max, pip_size)

                if result:
                    all_results.append(result)

                    emoji = "✅" if result['pf'] >= 1.2 else "⚠️" if result['pf'] >= 1.0 else "❌"
                    print(f"     {zone_name}: {result['trades']} trades, WR: {result['win_rate']:.1f}%, "
                          f"Pips: {result['total_pips']:+.1f}, PF: {result['pf']:.2f} {emoji}")

    # Summary
    print("\n" + "=" * 80)
    print("🏆 TOP 20 RESULTS (by Profit Factor, min 3 trades)")
    print("=" * 80)

    sorted_results = sorted([r for r in all_results if r['trades'] >= 3],
                           key=lambda x: x['pf'] if x['pf'] < 999 else 0, reverse=True)

    print(f"\n{'Para':<10} {'TF':<5} {'Strefa':<10} {'Trades':>7} {'WR%':>7} {'Pips':>8} {'PF':>7}")
    print("-" * 60)

    for r in sorted_results[:20]:
        print(f"{r['pair']:<10} {r['tf']:<5} {r['zone']:<10} {r['trades']:>7} "
              f"{r['win_rate']:>6.1f}% {r['total_pips']:>+7.1f} {r['pf']:>7.2f}")

    # Best by timeframe
    print("\n" + "=" * 80)
    print("📊 BEST ZONE BY TIMEFRAME")
    print("=" * 80)

    for tf in ['H1', 'D1']:
        tf_results = [r for r in all_results if r['tf'] == tf and r['trades'] >= 3]
        if tf_results:
            best = max(tf_results, key=lambda x: x['pf'] if x['pf'] < 999 else 0)
            print(f"\n{tf}: {best['zone']} on {best['pair']}")
            print(f"   Trades: {best['trades']}, WR: {best['win_rate']:.1f}%, PF: {best['pf']:.2f}")

    # Configuration recommendation
    print("\n" + "=" * 80)
    print("📋 CONFIGURATION FOR SETTINGS.JSON")
    print("=" * 80)
    print("""
{
  "trading": {
    "symbol": "EURUSD",
    "timeframe": "H1"
  },
  "strategy": {
    "entry_zone": "50-62",
    "entry_zones": {
      "aggressive": {"min": 0.38, "max": 0.50},
      "balanced": {"min": 0.50, "max": 0.62},
      "conservative": {"min": 0.62, "max": 0.71},
      "cp20_original": {"min": 0.71, "max": 0.79}
    },
    "bos_lookback": 50,
    "min_range_pips": 30
  },
  "filters": {
    "require_imbalance": false
  }
}
""")


if __name__ == "__main__":
    main()
