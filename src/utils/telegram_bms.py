"""
Telegram Notification Utility for BMS Fibo Liquidity Bot

Enhanced notification system with:
- BMS detection alerts
- Extremum confirmation alerts (NEW)
- Fibonacci zone entry alerts
- Liquidity sweep alerts
- Confirmation candle alerts
- Trade entry with 3 TP levels
- Filter blocked notifications
- TP1/TP2/TP3 hit notifications
- Risk warning notifications
"""

import requests
from typing import Optional, Dict, Any
from loguru import logger
from datetime import datetime


class TelegramNotifier:
    """
    Enhanced Telegram notification handler for BMS Strategy.
    """

    def __init__(self, bot_token: str, chat_id: str):
        self.bot_token = bot_token
        self.chat_id = chat_id
        self.base_url = f"https://api.telegram.org/bot{bot_token}"

    def send_message(self, text: str, parse_mode: str = "HTML") -> bool:
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

    def send_bms_detected(self, bms_direction: str, bms_level: float,
                          swing_point: float, symbol: str) -> bool:
        """Send BMS detection notification."""
        direction_emoji = "🟢" if bms_direction == "BULLISH" else "🔴"
        trade_dir = "LONG" if bms_direction == "BULLISH" else "SHORT"

        message = f"""🔥 <b>BMS DETECTED [{bms_direction}]</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction_emoji} {trade_dir}
<b>BMS Level:</b> {bms_level:.5f}
<b>Swing Point:</b> {swing_point:.5f}

⏳ <i>Tracking extremum...</i>

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def send_extremum_confirmed(self, bms_direction: str, confirmed_extremum: float,
                                bms_level: float, fib_levels: dict, symbol: str) -> bool:
        """Send extremum confirmation notification (NEW)."""
        direction_emoji = "🟢" if bms_direction == "BULLISH" else "🔴"

        message = f"""✅ <b>EXTREMUM CONFIRMED</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction_emoji} {bms_direction}
<b>Confirmed Extremum:</b> {confirmed_extremum:.5f}
<b>BMS Level:</b> {bms_level:.5f}

<b>Fibonacci Calculated:</b>
• Entry Zone: {fib_levels['entry_zone_min']:.5f} - {fib_levels['entry_zone_max']:.5f}
• SL: {fib_levels['sl']:.5f}
• TP1: {fib_levels['tp1']:.5f}

⏳ <i>Waiting for price to enter Fib zone...</i>

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def send_fib_zone_entry(self, price: float, fib_pct: float,
                            symbol: str) -> bool:
        """Send Fibonacci zone entry notification."""
        message = f"""📍 <b>PRICE IN FIB ZONE</b>

<b>Symbol:</b> {symbol}
<b>Current Price:</b> {price:.5f}
<b>Fib Level:</b> {fib_pct:.3f}

<b>Entry Zone:</b> 0.62 - 0.71

⏳ <i>Waiting for liquidity sweep...</i>

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def send_liquidity_sweep(self, wick_ratio: float, is_ideal: bool,
                             direction: str, symbol: str) -> bool:
        """Send liquidity sweep detection notification."""
        ideal_emoji = "⭐" if is_ideal else "✅"

        message = f"""💧 <b>LIQUIDITY SWEEP DETECTED</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction}
<b>Wick/Body Ratio:</b> {wick_ratio:.2f}x {ideal_emoji}
{f"• IDEAL sweep (>= 3x)" if is_ideal else "• Valid sweep (>= 2x)"}

⏳ <i>Waiting for confirmation candle...</i>

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def send_confirmation_candle(self, direction: str, price: float,
                                 body_pct: float, symbol: str) -> bool:
        """Send confirmation candle notification."""
        direction_emoji = "🟢" if direction == "BUY" else "🔴"

        message = f"""🕯️ <b>CONFIRMATION CANDLE</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction_emoji} {direction}
<b>Close:</b> {price:.5f}
<b>Body:</b> {body_pct*100:.1f}% ✅

✅ <i>All conditions met!</i>

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def send_trade_entry(self, setup) -> bool:
        """Send trade entry notification with 3 TP levels."""
        direction_emoji = "🟢" if setup.direction == "BUY" else "🔴"

        # Calculate percentages
        sl_pct = abs(setup.entry_price - setup.sl_price) / setup.entry_price * 100
        tp1_pct = abs(setup.tp1_price - setup.entry_price) / setup.entry_price * 100

        message = f"""🚀 <b>TRADE OPENED [{setup.direction}]</b>

<b>Symbol:</b> {setup.symbol}
<b>Direction:</b> {direction_emoji} {'LONG' if setup.direction == 'BUY' else 'SHORT'}
<b>Entry:</b> {setup.entry_price:.5f}
<b>Lots:</b> {setup.lot_size:.2f}

<b>Stop Loss:</b> {setup.sl_price:.5f} (-{sl_pct:.2f}%)
<b>Buffer:</b> 0.1%

<b>Take Profit Levels:</b>
• TP1: {setup.tp1_price:.5f} (+{tp1_pct:.2f}%) - 33%
• TP2: {setup.tp2_price:.5f} - 33%
• TP3: {setup.tp3_price:.5f} - 34%

