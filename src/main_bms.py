"""
BMS Fibo Liquidity Bot - Main Entry Point

Automated trading bot implementing the BMS + Fibonacci + Liquidity Sweep strategy.
According to PDF specification for BTCUSDT on 15m timeframe.
"""

import sys
import time
import argparse
from pathlib import Path
from datetime import datetime
from loguru import logger
import pandas as pd
import numpy as np

sys.path.insert(0, str(Path(__file__).parent))

from strategies.bms_fibo_liquidity_strategy import BMSFiboLiquidityStrategy
from utils.telegram_bms import TelegramNotifier
from config.loader import load_config


def setup_logging(log_level):
    logger.remove()
    logger.add(
        sys.stdout,
        level=log_level,
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{message}</cyan>"
    )
    logger.add("logs/bms_fibo_{time}.log", rotation="1 day", retention="30 days", level="DEBUG")


def get_default_config():
    return {
        'trading': {'symbol': 'BTCUSDT', 'timeframe': 'M15', 'magic_number': 710072},
        'risk': {'risk_percent': 1.0, 'max_daily_trades': 3},
        'bms': {'swing_lookback': 5, 'momentum_candles': 3, 'body_threshold': 0.60, 'distance_atr': 0.5},
        'fibonacci': {'entry_min': 0.62, 'entry_max': 0.71},
        'liquidity_sweep': {'min_wick_ratio': 2.0, 'ideal_wick_ratio': 3.0},
        'confirmation': {'body_percent': 0.50},
        'sl': {'buffer_percent': 0.1},
        'filters': {
            'enable_trend': True, 'enable_volume': True, 'enable_volatility': True, 'enable_rr': True,
            'ema_fast': 50, 'ema_slow': 200, 'volume_lookback': 20, 'min_rr_ratio': 2.0
        },
        'telegram': {'enabled': False}
    }


def get_mock_data(symbol, bars=200):
    np.random.seed(int(time.time()) % 10000)
    dates = pd.date_range(end=datetime.now(), periods=bars, freq='15min')
    returns_arr = np.random.randn(bars) * 0.002
    closes = 67000 * np.cumprod(1 + returns_arr)
    highs_arr = closes * (1 + np.abs(np.random.randn(bars)) * 0.005)
    lows_arr = closes * (1 - np.abs(np.random.randn(bars)) * 0.005)
    opens = closes + np.random.randn(bars) * 50
    for i in range(bars):
        highs_arr[i] = max(highs_arr[i], opens[i], closes[i])
        lows_arr[i] = min(lows_arr[i], opens[i], closes[i])
    volumes = np.random.randint(100, 1000, bars)
    return pd.DataFrame({
        'open': opens, 'high': highs_arr, 'low': lows_arr,
        'close': closes, 'volume': volumes
    }, index=dates)


