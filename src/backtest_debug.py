"""
Fibo 71 Bot - Debug Backtest to Fix Entry Logic

The previous backtest showed negative pips despite high win rates,
indicating a bug in the TP/SL or entry logic.
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass
import sys
import yfinance as yf

sys.path.insert(0, str(__file__).replace('/backtest_debug.py', ''))

from indicators.bos import BOSDetector, TrendDirection


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
    swing_high: float
    swing_low: float


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


def run_debug_backtest(df, symbol="EURUSD", fib_min=0.50, fib_max=0.62, pip_size=0.0001, verbose=True):
    """
    Run backtest with detailed trade logging to debug the logic.
    """
    print(f"\n{'='*70}")
    print(f"🔍 DEBUG BACKTEST - {symbol}")
    print(f"{'='*70}")
    print(f"Entry Zone: {fib_min*100:.0f}% - {fib_max*100:.0f}%")
    print(f"Pip Size: {pip_size}")
    print(f"{'='*70}\n")

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
                # For SELL: price must retrace UP into entry zone
                # We want to SELL when price is higher (closer to SL)
                # Entry zone is ABOVE swing low
                if current['high'] >= entry_zone_top:
                    # Price touched the top of our entry zone
                    entry_price = min(current['high'], entry_zone_bottom)
                    if verbose:
                        print(f"[{df.index[i]}] 📌 SELL ENTRY @ {entry_price:.5f}")
                        print(f"   Entry Zone: {entry_zone_top:.5f} - {entry_zone_bottom:.5f}")
                        print(f"   TP: {tp:.5f}, SL: {sl:.5f}")

            else:  # BUY
                # For BUY: price must retrace DOWN into entry zone
                # We want to BUY when price is lower (closer to SL)
                # Entry zone is BELOW swing high
                if current['low'] <= entry_zone_bottom:
                    # Price touched the bottom of our entry zone
                    entry_price = max(current['low'], entry_zone_top)
                    if verbose:
                        print(f"[{df.index[i]}] 📌 BUY ENTRY @ {entry_price:.5f}")
                        print(f"   Entry Zone: {entry_zone_top:.5f} - {entry_zone_bottom:.5f}")
                        print(f"   TP: {tp:.5f}, SL: {sl:.5f}")

            if entry_price:
                # Find exit
                for j in range(i + 1, min(i + 100, len(df))):
                    exit_candle = df.iloc[j]

                    if direction == 'SELL':
                        # TP is hit when price goes DOWN to TP level
                        if exit_candle['low'] <= tp:
                            exit_price = tp
                            pnl_pips = (entry_price - exit_price) / pip_size
                            result = 'WIN'
                            trades.append(Trade(df.index[i], df.index[j], direction,
                                              entry_price, exit_price, sl, tp, pnl_pips, result,
                                              active_setup['swing_high'], active_setup['swing_low']))
                            if verbose:
                                print(f"   [{df.index[j]}] ✅ TP HIT @ {exit_price:.5f}, Pips: +{pnl_pips:.1f}\n")
                            break
                        # SL is hit when price goes UP to SL level
                        elif exit_candle['high'] >= sl:
                            exit_price = sl
                            pnl_pips = (entry_price - exit_price) / pip_size
                            result = 'LOSS'
                            trades.append(Trade(df.index[i], df.index[j], direction,
                                              entry_price, exit_price, sl, tp, pnl_pips, result,
                                              active_setup['swing_high'], active_setup['swing_low']))
                            if verbose:
                                print(f"   [{df.index[j]}] ❌ SL HIT @ {exit_price:.5f}, Pips: {pnl_pips:.1f}\n")
                            break
                    else:  # BUY
                        # TP is hit when price goes UP to TP level
                        if exit_candle['high'] >= tp:
                            exit_price = tp
                            pnl_pips = (exit_price - entry_price) / pip_size
                            result = 'WIN'
                            trades.append(Trade(df.index[i], df.index[j], direction,
                                              entry_price, exit_price, sl, tp, pnl_pips, result,
                                              active_setup['swing_high'], active_setup['swing_low']))
                            if verbose:
                                print(f"   [{df.index[j]}] ✅ TP HIT @ {exit_price:.5f}, Pips: +{pnl_pips:.1f}\n")
                            break
                        # SL is hit when price goes DOWN to SL level
                        elif exit_candle['low'] <= sl:
                            exit_price = sl
                            pnl_pips = (exit_price - entry_price) / pip_size
                            result = 'LOSS'
                            trades.append(Trade(df.index[i], df.index[j], direction,
                                              entry_price, exit_price, sl, tp, pnl_pips, result,
                                              active_setup['swing_high'], active_setup['swing_low']))
                            if verbose:
                                print(f"   [{df.index[j]}] ❌ SL HIT @ {exit_price:.5f}, Pips: {pnl_pips:.1f}\n")
                            break

                active_setup = None

        # Look for new setup
        if active_setup is None and i - last_setup_idx >= 5:
            slice_df = df.iloc[:i+1].copy()
            bos = bos_det.detect_bos(slice_df, require_imbalance=False)

            if bos.detected:
                direction = 'SELL' if bos.direction == TrendDirection.BEARISH else 'BUY'
                swing_idx = bos.swing_point.index

                # Find the swing high and low from the move
                if direction == 'SELL':
                    # Bearish BOS: price broke below swing low
                    swing_low = bos.swing_point.price
                    # Look back to find the swing high that started this move
                    lookback = max(0, swing_idx - 30)
                    swing_high = df.iloc[lookback:swing_idx+1]['high'].max()
                else:
                    # Bullish BOS: price broke above swing high
                    swing_high = bos.swing_point.price
                    # Look back to find the swing low that started this move
                    lookback = max(0, swing_idx - 30)
                    swing_low = df.iloc[lookback:swing_idx+1]['low'].min()

                range_size = swing_high - swing_low

                # Calculate Fibonacci entry zone
                # For SELL: price retraces UP, so zone is ABOVE swing low
                # For BUY: price retraces DOWN, so zone is BELOW swing high

                if direction == 'SELL':
                    # Retracement levels from swing low going UP
                    # 0% = swing low (TP), 100% = swing high (SL)
                    # 50% = swing_low + range * 0.50
                    # 62% = swing_low + range * 0.62
                    entry_zone_top = swing_low + range_size * fib_min  # Lower price (first touch)
                    entry_zone_bottom = swing_low + range_size * fib_max  # Higher price
                    tp = swing_low
                    sl = swing_high
                else:
                    # Retracement levels from swing high going DOWN
                    # 0% = swing high (TP), 100% = swing low (SL)
                    # 50% = swing_high - range * 0.50
                    # 62% = swing_high - range * 0.62
                    entry_zone_top = swing_high - range_size * fib_min  # Higher price (first touch)
                    entry_zone_bottom = swing_high - range_size * fib_max  # Lower price
                    tp = swing_high
                    sl = swing_low

                # Validate setup - ensure entry zone is between TP and SL
                if direction == 'SELL':
                    valid = tp < entry_zone_top <= entry_zone_bottom < sl
                else:
                    valid = sl < entry_zone_bottom <= entry_zone_top < tp

                if valid and range_size / pip_size >= 30:  # Min 30 pips range
                    active_setup = {
                        'direction': direction,
                        'swing_high': swing_high,
                        'swing_low': swing_low,
                        'entry_zone_top': entry_zone_top,
                        'entry_zone_bottom': entry_zone_bottom,
                        'tp': tp,
                        'sl': sl,
                        'setup_idx': i
                    }
                    last_setup_idx = i

                    if verbose:
                        emoji = "🔴" if direction == "SELL" else "🟢"
                        print(f"\n[{df.index[i]}] {emoji} SETUP: {direction}")
                        print(f"   Swing High: {swing_high:.5f}, Low: {swing_low:.5f}")
                        print(f"   Range: {range_size/pip_size:.1f} pips")
                        print(f"   Entry Zone: {entry_zone_top:.5f} - {entry_zone_bottom:.5f}")
                        print(f"   TP: {tp:.5f}, SL: {sl:.5f}")
                        # R:R at middle of entry zone
                        mid_entry = (entry_zone_top + entry_zone_bottom) / 2
                        if direction == 'SELL':
                            rr = (mid_entry - tp) / (sl - mid_entry)
                        else:
                            rr = (tp - mid_entry) / (mid_entry - sl)
                        print(f"   Expected R:R: {rr:.2f}")
    return trades


def main():
    print("=" * 80)
    print("🔍 FIBO 71 - DEBUG BACKTEST")
    print("=" * 80)

    # Download EURUSD daily data
    df = download_data('EURUSD', '1d', 730)

    if df is None:
        print("❌ No data")
        return

    print(f"\n✅ Downloaded {len(df)} candles")
    print(f"📅 Period: {df.index[0]} to {df.index[-1]}")

    # Test with 50-62% zone
    trades = run_debug_backtest(df, "EURUSD", 0.50, 0.62, verbose=True)

    # Summary
    print("\n" + "=" * 80)
    print("📊 SUMMARY")
    print("=" * 80)

    if trades:
        wins = [t for t in trades if t.result == 'WIN']
        losses = [t for t in trades if t.result == 'LOSS']

        total_pips = sum(t.pnl_pips for t in trades)
        win_rate = len(wins) / len(trades) * 100

        print(f"Total Trades: {len(trades)}")
        print(f"Wins: {len(wins)}, Losses: {len(losses)}")
        print(f"Win Rate: {win_rate:.1f}%")
        print(f"Total Pips: {total_pips:+.1f}")

        if losses:
            gross_profit = sum(t.pnl_pips for t in wins)
            gross_loss = abs(sum(t.pnl_pips for t in losses))
            pf = gross_profit / gross_loss if gross_loss > 0 else 999
            print(f"Profit Factor: {pf:.2f}")

        print("\n📋 TRADE DETAILS:")
        print("-" * 90)
        print(f"{'Date':<12} {'Dir':<6} {'Entry':<10} {'Exit':<10} {'TP':<10} {'SL':<10} {'Pips':<8} {'R:R':<8}")
        print("-" * 90)

        for t in trades:
            if t.direction == 'SELL':
                rr = (t.entry_price - t.tp) / (t.sl - t.entry_price) if t.sl != t.entry_price else 0
            else:
                rr = (t.tp - t.entry_price) / (t.entry_price - t.sl) if t.entry_price != t.sl else 0

            res = "✅" if t.result == "WIN" else "❌"
            print(f"{t.entry_time.strftime('%Y-%m-%d'):<12} {t.direction:<6} "
                  f"{t.entry_price:<10.5f} {t.exit_price:<10.5f} {t.tp:<10.5f} {t.sl:<10.5f} "
                  f"{t.pnl_pips:>+7.1f} {rr:>6.2f} {res}")
    else:
        print("No trades found")


if __name__ == "__main__":
    main()
