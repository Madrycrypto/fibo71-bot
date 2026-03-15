"""
Porównanie strategii Fibo 71 na różnych parach i interwałach.
"""

import yfinance as yf
import pandas as pd
from datetime import datetime, timedelta
import sys
sys.path.insert(0, 'src')

from indicators.bos import BOSDetector, TrendDirection
from indicators.fibonacci import FibonacciCalculator

# Główne pary walutowe
PAIRS = ['EURUSD', 'GBPUSD', 'USDJPY', 'AUDUSD', 'USDCAD', 'NZDUSD']
TIMEFRAMES = {'15m': '15m', '1h': '1h', '4h': '1d'}  # yfinance limits

# Strefy wejścia
ENTRY_ZONES = {
    '50-62%': (0.50, 0.62),
    '38-50%': (0.38, 0.50),
}

def download_data(symbol, interval, days):
    """Pobierz dane z Yahoo Finance."""
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
        return None

def run_backtest(df, fib_min, fib_max):
    """Uruchom prosty backtest."""
    if df is None or len(df) < 100:
        return None

    bos_det = BOSDetector(lookback=50, min_imbalance_pips=3.0)
    fib_calc = FibonacciCalculator(fib_min, fib_max)

    trades = []
    pending_setup = None
    pip_size = 0.01 if 'JPY' in 'EURUSD' else 0.0001

    for i in range(60, len(df)):
        current = df.iloc[i]

        # Sprawdź wejście
        if pending_setup:
            direction = pending_setup['direction']
            entry_top = pending_setup['entry_top']
            entry_bottom = pending_setup['entry_bottom']

            if direction == 'SELL':
                if current['high'] >= entry_bottom:
                    entry = min(current['high'], entry_top)
                    for j in range(i+1, min(i+50, len(df))):
                        c = df.iloc[j]
                        if c['low'] <= pending_setup['tp']:
                            pnl = (entry - pending_setup['tp']) / pip_size - 1.5
                            trades.append({'result': 'WIN', 'pips': pnl})
                            break
                        elif c['high'] >= pending_setup['sl']:
                            pnl = (entry - pending_setup['sl']) / pip_size - 1.5
                            trades.append({'result': 'LOSS', 'pips': pnl})
                            break
                    pending_setup = None
            else:
                if current['low'] <= entry_top:
                    entry = max(current['low'], entry_bottom)
                    for j in range(i+1, min(i+50, len(df))):
                        c = df.iloc[j]
                        if c['high'] >= pending_setup['tp']:
                            pnl = (pending_setup['tp'] - entry) / pip_size - 1.5
                            trades.append({'result': 'WIN', 'pips': pnl})
                            break
                        elif c['low'] <= pending_setup['sl']:
                            pnl = (pending_setup['sl'] - entry) / pip_size - 1.5
                            trades.append({'result': 'LOSS', 'pips': pnl})
                            break
                    pending_setup = None

        # Szukaj setupu
        if pending_setup is None:
            slice_df = df.iloc[:i+1].copy()
            bos = bos_det.detect_bos(slice_df, require_imbalance=False)

            if bos.detected:
                direction = 'SELL' if bos.direction.name == 'BEARISH' else 'BUY'
                swing_idx = bos.swing_point.index

                if direction == 'SELL':
                    swing_low = bos.swing_point.price
                    lookback = max(0, swing_idx - 20)
                    swing_high = df.iloc[lookback:swing_idx+1]['high'].max()
                else:
                    swing_high = bos.swing_point.price
                    lookback = max(0, swing_idx - 20)
                    swing_low = df.iloc[lookback:swing_idx+1]['low'].min()

                range_size = swing_high - swing_low

                if direction == 'SELL':
                    entry_top = swing_low + range_size * fib_min
                    entry_bottom = swing_low + range_size * fib_max
                    tp = swing_low
                    sl = swing_high
                else:
                    entry_top = swing_high - range_size * fib_min
                    entry_bottom = swing_high - range_size * fib_max
                    tp = swing_high
                    sl = swing_low

                pending_setup = {
                    'direction': direction,
                    'entry_top': entry_top,
                    'entry_bottom': entry_bottom,
                    'tp': tp,
                    'sl': sl
                }

    if not trades:
        return None

    wins = [t for t in trades if t['result'] == 'WIN']
    losses = [t for t in trades if t['result'] == 'LOSS']

    total_pips = sum(t['pips'] for t in trades)
    win_rate = len(wins) / len(trades) * 100 if trades else 0
    profit_factor = abs(sum(t['pips'] for t in wins) / sum(t['pips'] for t in losses)) if losses and sum(t['pips'] for t in losses) != 0 else 0

    return {
        'trades': len(trades),
        'wins': len(wins),
        'win_rate': win_rate,
        'pips': total_pips,
        'pf': profit_factor
    }

def main():
    print("=" * 80)
    print("📊 FIBO 71 - PORÓWNANIE PAR WALUTOWYCH")
    print("=" * 80)

    results = []

    for pair in PAIRS:
        print(f"\n💱 {pair}")
        print("-" * 40)

        for tf_name, tf_yf in [('H1', '1h')]:  # Tylko H1 dla szybkości
            print(f"  📈 {tf_name}...", end=" ", flush=True)

            df = download_data(pair, tf_yf, days=700)

            if df is None or len(df) < 100:
                print("❌ Brak danych")
                continue

            print(f"({len(df)} świec)")

            for zone_name, (fib_min, fib_max) in ENTRY_ZONES.items():
                result = run_backtest(df, fib_min, fib_max)

                if result:
                    results.append({
                        'pair': pair,
                        'tf': tf_name,
                        'zone': zone_name,
                        'trades': result['trades'],
                        'win_rate': result['win_rate'],
                        'pips': result['pips'],
                        'pf': result['pf']
                    })

                    emoji = "✅" if result['pf'] >= 1.2 else "⚠️" if result['pf'] >= 1.0 else "❌"
                    print(f"     {zone_name}: {result['trades']} trades, WR: {result['win_rate']:.1f}%, "
                          f"Pips: {result['pips']:+.1f}, PF: {result['pf']:.2f} {emoji}")

    # Podsumowanie
    print("\n" + "=" * 80)
    print("🏆 NAJLEPSZE KOMBINACJE")
    print("=" * 80)

    # Sortuj po Profit Factor
    sorted_results = sorted(results, key=lambda x: x['pf'] if x['pf'] < 999 else 0, reverse=True)

    print(f"\n{'Para':<10} {'TF':<5} {'Strefa':<10} {'Trades':>7} {'WR%':>7} {'Pips':>8} {'PF':>7}")
    print("-" * 60)

    for r in sorted_results[:10]:
        if r['trades'] >= 3:  # Minimum 3 trades
            print(f"{r['pair']:<10} {r['tf']:<5} {r['zone']:<10} {r['trades']:>7} "
                  f"{r['win_rate']:>6.1f}% {r['pips']:>+7.1f} {r['pf']:>7.2f}")

    # Najlepszy wynik
    if sorted_results:
        best = sorted_results[0]
        print(f"\n🏆 NAJLEPSZY: {best['pair']} {best['tf']} - {best['zone']}")
        print(f"   Win Rate: {best['win_rate']:.1f}%, Profit Factor: {best['pf']:.2f}")

if __name__ == "__main__":
    main()
