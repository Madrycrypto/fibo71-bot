"""
BMS Fibo Liquidity Bot - Enhanced Backtest Script

Tests the CORRECTED algorithm with realistic market simulation:
1. BMS detection with momentum
2. Extremum tracking after BMS
3. Extremum confirmation (price retraces through BMS level)
4. Fibonacci calculation
5. Entry into Fib zone
6. Liquidity sweep detection
7. Confirmation candle
8. Trade execution with 3 TP levels

Run: python src/backtest_bms.py
"""

import sys
from pathlib import Path
from datetime import datetime, timedelta
import pandas as pd
import numpy as np
from loguru import logger

sys.path.insert(0, str(Path(__file__).parent))

from strategies.bms_fibo_liquidity_strategy import BMSFiboLiquidityStrategy, StrategyState


def setup_logging():
    logger.remove()
    logger.add(
        sys.stdout,
        level="INFO",
        format="<green>{time:HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{message}</cyan>"
    )


def generate_realistic_data(bars: int = 1000, start_price: float = 67000) -> pd.DataFrame:
    """
    Generate realistic OHLCV data with trends, swings, and patterns.
    """
    np.random.seed(42)

    # Generate base price with trends
    returns = np.zeros(bars)

    # Add trend periods
    trend_length = bars // 10
    for i in range(10):
        start = i * trend_length
        end = (i + 1) * trend_length
        if i % 2 == 0:
            # Uptrend
            returns[start:end] = np.random.randn(trend_length) * 0.001 + 0.0005
        else:
            # Downtrend
            returns[start:end] = np.random.randn(trend_length) * 0.001 - 0.0005

    # Add some volatility spikes
    spike_indices = np.random.choice(bars, size=20, replace=False)
    for idx in spike_indices:
        returns[idx] *= 3

    # Calculate prices
    closes = start_price * np.cumprod(1 + returns)

    # Generate OHLC
    base_volatility = 0.003
    highs = []
    lows = []
    opens = []

    for i in range(bars):
        volatility = base_volatility * (1 + np.abs(returns[i]) * 5)
        open_price = closes[i] * (1 + np.random.randn() * volatility * 0.3)
        high_price = max(open_price, closes[i]) * (1 + np.random.rand() * volatility)
        low_price = min(open_price, closes[i]) * (1 - np.random.rand() * volatility)

        opens.append(open_price)
        highs.append(high_price)
        lows.append(low_price)

    # Generate volume
    volumes = np.random.randint(100, 1000, bars) * (1 + np.abs(returns) * 100)

    # Create DataFrame
    dates = pd.date_range(end=datetime.now(), periods=bars, freq='15min')
    df = pd.DataFrame({
        'open': opens,
        'high': highs,
        'low': lows,
        'close': closes,
        'volume': volumes
    }, index=dates)

    return df


