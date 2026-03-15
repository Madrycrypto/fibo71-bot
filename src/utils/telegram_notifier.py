"""
Fibo 71 - Telegram Notifier

Handles all Telegram communications for trading signals and notifications.
"""

import asyncio
import aiohttp
from typing import Optional, Dict, Any
from datetime import datetime
import json


class TelegramNotifier:
    """Async Telegram client for trading notifications."""

    def __init__(self, bot_token: str, chat_id: str):
        self.bot_token = bot_token
        self.chat_id = chat_id
        self.base_url = f"https://api.telegram.org/bot{bot_token}"
        self.session: Optional[aiohttp.ClientSession] = None

    async def __aenter__(self):
        self.session = aiohttp.ClientSession()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    async def send_message(self, text: str, parse_mode: str = "HTML") -> bool:
        """Send a message to the configured chat."""
        if not self.session:
            self.session = aiohttp.ClientSession()

        url = f"{self.base_url}/sendMessage"
        payload = {
            "chat_id": self.chat_id,
            "text": text,
            "parse_mode": parse_mode
        }

        try:
            async with self.session.post(url, json=payload) as response:
                result = await response.json()
                if result.get("ok"):
                    return True
                else:
                    print(f"Telegram error: {result.get('description')}")
                    return False
        except Exception as e:
            print(f"Telegram send error: {e}")
            return False

    async def send_photo(self, photo_url: str, caption: str = "") -> bool:
        """Send a photo with optional caption."""
        if not self.session:
            self.session = aiohttp.ClientSession()

        url = f"{self.base_url}/sendPhoto"
        payload = {
            "chat_id": self.chat_id,
            "photo": photo_url,
            "caption": caption,
            "parse_mode": "HTML"
        }

        try:
            async with self.session.post(url, json=payload) as response:
                result = await response.json()
                return result.get("ok", False)
        except Exception as e:
            print(f"Telegram photo error: {e}")
            return False

    # ==================== TRADING NOTIFICATIONS ====================

    async def send_bot_started(self, symbol: str, timeframe: str, zone: str):
        """Notify that bot has started."""
        message = f"""
🚀 <b>FIBO 71 BOT STARTED</b>

📊 Symbol: <code>{symbol}</code>
⏰ Timeframe: <code>{timeframe}</code>
📍 Entry Zone: <code>{zone}</code>
🕐 Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

✅ Bot is now monitoring for setups...
"""
        return await self.send_message(message)

    async def send_bos_detected(self, direction: str, swing_high: float,
                                swing_low: float, symbol: str):
        """Notify BOS detection."""
        emoji = "🔴" if direction == "SELL" else "🟢"
        range_pips = abs(swing_high - swing_low) / 0.0001

        message = f"""
{emoji} <b>BOS DETECTED</b>

📊 Symbol: <code>{symbol}</code>
📈 Direction: <b>{direction}</b>

📍 Swing High: <code>{swing_high:.5f}</code>
📍 Swing Low: <code>{swing_low:.5f}</code>
📏 Range: <code>{range_pips:.1f} pips</code>

⏳ Waiting for retracement to entry zone...
"""
        return await self.send_message(message)

    async def send_entry_signal(self, direction: str, entry_price: float,
                                tp: float, sl: float, symbol: str,
                                fib_zone: str, rr: float):
        """Notify entry signal."""
        emoji = "🔴" if direction == "SELL" else "🟢"
        tp_pips = abs(tp - entry_price) / 0.0001
        sl_pips = abs(sl - entry_price) / 0.0001

        message = f"""
⚡ <b>ENTRY SIGNAL</b>

{emoji} <b>{direction} {symbol}</b>

📍 Entry: <code>{entry_price:.5f}</code>
🎯 TP: <code>{tp:.5f}</code> ({tp_pips:.1f} pips)
🛑 SL: <code>{sl:.5f}</code> ({sl_pips:.1f} pips)

📍 Fibo Zone: <code>{fib_zone}</code>
📊 R:R: <code>1:{rr:.2f}</code>

⏰ {datetime.now().strftime('%H:%M:%S')}
"""
        return await self.send_message(message)

    async def send_trade_closed(self, direction: str, entry_price: float,
                                exit_price: float, result: str, pips: float,
                                symbol: str, reason: str = "TP/SL"):
        """Notify trade closed."""
        if result == "WIN":
            emoji = "✅"
            result_text = "PROFIT"
        else:
            emoji = "❌"
            result_text = "LOSS"

        message = f"""
{emoji} <b>TRADE CLOSED - {result_text}</b>

📊 {direction} {symbol}

📍 Entry: <code>{entry_price:.5f}</code>
📍 Exit: <code>{exit_price:.5f}</code>
📈 Result: <code>{pips:+.1f} pips</code>

📝 Reason: {reason}
⏰ {datetime.now().strftime('%H:%M:%S')}
"""
        return await self.send_message(message)

    async def send_daily_summary(self, trades: int, wins: int, losses: int,
                                 total_pips: float, win_rate: float):
        """Send daily trading summary."""
        if total_pips >= 0:
            emoji = "📈"
        else:
            emoji = "📉"

        message = f"""
📊 <b>DAILY SUMMARY</b>

{emoji} <b>P/L: {total_pips:+.1f} pips</b>

📊 Trades: <code>{trades}</code>
✅ Wins: <code>{wins}</code>
❌ Losses: <code>{losses}</code>
📈 Win Rate: <code>{win_rate:.1f}%</code>

⏰ {datetime.now().strftime('%Y-%m-%d %H:%M')}
"""
        return await self.send_message(message)

    async def send_error(self, error_msg: str, details: str = ""):
        """Send error notification."""
        message = f"""
⚠️ <b>BOT ERROR</b>

❌ Error: <code>{error_msg}</code>
📝 Details: <code>{details}</code>

⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
"""
        return await self.send_message(message)

    async def send_risk_alert(self, alert_type: str, value: float, limit: float):
        """Send risk management alert."""
        message = f"""
🛡️ <b>RISK ALERT</b>

⚠️ {alert_type}: <code>{value:.1f}%</code>
🚫 Limit: <code>{limit:.1f}%</code>

⛔ Trading paused until next session.

⏰ {datetime.now().strftime('%Y-%m-%d %H:%M')}
"""
        return await self.send_message(message)


