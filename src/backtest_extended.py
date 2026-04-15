"""
Fibo 71 Bot - Extended Backtest (Crypto, Commodities, Stocks)
"""

import pandas as pd
import numpy as np
from datetime import datetime
from dataclasses import dataclass
import sys
import yfinance as yf

sys.path.insert(0, str(__file__).replace('/backtest_extended.py', ''))
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
    try:
        if interval == '1h':
            period = '730d'
        elif interval == '1d':
            period = '2y'
        else:
            period = f'{days}d'

        ticker = yf.Ticker(symbol)
        df = ticker.history(period=period, interval=interval)

        if df.empty:
            return None
        df.columns = [c.lower() for c in df.columns]
        return df
    except Exception as e:
        print(f"Error {symbol}: {e}")
        return None


def run_backtest(df, symbol, tf_name, fib_min, fib_max, pip_size, min_range_pips=30):
    bos_det = BOSDetector(lookback=50, min_imbalance_pips=3.0)
    trades = []
    active_setup = None
    last_setup_idx = -100

    for i in range(60, len(df)):
        current = df.iloc[i]

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


# ===== ASSET DEFINITIONS =====

CRYPTO = {
    # symbol: (display_name, pip_size, min_range_pips)
    'BTC-USD':   ('BTC/USD',   1.0,   50),
    'ETH-USD':   ('ETH/USD',   0.1,   30),
    'BNB-USD':   ('BNB/USD',   0.01,  30),
    'XRP-USD':   ('XRP/USD',   0.0001, 30),
    'SOL-USD':   ('SOL/USD',   0.01,  30),
    'ADA-USD':   ('ADA/USD',   0.0001, 30),
    'DOGE-USD':  ('DOGE/USD',  0.00001, 30),
    'AVAX-USD':  ('AVAX/USD',  0.01,  30),
    'DOT-USD':   ('DOT/USD',   0.001, 30),
    'LINK-USD':  ('LINK/USD',  0.001, 30),
}

COMMODITIES = {
    # symbol: (display_name, pip_size, min_range_pips)
    'GC=F':   ('GOLD',     0.1,  30),
    'SI=F':   ('SILVER',   0.01, 30),
    'HG=F':   ('COPPER',   0.001, 20),
    'CL=F':   ('OIL WTI',  0.01, 30),
    'BZ=F':   ('OIL BRENT', 0.01, 30),
    'NG=F':   ('NAT.GAS',  0.001, 20),
    'PL=F':   ('PLATINUM', 0.1,  30),
    'PA=F':   ('PALLADIUM',0.1,  30),
}

STOCKS = {
    # symbol: (display_name, pip_size, min_range_pips)
    'AAPL':  ('Apple',        0.01, 20),
    'MSFT':  ('Microsoft',    0.01, 20),
    'GOOGL': ('Alphabet',     0.01, 20),
    'AMZN':  ('Amazon',       0.01, 20),
    'NVDA':  ('NVIDIA',       0.01, 20),
    'META':  ('Meta',         0.01, 20),
    'TSLA':  ('Tesla',        0.01, 20),
    'BRK-B': ('Berkshire',    0.01, 20),
    'JPM':   ('JP Morgan',    0.01, 20),
    'V':     ('Visa',         0.01, 20),
    'UNH':   ('UnitedHealth', 0.01, 20),
    'JNJ':   ('Johnson&Johnson', 0.01, 20),
    'WMT':   ('Walmart',      0.01, 20),
    'PG':    ('P&G',          0.01, 20),
    'MA':    ('Mastercard',   0.01, 20),
    'HD':    ('Home Depot',   0.01, 20),
    'NFLX':  ('Netflix',      0.01, 20),
    'AMD':   ('AMD',          0.01, 20),
    'BAC':   ('Bank of America', 0.01, 20),
    'CRM':   ('Salesforce',   0.01, 20),
}

ENTRY_ZONES = {
    '38-50%': (0.38, 0.50),
    '50-62%': (0.50, 0.62),
    '62-71%': (0.62, 0.71),
    '71-79%': (0.71, 0.79),
}

