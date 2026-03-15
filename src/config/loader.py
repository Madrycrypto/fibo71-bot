"""
Configuration Loader

Loads and validates bot configuration from JSON file.
"""

import json
from pathlib import Path
from typing import Dict, Any
from loguru import logger


def load_config(config_path: Path) -> Dict[str, Any]:
    """
    Load configuration from JSON file.

    Args:
        config_path: Path to config file

    Returns:
        Configuration dictionary
    """
    with open(config_path, 'r') as f:
        config = json.load(f)

    # Validate required sections
    required_sections = ['trading', 'risk', 'strategy']
    for section in required_sections:
        if section not in config:
            raise ValueError(f"Missing required config section: {section}")

    logger.info(f"Configuration loaded from {config_path}")
    return config


def validate_config(config: Dict[str, Any]) -> bool:
    """
    Validate configuration values.

    Args:
        config: Configuration dictionary

    Returns:
        True if valid
    """
    # Risk validation
    if config['risk']['risk_percent'] <= 0 or config['risk']['risk_percent'] > 5:
        logger.warning("Risk percent should be between 0 and 5")

    # Fibonacci validation
    fib_min = config['strategy']['fib_entry_min']
    fib_max = config['strategy']['fib_entry_max']

    if fib_min >= fib_max:
        raise ValueError("fib_entry_min must be less than fib_entry_max")

    if fib_min < 0.5 or fib_max > 1.0:
        logger.warning("Fibonacci levels outside typical range (0.5-1.0)")

    return True
