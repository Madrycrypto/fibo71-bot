"""
Telegram Notification Utility

Sends trading alerts and status messages to Telegram.
"""

import requests
from typing import Optional, Dict, Any
from loguru import logger


class TelegramNotifier:
    """
    Telegram notification handler.

    Sends formatted messages for trade setups,
    entries, exits, and status updates.
    """

    def __init__(self, bot_token: str, chat_id: str):
        """
        Initialize Telegram notifier.

        Args:
            bot_token: Telegram bot token from @BotFather
            chat_id: Chat ID from @userinfobot
        """
        self.bot_token = bot_token
        self.chat_id = chat_id
        self.base_url = f"https://api.telegram.org/bot{bot_token}"

    def send_message(self, text: str, parse_mode: str = "HTML") -> bool:
        """
        Send a text message.

        Args:
            text: Message text (HTML formatted)
            parse_mode: Parse mode (HTML or Markdown)

        Returns:
            True if successful
        """
        url = f"{self.base_url}/sendMessage"

        data = {
            "chat_id": self.chat_id,
            "text": text,
            "parse_mode": parse_mode
        }

        try:
            response = requests.post(url, data=data, timeout=10)
            response.raise_for_status()
            logger.debug("Telegram message sent")
            return True
        except Exception as e:
            logger.error(f"Telegram send failed: {e}")
            return False

    def send_trade_setup(self, setup) -> bool:
        """
        Send formatted trade setup notification.

        Args:
            setup: TradeSetup object

        Returns:
            True if successful
        """
        direction_emoji = "🔴" if setup.direction == "SELL" else "🟢"

        message = f"""
{direction_emoji} <b>CP 2.0 Setup Detected</b>

<b>Symbol:</b> {setup.symbol}
<b>Direction:</b> {setup.direction}
<b>Entry:</b> {setup.entry_price:.5f}
<b>Stop Loss:</b> {setup.sl:.5f}
<b>Take Profit:</b> {setup.tp:.5f}
<b>Lot Size:</b> {setup.lot_size}

<b>Fibonacci Levels:</b>
• 0% (TP): {setup.fib_levels.level_0:.5f}
• 71%: {setup.fib_levels.level_71:.5f}
• 75%: {setup.fib_levels.level_75:.5f}
• 79%: {setup.fib_levels.level_79:.5f}
• 100% (SL): {setup.fib_levels.level_100:.5f}

⏰ {setup.timestamp.strftime('%Y-%m-%d %H:%M:%S')}
"""
        return self.send_message(message)

    def send_order_placed(self, symbol: str, direction: str,
                          entry: float, sl: float, tp: float,
                          lot: float) -> bool:
        """
        Send order placed notification.

        Args:
            symbol: Trading symbol
            direction: BUY or SELL
            entry: Entry price
            sl: Stop loss
            tp: Take profit
            lot: Lot size

        Returns:
            True if successful
        """
        direction_emoji = "🔴" if direction == "SELL" else "🟢"

        message = f"""
{direction_emoji} <b>Order Placed</b>

<b>Symbol:</b> {symbol}
<b>Type:</b> {direction} LIMIT
<b>Lots:</b> {lot}
<b>Entry:</b> {entry:.5f}
<b>SL:</b> {sl:.5f}
<b>TP:</b> {tp:.5f}

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def send_position_closed(self, symbol: str, direction: str,
                             entry: float, exit_price: float,
                             profit: float, reason: str = "TP/SL") -> bool:
        """
        Send position closed notification.

        Args:
            symbol: Trading symbol
            direction: BUY or SELL
            entry: Entry price
            exit_price: Exit price
            profit: Profit/Loss
            reason: Close reason

        Returns:
            True if successful
        """
        profit_emoji = "✅" if profit >= 0 else "❌"
        direction_emoji = "🔴" if direction == "SELL" else "🟢"

        message = f"""
{profit_emoji} <b>Position Closed</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction}
<b>Entry:</b> {entry:.5f}
<b>Exit:</b> {exit_price:.5f}
<b>P/L:</b> ${profit:.2f}
<b>Reason:</b> {reason}

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def send_daily_summary(self, trades: int, pnl: float,
                           win_rate: float) -> bool:
        """
        Send daily summary notification.

        Args:
            trades: Number of trades
            pnl: Total P/L
            win_rate: Win rate percentage

        Returns:
            True if successful
        """
        pnl_emoji = "📈" if pnl >= 0 else "📉"

        message = f"""
📊 <b>Daily Summary</b>

<b>Trades:</b> {trades}
<b>P/L:</b> ${pnl:.2f}
<b>Win Rate:</b> {win_rate:.1f}%

{pnl_emoji} {'Profitable day!' if pnl >= 0 else 'Better luck tomorrow!'}

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def send_error(self, error_message: str) -> bool:
        """
        Send error notification.

        Args:
            error_message: Error description

        Returns:
            True if successful
        """
        message = f"""
⚠️ <b>Error Alert</b>

{error_message}

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def _get_timestamp(self) -> str:
        """Get formatted timestamp."""
        from datetime import datetime
        return datetime.now().strftime('%Y-%m-%d %H:%M:%S')