def run_backtest(config: dict, bars: int = 1000):
    """
    Run comprehensive backtest.
    """
    logger.info("=" * 60)
    logger.info("BMS FIBO LIQUIDITY BACKTEST")
    logger.info("=" * 60)

    # Generate data
    logger.info(f"Generating {bars} bars of realistic market data...")
    df = generate_realistic_data(bars, start_price=67000)

    # Create strategy
    strategy = BMSFiboLiquidityStrategy(
        symbol=config['trading']['symbol'],
        timeframe=config['trading']['timeframe'],
        risk_percent=config['risk']['risk_percent'],
        max_daily_trades=config['risk']['max_daily_trades'],
        bms_swing_lookback=config['bms']['swing_lookback'],
        bms_momentum_candles=config['bms']['momentum_candles'],
        bms_body_threshold=config['bms']['body_threshold'],
        bms_distance_atr=config['bms']['distance_atr'],
        fib_entry_min=config['fibonacci']['entry_min'],
        fib_entry_max=config['fibonacci']['entry_max'],
        sweep_min_wick_ratio=config['liquidity_sweep']['min_wick_ratio'],
        sweep_ideal_wick_ratio=config['liquidity_sweep']['ideal_wick_ratio'],
        confirmation_body_pct=config['confirmation']['body_percent'],
        sl_buffer_percent=config['sl']['buffer_percent'],
        enable_trend_filter=config['filters']['enable_trend'],
        enable_volume_filter=config['filters']['enable_volume'],
        enable_volatility_filter=config['filters']['enable_volatility'],
        enable_rr_filter=config['filters']['enable_rr'],
        ema_fast=config['filters']['ema_fast'],
        ema_slow=config['filters']['ema_slow'],
        volume_lookback=config['filters']['volume_lookback'],
        min_rr_ratio=config['filters']['min_rr_ratio']
    )

    # Track results
    setups = []
    state_changes = {
        'idle': 0,
        'bms_detected': 0,
        'tracking_extremum': 0,
        'extremum_confirmed': 0,
        'in_fib_zone': 0,
        'sweep_detected': 0,
        'in_trade': 0
    }

    logger.info(f"Running backtest on {len(df)} candles...")
    logger.info(f"Period: {df.index[0]} to {df.index[-1]}")
    logger.info("")

    # Run backtest
    warmup = 50
    for i in range(warmup, len(df)):
        df_slice = df.iloc[:i+1].copy()

        # Get state before
        prev_state = strategy.state

        # Analyze
        setup = strategy.analyze(df_slice)

        # Track state changes
        current_state = strategy.state.value
        if strategy.state == StrategyState.TRACKING_EXTREMUM:
            state_changes['tracking_extremum'] += 1

        # Log BMS detection
        if strategy.state == StrategyState.BMS_DETECTED and prev_state == StrategyState.IDLE:
            state_changes['bms_detected'] += 1
            logger.info(f"[{df.index[i]}] 🔥 BMS DETECTED")

        # Log extremum confirmation
        if strategy.state == StrategyState.EXTREMUM_CONFIRMED and prev_state in [StrategyState.TRACKING_EXTREMUM, StrategyState.BMS_DETECTED]:
            state_changes['extremum_confirmed'] += 1
            if strategy.confirmed_extremum:
                logger.info(f"[{df.index[i]}] ✅ EXTREMUM CONFIRMED at {strategy.confirmed_extremum:.2f}")

        # Log Fib zone entry
        if strategy.state == StrategyState.IN_FIB_ZONE and prev_state == StrategyState.EXTREMUM_CONFIRMED:
            state_changes['in_fib_zone'] += 1
            logger.info(f"[{df.index[i]}] 📍 PRICE IN FIB ZONE")

        # Log sweep detection
        if strategy.state == StrategyState.SWEEP_DETECTED and prev_state == StrategyState.IN_FIB_ZONE:
            state_changes['sweep_detected'] += 1
            logger.info(f"[{df.index[i]}] 💧 LIQUIDITY SWEEP")

        # Handle trade setup
        if setup:
            setups.append(setup)
            logger.info("")
            logger.info(f"[{df.index[i]}] 🚀 TRADE EXECUTED")
            logger.info(f"   Direction: {setup.direction}")
            logger.info(f"   Entry: {setup.entry_price:.2f}")
            logger.info(f"   SL: {setup.sl_price:.2f}")
            logger.info(f"   TP1: {setup.tp1_price:.2f} | TP2: {setup.tp2_price:.2f} | TP3: {setup.tp3_price:.2f}")
            logger.info(f"   R:R: 1:{setup.rr_ratio:.1f}")
            logger.info(f"   Confirmed Extremum: {setup.confirmed_extremum_price:.2f}")
            logger.info("")

            # Reset for next trade
            strategy.reset_state()

    # Calculate statistics
    logger.info("=" * 60)
    logger.info("BACKTEST RESULTS")
    logger.info("=" * 60)

    logger.info(f"\n📊 State Statistics:")
    logger.info(f"   BMS Detections: {state_changes['bms_detected']}")
    logger.info(f"   Extremum Confirmations: {state_changes['extremum_confirmed']}")
    logger.info(f"   Fib Zone Entries: {state_changes['in_fib_zone']}")
    logger.info(f"   Liquidity Sweeps: {state_changes['sweep_detected']}")

    if setups:
        longs = sum(1 for s in setups if s.direction == 'BUY')
        shorts = sum(1 for s in setups if s.direction == 'SELL')
        avg_rr = sum(s.rr_ratio for s in setups) / len(setups)
        min_rr = min(s.rr_ratio for s in setups)
        max_rr = max(s.rr_ratio for s in setups)

        logger.info(f"\n📈 Trade Statistics:")
        logger.info(f"   Total Trades: {len(setups)}")
        logger.info(f"   LONG: {longs} | SHORT: {shorts}")
        logger.info(f"   Avg R:R: 1:{avg_rr:.1f}")
        logger.info(f"   Min R:R: 1:{min_rr:.1f}")
        logger.info(f"   Max R:R: 1:{max_rr:.1f}")

        # Calculate conversion rates
        if state_changes['bms_detected'] > 0:
            bms_to_extremum = state_changes['extremum_confirmed'] / state_changes['bms_detected'] * 100
            logger.info(f"\n📉 Conversion Rates:")
            logger.info(f"   BMS → Extremum: {bms_to_extremum:.1f}%")

            if state_changes['extremum_confirmed'] > 0:
                extremum_to_trade = len(setups) / state_changes['extremum_confirmed'] * 100
                logger.info(f"   Extremum → Trade: {extremum_to_trade:.1f}%")

        # Print trade details
        logger.info(f"\n📋 Trade Details:")
        for i, setup in enumerate(setups, 1):
            logger.info(f"   Trade {i}: {setup.direction} @ {setup.entry_price:.2f}, "
                       f"SL: {setup.sl_price:.2f}, TP1: {setup.tp1_price:.2f}, R:R: 1:{setup.rr_ratio:.1f}")
    else:
        logger.info("\n⚠️ No trades found in this period.")
        logger.info("   Try increasing the number of bars or adjusting parameters.")

    return setups


def main():
    setup_logging()

    # Default configuration
    config = {
        'trading': {'symbol': 'BTCUSDT', 'timeframe': 'M15'},
        'risk': {'risk_percent': 1.0, 'max_daily_trades': 3},
        'bms': {'swing_lookback': 5, 'momentum_candles': 3, 'body_threshold': 0.60, 'distance_atr': 0.5},
        'fibonacci': {'entry_min': 0.62, 'entry_max': 0.71},
        'liquidity_sweep': {'min_wick_ratio': 2.0, 'ideal_wick_ratio': 3.0},
        'confirmation': {'body_percent': 0.50},
        'sl': {'buffer_percent': 0.1},
        'filters': {
            'enable_trend': True,
            'enable_volume': True,
            'enable_volatility': True,
            'enable_rr': True,
            'ema_fast': 50,
            'ema_slow': 200,
            'volume_lookback': 20,
            'min_rr_ratio': 2.0
        }
    }

    # Run backtest with more data
    setups = run_backtest(config, bars=2000)

    logger.info("\n" + "=" * 60)
    logger.info("Backtest complete!")
    logger.info("=" * 60)


if __name__ == "__main__":
    main()