<b>R:R:</b> 1:{setup.rr_ratio:.1f}
<b>Confirmed Extremum:</b> {setup.confirmed_extremum_price:.5f}

⏰ {setup.timestamp.strftime('%Y-%m-%d %H:%M:%S')}"""
        return self.send_message(message)

    def send_filter_blocked(self, blocked_by: str, details: str,
                            symbol: str, direction: str) -> bool:
        """Send filter blocked notification."""
        direction_emoji = "🟢" if direction == "BUY" else "🔴"

        message = f"""🚫 <b>TRADE BLOCKED</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction_emoji} {direction}

<b>Blocked by:</b> {blocked_by}
<b>Details:</b> {details}

⏳ <i>Waiting for next opportunity...</i>

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def send_tp_hit(self, symbol: str, direction: str, tp_level: int,
                    price: float, profit: float, remaining_pct: int) -> bool:
        """Send TP hit notification."""
        profit_emoji = "💰" if profit >= 0 else "📉"
        direction_emoji = "🟢" if direction == "BUY" else "🔴"

        if tp_level == 3:
            remaining_text = "🎉 Position fully closed!"
        else:
            remaining_text = f"📊 Remaining: {remaining_pct}%"

        message = f"""{profit_emoji} <b>TP{tp_level} HIT!</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction_emoji} {direction}
<b>TP{tp_level} Price:</b> {price:.5f}
<b>Partial Profit:</b> ${profit:.2f}

{remaining_text}

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def send_sl_hit(self, symbol: str, direction: str,
                    entry: float, sl_price: float, loss: float) -> bool:
        """Send SL hit notification."""
        direction_emoji = "🔴" if direction == "BUY" else "🟢"

        message = f"""🛑 <b>STOP LOSS HIT</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction_emoji} {direction}
<b>Entry:</b> {entry:.5f}
<b>SL:</b> {sl_price:.5f}
<b>Loss:</b> ${loss:.2f}

<i>Position closed.</i>

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def send_daily_summary(self, trades: int, wins: int, losses: int,
                           pnl: float, win_rate: float, symbol: str) -> bool:
        """Send daily summary notification."""
        pnl_emoji = "📈" if pnl >= 0 else "📉"

        message = f"""📊 <b>DAILY SUMMARY</b>

<b>Symbol:</b> {symbol}
<b>Date:</b> {datetime.now().strftime('%Y-%m-%d')}

<b>Trades:</b> {trades}
<b>Wins:</b> {wins} ✅
<b>Losses:</b> {losses} ❌
<b>Win Rate:</b> {win_rate:.1f}%

<b>P/L:</b> ${pnl:.2f}

{pnl_emoji} {'Profitable day!' if pnl >= 0 else 'Better luck tomorrow!'}

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def send_bot_started(self, symbol: str, timeframe: str, config: dict) -> bool:
        """Send bot started notification."""
        filters = config.get('filters', {})
        filter_list = []
        if filters.get('enable_trend', True):
            filter_list.append("✅ Trend")
        if filters.get('enable_volume', True):
            filter_list.append("✅ Volume")
        if filters.get('enable_volatility', True):
            filter_list.append("✅ ATR")
        if filters.get('enable_rr', True):
            filter_list.append("✅ R:R")

        message = f"""🤖 <b>BMS FIBO LIQUIDITY BOT STARTED</b>

<b>Symbol:</b> {symbol}
<b>Timeframe:</b> {timeframe}
<b>Risk:</b> {config.get('risk', {}).get('risk_percent', 1.0)}% per trade
<b>Max Daily Trades:</b> {config.get('risk', {}).get('max_daily_trades', 3)}

<b>Algorithm:</b>
1️⃣ Detect BMS
2️⃣ Track Extremum
3️⃣ Confirm Extremum
4️⃣ Calculate Fibonacci
5️⃣ Wait for Fib Zone
6️⃣ Liquidity Sweep
7️⃣ Confirmation Candle
8️⃣ Execute Trade

<b>Active Filters:</b>
{' | '.join(filter_list)}

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def send_bot_stopped(self, reason: str = "User stopped") -> bool:
        """Send bot stopped notification."""
        message = f"""🛑 <b>BOT STOPPED</b>

<b>Reason:</b> {reason}

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def send_error(self, error_message: str, context: str = "") -> bool:
        """Send error notification."""
        message = f"""⚠️ <b>ERROR ALERT</b>

<b>Message:</b> {error_message}
{f'<b>Context:</b> {context}' if context else ''}

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def send_extremum_timeout(self, symbol: str, candles: int) -> bool:
        """Send extremum tracking timeout notification."""
        message = f"""⏱️ <b>EXTREMUM TRACKING TIMEOUT</b>

<b>Symbol:</b> {symbol}
<b>Candles waited:</b> {candles}

<i>Resetting to IDLE state...</i>

⏰ {self._get_timestamp()}"""
        return self.send_message(message)

    def _get_timestamp(self) -> str:
        """Get formatted timestamp."""
        return datetime.now().strftime('%Y-%m-%d %H:%M:%S')
