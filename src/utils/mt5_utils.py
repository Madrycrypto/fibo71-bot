"""
MetaTrader 5 Utility Functions

Handles connection, data retrieval, and order execution.
"""

import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from loguru import logger


def initialize_mt5() -> bool:
    """
    Initialize MT5 connection.

    Returns:
        True if successful
    """
    if not mt5.initialize():
        logger.error(f"MT5 initialize() failed: {mt5.last_error()}")
        return False

    logger.info(f"MT5 initialized: {mt5.version()}")
    return True


def shutdown_mt5():
    """Shutdown MT5 connection."""
    mt5.shutdown()
    logger.info("MT5 shutdown")


def get_account_info() -> Optional[Dict[str, Any]]:
    """
    Get account information.

    Returns:
        Dictionary with account info or None
    """
    info = mt5.account_info()
    if info is None:
        logger.error(f"Failed to get account info: {mt5.last_error()}")
        return None

    return {
        'balance': info.balance,
        'equity': info.equity,
        'margin': info.margin,
        'free_margin': info.margin_free,
        'profit': info.profit,
        'currency': info.currency
    }


def get_candles(symbol: str, timeframe: int, bars: int = 100) -> Optional[pd.DataFrame]:
    """
    Get historical candles from MT5.

    Args:
        symbol: Trading symbol
        timeframe: MT5 timeframe constant
        bars: Number of bars to retrieve

    Returns:
        DataFrame with OHLCV data or None
    """
    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, bars)

    if rates is None or len(rates) == 0:
        logger.error(f"Failed to get candles for {symbol}: {mt5.last_error()}")
        return None

    df = pd.DataFrame(rates)
    df['time'] = pd.to_datetime(df['time'], unit='s')
    df.set_index('time', inplace=True)

    return df


def get_current_price(symbol: str) -> Optional[Dict[str, float]]:
    """
    Get current bid/ask prices.

    Args:
        symbol: Trading symbol

    Returns:
        Dictionary with bid/ask or None
    """
    tick = mt5.symbol_info_tick(symbol)

    if tick is None:
        logger.error(f"Failed to get tick for {symbol}: {mt5.last_error()}")
        return None

    return {
        'bid': tick.bid,
        'ask': tick.ask,
        'spread': tick.ask - tick.bid,
        'time': datetime.fromtimestamp(tick.time)
    }


def place_order(symbol: str, order_type: str, volume: float,
                price: Optional[float] = None, sl: float = 0, tp: float = 0,
                comment: str = "", magic: int = 710071) -> Optional[int]:
    """
    Place a market or pending order.

    Args:
        symbol: Trading symbol
        order_type: 'BUY', 'SELL', 'BUY_LIMIT', 'SELL_LIMIT'
        volume: Lot size
        price: Price for pending orders
        sl: Stop loss price
        tp: Take profit price
        comment: Order comment
        magic: Magic number

    Returns:
        Order ticket or None if failed
    """
    # Map order types
    type_map = {
        'BUY': mt5.ORDER_TYPE_BUY,
        'SELL': mt5.ORDER_TYPE_SELL,
        'BUY_LIMIT': mt5.ORDER_TYPE_BUY_LIMIT,
        'SELL_LIMIT': mt5.ORDER_TYPE_SELL_LIMIT
    }

    action_map = {
        'BUY': mt5.TRADE_ACTION_DEAL,
        'SELL': mt5.TRADE_ACTION_DEAL,
        'BUY_LIMIT': mt5.TRADE_ACTION_PENDING,
        'SELL_LIMIT': mt5.TRADE_ACTION_PENDING
    }

    mt5_type = type_map.get(order_type.upper())
    mt5_action = action_map.get(order_type.upper())

    if mt5_type is None:
        logger.error(f"Invalid order type: {order_type}")
        return None

    # Get current price for market orders
    if price is None and mt5_action == mt5.TRADE_ACTION_DEAL:
        tick = mt5.symbol_info_tick(symbol)
        price = tick.ask if 'BUY' in order_type else tick.bid

    request = {
        "action": mt5_action,
        "symbol": symbol,
        "volume": volume,
        "type": mt5_type,
        "price": price,
        "sl": sl,
        "tp": tp,
        "deviation": 20,
        "magic": magic,
        "comment": comment,
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }

    result = mt5.order_send(request)

    if result.retcode != mt5.TRADE_RETCODE_DONE:
        logger.error(f"Order failed: {result.comment} (code: {result.retcode})")
        return None

    logger.info(f"Order placed: {order_type} {volume} {symbol} @ {price}")
    return result.order


def close_position(ticket: int, symbol: str, volume: float,
                   position_type: int) -> bool:
    """
    Close an open position.

    Args:
        ticket: Position ticket
        symbol: Trading symbol
        volume: Volume to close
        position_type: MT5 position type

    Returns:
        True if successful
    """
    tick = mt5.symbol_info_tick(symbol)

    close_type = mt5.ORDER_TYPE_SELL if position_type == mt5.POSITION_TYPE_BUY else mt5.ORDER_TYPE_BUY
    close_price = tick.bid if position_type == mt5.POSITION_TYPE_BUY else tick.ask

    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": symbol,
        "volume": volume,
        "type": close_type,
        "position": ticket,
        "price": close_price,
        "deviation": 20,
        "magic": 710071,
        "comment": "Close position",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }

    result = mt5.order_send(request)

    if result.retcode != mt5.TRADE_RETCODE_DONE:
        logger.error(f"Close failed: {result.comment}")
        return False

    logger.info(f"Position closed: {ticket}")
    return True


def get_open_positions(symbol: Optional[str] = None) -> list:
    """
    Get all open positions.

    Args:
        symbol: Filter by symbol (optional)

    Returns:
        List of position dictionaries
    """
    if symbol:
        positions = mt5.positions_get(symbol=symbol)
    else:
        positions = mt5.positions_get()

    if positions is None:
        return []

    return [
        {
            'ticket': pos.ticket,
            'symbol': pos.symbol,
            'type': 'BUY' if pos.type == mt5.POSITION_TYPE_BUY else 'SELL',
            'volume': pos.volume,
            'price_open': pos.price_open,
            'price_current': pos.price_current,
            'sl': pos.sl,
            'tp': pos.tp,
            'profit': pos.profit,
            'comment': pos.comment,
            'magic': pos.magic
        }
        for pos in positions
    ]