TIMEFRAMES = {
    'H1': ('1h', 700),
    'D1': ('1d', 730),
}


def run_category(name, assets):
    print(f"\n{'='*80}")
    print(f"  {name}")
    print(f"{'='*80}")

    all_results = []

    for symbol, (display, pip_size, min_range) in assets.items():
        print(f"\n  {display} ({symbol})")

        for tf_name, (tf_yf, days) in TIMEFRAMES.items():
            print(f"    {tf_name}...", end=" ", flush=True)

            df = download_data(symbol, tf_yf, days)

            if df is None or len(df) < 100:
                print("brak danych")
                continue

            print(f"({len(df)} swiec)", flush=True)

            for zone_name, (fib_min, fib_max) in ENTRY_ZONES.items():
                result = run_backtest(df, display, tf_name, fib_min, fib_max, pip_size, min_range)

                if result:
                    all_results.append(result)
                    emoji = "OK" if result['pf'] >= 1.2 else "~" if result['pf'] >= 1.0 else "X"
                    print(f"      {zone_name}: {result['trades']}t  WR:{result['win_rate']:.0f}%  "
                          f"Pips:{result['total_pips']:+.1f}  PF:{result['pf']:.2f} {emoji}")

    return all_results


def print_top(results, title, n=20):
    sorted_r = sorted([r for r in results if r['trades'] >= 2],
                      key=lambda x: x['pf'] if x['pf'] < 999 else 0, reverse=True)

    print(f"\n{'='*80}")
    print(f"  {title}")
    print(f"{'='*80}")
    print(f"\n{'Para':<18} {'TF':<5} {'Strefa':<10} {'Trades':>7} {'WR%':>7} {'Pips':>8} {'PF':>7}")
    print("-" * 65)

    for r in sorted_r[:n]:
        print(f"{r['pair']:<18} {r['tf']:<5} {r['zone']:<10} {r['trades']:>7} "
              f"{r['win_rate']:>6.1f}% {r['total_pips']:>+7.1f} {r['pf']:>7.2f}")

    return sorted_r[:n]


def main():
    print("=" * 80)
    print("  FIBO 71 - EXTENDED BACKTEST")
    print("  Crypto / Surowce / Akcje")
    print("=" * 80)

    all_all = []

    crypto_results = run_category("CRYPTO — Top 10", CRYPTO)
    all_all.extend(crypto_results)

    comm_results = run_category("SUROWCE — Metale / Ropa / Gaz", COMMODITIES)
    all_all.extend(comm_results)

    stock_results = run_category("AKCJE — Top 20", STOCKS)
    all_all.extend(stock_results)

    print_top(crypto_results, "CRYPTO — TOP 10 Setupow", 10)
    print_top(comm_results, "SUROWCE — TOP 10 Setupow", 10)
    print_top(stock_results, "AKCJE — TOP 20 Setupow", 20)
    print_top(all_all, "GLOBALNY TOP 20 (wszystkie aktywa)", 20)

    # Summary stats
    print(f"\n{'='*80}")
    print(f"  PODSUMOWANIE")
    print(f"{'='*80}")

    profitable = [r for r in all_all if r['pf'] >= 1.0 and r['trades'] >= 2]
    great = [r for r in all_all if r['pf'] >= 1.5 and r['trades'] >= 2]

    print(f"  Lacznie wynikow (min 2 trades): {len([r for r in all_all if r['trades'] >= 2])}")
    print(f"  Zyskownych (PF >= 1.0): {len(profitable)}")
    print(f"  Bardzo zyskownych (PF >= 1.5): {len(great)}")

    if great:
        print(f"\n  Najlepszy setup:")
        best = max(great, key=lambda x: x['pf'] if x['pf'] < 999 else 0)
        print(f"  {best['pair']} {best['tf']} {best['zone']}")
        print(f"  Trades: {best['trades']}, WR: {best['win_rate']:.1f}%, PF: {best['pf']:.2f}, Pips: {best['total_pips']:+.1f}")


if __name__ == "__main__":
    main()
