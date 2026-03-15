"""
Fibo 71 Bot - Main Entry Point

CP 2.0 Strategy automated trading bot for MetaTrader 5.
"""

import sys
import time
import argparse
from pathlib import Path
from datetime import datetime
from loguru import logger

import MetaTrader5 as mt5
import pandas as pd

# Add src to path
sys.path.insert(0, str(Path(__file__).parent))

from strategies.fibo71_strategy import CP2Strategy
from utils.mt5_utils import initialize_mt5, shutdown_mt5, get_candles
from utils.telegram import TelegramNotifier
from config.loader import load_config


def setup_logging(log_level: str = "INFO"):
    """Configure logging with loguru."""
    logger.remove()
    logger.add(
        sys.stdout,
        level=log_level,
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{message}</cyan>"
    )
    logger.add(
        "logs/fibo71_{time}.log",
        rotation="1 day",
        retention="30 days",
        level="DEBUG"
    )


def run_backtest(config: dict):
    """Run backtesting mode."""
    logger.info("Starting backtest...")

    # TODO: Implement backtesting with historical data
    # For now, use vectorbt or backtrader

    logger.warning("Backtest mode not yet implemented")
    logger.info("Use --live with --demo flag for forward testing")


def run_live(config: dict, demo: bool = True):
    """Run live trading mode."""
    logger.info(f"Starting {'DEMO' if demo else 'LIVE'} trading...")

    if not demo:
        response = input("⚠️  You are about to run LIVE trading. Type 'YES' to confirm: ")
        if response != "YES":
            logger.info("Cancelled.")
            return

    # Initialize MT5
    if not initialize_mt5():
        logger.error("Failed to initialize MT5")
        return

    # Load config
    symbol = config['trading']['symbol']
    timeframe = config['trading']['timeframe']

    # Map timeframe string to MT5 constant
    tf_map = {
        'M15': mt5.TIMEFRAME_M15,
        'H1': mt5.TIMEFRAME_H1,
        'H4': mt5.TIMEFRAME_H4,
    }
    mt5_timeframe = tf_map.get(timeframe, mt5.TIMEFRAME_H4)

    # Initialize strategy
    strategy = CP2Strategy(
        symbol=symbol,
        timeframe=timeframe,
        risk_percent=config['risk']['risk_percent'],
        fib_entry_min=config['strategy']['fib_entry_min'],
        fib_entry_max=config['strategy']['fib_entry_max'],
        bos_lookback=config['strategy']['bos_lookback'],
        min_imbalance_pips=config['strategy']['min_imbalance_pips'],
        enable_liquidity_sweep=config['filters']['enable_liquidity_sweep']
    )

    # Initialize Telegram if enabled
    telegram = None
    if config['telegram']['enabled']:
        telegram = TelegramNotifier(
            bot_token=config['telegram']['bot_token'],
            chat_id=config['telegram']['chat_id']
        )
        telegram.send_message(f"🤖 Fibo 71 Bot started on {symbol} ({timeframe})")

    logger.info(f"Strategy initialized: {symbol} on {timeframe}")
    logger.info(f"Risk: {config['risk']['risk_percent']}% per trade")
    logger.info(f"Entry zone: {config['strategy']['fib_entry_min']}-{config['strategy']['fib_entry_max']}")

    try:
        while True:
            # Get latest candles
            df = get_candles(symbol, mt5_timeframe, bars=100)

            if df is None or len(df) == 0:
                logger.warning("No data received, waiting...")
                time.sleep(10)
                continue

            # Run strategy
            setup = strategy.on_tick(df)

            if setup and telegram:
                telegram.send_trade_setup(setup)

            # Print status every minute
            if datetime.now().second == 0:
                status = strategy.get_status()
                logger.info(f"Status: {status}")

            # Sleep to avoid overloading
            time.sleep(1)

    except KeyboardInterrupt:
        logger.info("Bot stopped by user")
    finally:
        if telegram:
            telegram.send_message("🛑 Fibo 71 Bot stopped")
        shutdown_mt5()


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Fibo 71 Trading Bot (CP 2.0 Strategy)")

    parser.add_argument('--backtest', action='store_true', help='Run backtesting')
    parser.add_argument('--live', action='store_true', help='Run live trading')
    parser.add_argument('--demo', action='store_true', help='Demo mode (forward test)')
    parser.add_argument('--config', type=str, default='config/settings.json',
                       help='Path to config file')
    parser.add_argument('--log-level', type=str, default='INFO',
                       choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
                       help='Logging level')

    args = parser.parse_args()

    # Setup logging
    setup_logging(args.log_level)

    # Create logs directory
    Path("logs").mkdir(exist_ok=True)

    # Load configuration
    config_path = Path(args.config)
    if not config_path.exists():
        logger.warning(f"Config file not found: {config_path}")
        logger.info("Using default configuration")
        config = {
            'trading': {'symbol': 'EURUSD', 'timeframe': 'H4', 'magic_number': 710071},
            'risk': {'risk_percent': 1.0},
            'strategy': {
                'fib_entry_min': 0.71,
                'fib_entry_max': 0.79,
                'bos_lookback': 50,
                'min_imbalance_pips': 5
            },
            'filters': {
                'enable_imbalance': True,
                'enable_liquidity_sweep': True
            },
            'telegram': {'enabled': False}
        }
    else:
        config = load_config(config_path)

    # Run appropriate mode
    if args.backtest:
        run_backtest(config)
    elif args.live or args.demo:
        run_live(config, demo=args.demo or not args.live)
    else:
        parser.print_help()
        logger.info("\nQuick start:")
        logger.info("  python src/main.py --demo        # Forward test on demo")
        logger.info("  python src/main.py --backtest    # Run backtest")
        logger.info("  python src/main.py --live        # Live trading (CAUTION!)")


if __name__ == "__main__":
    main()