# ==================== SYNC WRAPPER ====================

class TelegramSync:
    """Synchronous wrapper for Telegram operations."""

    def __init__(self, bot_token: str, chat_id: str):
        self.notifier = TelegramNotifier(bot_token, chat_id)

    def _run_async(self, coro):
        """Run async coroutine synchronously."""
        try:
            loop = asyncio.get_event_loop()
        except RuntimeError:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)

        return loop.run_until_complete(coro)

    def send_message(self, text: str) -> bool:
        return self._run_async(self.notifier.send_message(text))

    def send_bot_started(self, symbol: str, timeframe: str, zone: str) -> bool:
        return self._run_async(self.notifier.send_bot_started(symbol, timeframe, zone))

    def send_bos_detected(self, direction: str, swing_high: float,
                          swing_low: float, symbol: str) -> bool:
        return self._run_async(self.notifier.send_bos_detected(
            direction, swing_high, swing_low, symbol))

    def send_entry_signal(self, direction: str, entry_price: float,
                          tp: float, sl: float, symbol: str,
                          fib_zone: str, rr: float) -> bool:
        return self._run_async(self.notifier.send_entry_signal(
            direction, entry_price, tp, sl, symbol, fib_zone, rr))

    def send_trade_closed(self, direction: str, entry_price: float,
                          exit_price: float, result: str, pips: float,
                          symbol: str, reason: str = "TP/SL") -> bool:
        return self._run_async(self.notifier.send_trade_closed(
            direction, entry_price, exit_price, result, pips, symbol, reason))

    def send_daily_summary(self, trades: int, wins: int, losses: int,
                           total_pips: float, win_rate: float) -> bool:
        return self._run_async(self.notifier.send_daily_summary(
            trades, wins, losses, total_pips, win_rate))


# ==================== TEST ====================

async def test_telegram():
    """Test Telegram connection."""
    import os

    bot_token = os.getenv("TELEGRAM_BOT_TOKEN", "YOUR_BOT_TOKEN")
    chat_id = os.getenv("TELEGRAM_CHAT_ID", "YOUR_CHAT_ID")

    async with TelegramNotifier(bot_token, chat_id) as tg:
        # Test basic message
        print("Testing basic message...")
        await tg.send_bot_started("AUDUSD", "H1", "71-79%")

        # Test BOS
        print("Testing BOS notification...")
        await tg.send_bos_detected("SELL", 0.6500, 0.6400, "AUDUSD")

        # Test entry
        print("Testing entry signal...")
        await tg.send_entry_signal("SELL", 0.6470, 0.6400, 0.6500,
                                   "AUDUSD", "71-79%", 1.5)

        # Test close
        print("Testing trade closed...")
        await tg.send_trade_closed("SELL", 0.6470, 0.6400, "WIN",
                                   70.0, "AUDUSD", "TP Hit")

        print("✅ All tests completed!")


if __name__ == "__main__":
    asyncio.run(test_telegram())
