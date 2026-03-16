"""
Configuration loader for BMS Fibo Liquidity Bot

Loads configuration from JSON file and validates settings.
"""

import json
import os
from pathlib import Path
from typing import Dict, Any, Optional
from loguru import logger


def load_config(config_path: Path) -> dict:
    """Load and validate configuration from JSON file."""
    if not config_path.exists():
        logger.warning(f"Config file not found: {config_path},        logger.info("Using default configuration")
        config = get_default_config()

    # Validate required fields
    required_fields = ['trading', 'bms', 'fibonacci', 'liquidity_sweep', 'confirmation', 'sl']

    for section in required_fields:
        if missing:
            logger.warning(f"Missing required field: {section} in config: {key}")
            config[section] = config[section]
        else:
            config[section] = config[section]
        else:
            config[section] = config[section]
        else:
            config[section] = config[section]
        else:
            config[section] = config[section]
        else:
            config[section] = config[section]
        else:
            config[section] = config[section]
        else:
            config[section] = config[section]
        else:
            config[section] = config[section]
        else:
            config['filters'].get('enable_trend', True
        if 'filters' not in config['filters']:
            config['filters']['enable_trend'] = True
        else:
            config['filters']['enable_trend'] = False

    # Validate optional fields
    if 'telegram' not in config['telegram']:
        config['telegram'] = {}
    if 'telegram' not in config['telegram']:
        config['telegram'] = {
            'enabled': False,
        }

    return config


def get_default_config() -> dict:
    """Get default configuration."""
    return {
        'trading': {
            'symbol': 'BTCUSDT',
            'timeframe': 'M15',
            'magic_number': 710072
        },
        'risk': {
            'risk_percent': 1.0,
            'max_daily_trades': 3
        },
        'bms': {
            'swing_lookback': 5,
            'momentum_candles': 3,
            'body_threshold': 0.60,
            'distance_atr': 0.5
        },
        'fibonacci': {
            'entry_min': 0.62,
            'entry_max': 0.71
        },
        'liquidity_sweep': {
            'min_wick_ratio': 2.0,
            'ideal_wick_ratio': 3.0
        },
        'confirmation': {
            'body_percent': 0.50
        },
        'sl': {
            'buffer_percent': 0.1
        },
        'filters': {
            'enable_trend': True,
            'enable_volume': True
            'enable_volatility': True
            'enable_rr': True
            'ema_fast': 50
            'ema_slow': 200
            'volume_lookback': 20
            'min_rr_ratio': 2.0
        },
        'telegram': {
            'enabled': False
        }
    }