def create_strategy(config):
    return BMSFiboLiquidityStrategy(
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


def run_backtest(config):
    logger.info("Starting backtest...")
    strategy = create_strategy(config)
    df = get_mock_data(config['trading']['symbol'], bars=500)
    logger.info(f"Running backtest on {len(df)} candles...")
    setups = []
    for i in range(100, len(df)):
        df_slice = df.iloc[:i+1].copy()
        setup = strategy.analyze(df_slice)
        if setup:
            setups.append(setup)
            logger.info(f"Trade at {df.index[i]}: {setup.direction} @ {setup.entry_price:.2f}")
            strategy.reset_state()
    logger.info(f"Backtest complete: {len(setups)} setups found")
    if setups:
        longs = sum(1 for s in setups if s.direction == 'BUY')
        shorts = sum(1 for s in setups if s.direction == 'SELL')
        avg_rr = sum(s.rr_ratio for s in setups) / len(setups)
        logger.info(f"LONG: {longs}, SHORT: {shorts}, Avg R:R: 1:{avg_rr:.1f}")


def run_live(config, demo=True):
    mode = "DEMO" if demo else "LIVE"
    logger.info(f"Starting {mode} trading...")
    if not demo:
        response = input("WARNING: LIVE trading. Type 'YES' to confirm: ")
        if response != "YES":
            logger.info("Cancelled.")
            return

    strategy = create_strategy(config)
    telegram = None
    if config['telegram'].get('enabled', False):
        telegram = TelegramNotifier(
            bot_token=config['telegram']['bot_token'],
            chat_id=config['telegram']['chat_id']
        )
        telegram.send_bot_started(
            symbol=config['trading']['symbol'],
            timeframe=config['trading']['timeframe'],
            config=config
        )

    logger.info(f"Strategy: {config['trading']['symbol']} on {config['trading']['timeframe']}")
    logger.info(f"Risk: {config['risk']['risk_percent']}% | Entry zone: {config['fibonacci']['entry_min']}-{config['fibonacci']['entry_max']}")
    logger.info(f"Filters: Trend={config['filters']['enable_trend']}, Vol={config['filters']['enable_volume']}, "
               f"ATR={config['filters']['enable_volatility']}, R:R={config['filters']['enable_rr']}")

    try:
        iteration = 0
        while True:
            iteration += 1
            df = get_mock_data(config['trading']['symbol'], bars=200)
            if df is None or len(df) == 0:
                logger.warning("No data, waiting...")
                time.sleep(10)
                continue
            setup = strategy.analyze(df)
            if setup and telegram:
                telegram.send_trade_entry(setup)
                logger.info(f"Trade setup: {setup.direction} @ {setup.entry_price:.5f}")
            if iteration % 60 == 0:
                status = strategy.get_status()
                logger.info(f"State: {status.state.value} | In zone: {status.in_entry_zone}")
            time.sleep(1)
    except KeyboardInterrupt:
        logger.info("Bot stopped by user")
    finally:
        if telegram:
            telegram.send_bot_stopped("User stopped")
        logger.info("Bot shutdown complete")


def main():
    parser = argparse.ArgumentParser(description="BMS Fibo Liquidity Trading Bot")
    parser.add_argument('--backtest', action='store_true', help='Run backtesting')
    parser.add_argument('--live', action='store_true', help='Run live trading')
    parser.add_argument('--demo', action='store_true', help='Demo mode')
    parser.add_argument('--config', type=str, default='config/bms_settings.json', help='Config file')
    parser.add_argument('--log-level', type=str, default='INFO', choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'])
    parser.add_argument('--no-trend-filter', action='store_true', help='Disable trend filter')
    parser.add_argument('--no-volume-filter', action='store_true', help='Disable volume filter')
    parser.add_argument('--no-volatility-filter', action='store_true', help='Disable volatility filter')
    parser.add_argument('--no-rr-filter', action='store_true', help='Disable R:R filter')
    args = parser.parse_args()

    setup_logging(args.log_level)
    Path("logs").mkdir(exist_ok=True)

    config_path = Path(args.config)
    if config_path.exists():
        config = load_config(config_path)
        logger.info(f"Loaded config from {config_path}")
    else:
        logger.warning(f"Config not found: {config_path}, using defaults")
        config = get_default_config()

    if args.no_trend_filter:
        config['filters']['enable_trend'] = False
    if args.no_volume_filter:
        config['filters']['enable_volume'] = False
    if args.no_volatility_filter:
        config['filters']['enable_volatility'] = False
    if args.no_rr_filter:
        config['filters']['enable_rr'] = False

    if args.backtest:
        run_backtest(config)
    elif args.live or args.demo:
        run_live(config, demo=args.demo or not args.live)
    else:
        parser.print_help()
        print("\n" + "="*60)
        print("BMS FIBO LIQUIDITY BOT - Quick Start")
        print("="*60)
        print("\nModes:")
        print("  python src/main_bms.py --demo        # Forward test")
        print("  python src/main_bms.py --backtest    # Backtest")
        print("  python src/main_bms.py --live        # Live (CAUTION!)")
        print("\nFilter options:")
        print("  --no-trend-filter      Disable EMA trend filter")
        print("  --no-volume-filter     Disable volume filter")
        print("  --no-volatility-filter Disable ATR filter")
        print("  --no-rr-filter         Disable R:R filter")


if __name__ == "__main__":
    main()
