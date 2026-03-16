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
        logger.warning(f"Config file not found: {config_path}")
        logger.info("Using default configuration")
        return get_default_config()

    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in config file: {e}")
        logger.info("Using default configuration")
        return get_default_config()

    # Validate required sections
    required_sections = ['trading', 'bms', 'fibonacci', 'liquidity_sweep', 'confirmation', 'sl']

    for section in required_sections:
        if section not in config:
            logger.warning(f"Missing required section: {section}, using defaults")
            config[section] = get_default_config().get(section, {})

    # Validate filters section
    if 'filters' not in config:
        config['filters'] = get_default_config()['filters']
    else:
        # Ensure all filter settings exist
        default_filters = get_default_config()['filters']
        for key, value in default_filters.items():
            if key not in config['filters']:
                config['filters'][key] = value

    # Validate extremum section
    if 'extremum' not in config:
        config['extremum'] = get_default_config()['extremum']

    # Validate telegram section
    if 'telegram' not in config:
        config['telegram'] = {'enabled': False, 'bot_token': '', 'chat_id': ''}
    else:
        if 'enabled' not in config['telegram']:
            config['telegram']['enabled'] = False
        if 'bot_token' not in config['telegram']:
            config['telegram']['bot_token'] = ''
        if 'chat_id' not in config['telegram']:
            config['telegram']['chat_id'] = ''

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
            'enable_volume': True,
            'enable_volatility': True,
            'enable_rr': True,
            'ema_fast': 50,
            'ema_slow': 200,
            'volume_lookback': 20,
            'min_rr_ratio': 2.0
        },
        'extremum': {
            'min_candles': 1,
            'timeout_candles': 50
        },
        'telegram': {
            'enabled': False,
            'bot_token': '',
            'chat_id': ''
        }
    }
