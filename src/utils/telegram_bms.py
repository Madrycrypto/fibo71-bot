"""
Telegram Notification Utility for BMS Fibo Liquidity Bot

Enhanced notification system with:
- BMS detection alerts
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

    Sends formatted messages for:
    - BMS detection
    - Fibonacci zone entry
    - Liquidity sweep detection
    - Confirmation candle
    - Trade entry with 3 TP levels
    - Filter blocked
    - TP hit notifications
    - Daily summary
    - Errors
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

    def send_bms_detected(self, bms_result, fib_levels, symbol: str) -> bool:
        """
        Send BMS detection notification.

        Args:
            bms_result: BMSResult object
            fib_levels: FibonacciExtendedLevels object
            symbol: Trading symbol

        Returns:
            True if successful
        """
        direction = "BULLISH" if bms_result.direction.value == 1 else "BEARISH"
        direction_emoji = "🟢" if direction == "BULLISH" else "🔴"
        trade_dir = "LONG" if direction == "BULLISH" else "SHORT"

        swing_high = fib_levels.swing_high
        swing_low = fib_levels.swing_low

        message = f"""
{direction_emoji} <b>BMS DETECTED [{direction}]</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {trade_dir}
<b>Momentum Candles:</b> {bms_result.momentum_candles} ✅
<b>Distance:</b> {bms_result.distance_atr:.2f} ATR ✅

<b>Swing Points:</b>
• Swing High: {swing_high:.5f}
• Swing Low: {swing_low:.5f}

<b>Fibonacci Entry Zone:</b>
• 0.62: {fib_levels.entry_zone_min:.5f}
• 0.71: {fib_levels.entry_zone_max:.5f}

⏳ Waiting for retracement...

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def send_fib_zone_entry(self, price: float, fib_pct: float,
                            fib_levels, symbol: str) -> bool:
        """
        Send Fibonacci zone entry notification.

        Args:
            price: Current price
            fib_pct: Fibonacci percentage
            fib_levels: FibonacciExtendedLevels object
            symbol: Trading symbol

        Returns:
            True if successful
        """
        message = f"""
📍 <b>PRICE IN FIB ZONE</b>

<b>Symbol:</b> {symbol}
<b>Current Price:</b> {price:.5f}
<b>Fib Level:</b> {fib_pct:.3f} (0.{int(fib_pct*100)})

<b>Entry Zone:</b> 0.62 - 0.71
⏳ Waiting for liquidity sweep...

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def send_liquidity_sweep(self, sweep_result, symbol: str) -> bool:
        """
        Send liquidity sweep detection notification.

        Args:
            sweep_result: LiquiditySweepResult object
            symbol: Trading symbol

        Returns:
            True if successful
        """
        direction = "BULLISH" if sweep_result.direction.value == 1 else "BEARISH"
        ideal_emoji = "⭐" if sweep_result.is_ideal else "✅"

        message = f"""
💧 <b>LIQUIDITY SWEEP DETECTED</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction}

<b>Sweep Details:</b>
• Sweep Low: {sweep_result.sweep_low:.5f}
• Close: {sweep_result.close_price:.5f}
• Wick/Body Ratio: {sweep_result.wick_to_body_ratio:.2f}x {ideal_emoji}
{"• IDEAL sweep (>= 3x)" if sweep_result.is_ideal else "• Valid sweep (>= 2x)"}

⏳ Waiting for confirmation candle...

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def send_confirmation_candle(self, direction: str, price: float,
                                 body_pct: float, symbol: str) -> bool:
        """
        Send confirmation candle notification.

        Args:
            direction: Trade direction
            price: Candle close price
            body_pct: Body percentage
            symbol: Trading symbol

        Returns:
            True if successful
        """
        direction_emoji = "🟢" if direction == "BUY" else "🔴"

        message = f"""
🕯️ <b>CONFIRMATION CANDLE</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction_emoji} {direction}
<b>Close:</b> {price:.5f}
<b>Body:</b> {body_pct*100:.1f}% ✅

✅ All conditions met!

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def send_trade_entry(self, setup) -> bool:
        """
        Send trade entry notification with 3 TP levels.

        Args:
            setup: TradeSetup object

        Returns:
            True if successful
        """
        direction_emoji = "🟢" if setup.direction == "BUY" else "🔴"

        # Filter status
        filters = setup.filters_result
        filter_status = []
        filter_status.append(f"{'✅' if filters.trend_filter.passed else '❌'} Trend")
        filter_status.append(f"{'✅' if filters.volume_filter.passed else '❌'} Vol")
        filter_status.append(f"{'✅' if filters.volatility_filter.passed else '❌'} ATR")

        message = f"""
🚀 <b>TRADE ENTRY [{setup.direction}]</b>

<b>Symbol:</b> {setup.symbol}
<b>Direction:</b> {direction_emoji} {'LONG' if setup.direction == 'BUY' else 'SHORT'}
<b>Entry:</b> {setup.entry_price:.5f}
<b>Lots:</b> {setup.lot_size}

<b>Stop Loss:</b> {setup.sl_price:.5f} (-0.1% buffer)

<b>Take Profit Levels:</b>
• TP1: {setup.tp1_price:.5f} (33%) - Prev High/Low
• TP2: {setup.tp2_price:.5f} (33%) - Fib 1.27
• TP3: {setup.tp3_price:.5f} (34%) - Fib 1.62

<b>Risk:</b> {1.0:.1f}% | <b>R:R:</b> 1:{setup.rr_ratio:.1f}

<b>Filters:</b> {' | '.join(filter_status)}

⏰ {setup.timestamp.strftime('%Y-%m-%d %H:%M:%S')}
"""
        return self.send_message(message)

    def send_filter_blocked(self, filters_result, symbol: str,
                            direction: str) -> bool:
        """
        Send filter blocked notification.

        Args:
            filters_result: AllFiltersResult object
            symbol: Trading symbol
            direction: Trade direction

        Returns:
            True if successful
        """
        direction_emoji = "🟢" if direction == "BUY" else "🔴"

        # Build filter details
        details = []
        if not filters_result.trend_filter.passed:
            details.append(f"📉 Trend: {filters_result.trend_filter.message}")
        if not filters_result.volume_filter.passed:
            details.append(f"📊 Volume: {filters_result.volume_filter.message}")
        if not filters_result.volatility_filter.passed:
            details.append(f"📈 Volatility: {filters_result.volatility_filter.message}")

        details_text = "\n".join(details)

        message = f"""
🚫 <b>SIGNAL BLOCKED</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction_emoji} {direction}

<b>Reason:</b> {filters_result.blocked_by}

{details_text}

⏳ Waiting for next opportunity...

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def send_tp_hit(self, symbol: str, direction: str, tp_level: int,
                    price: float, profit: float, remaining_pct: int) -> bool:
        """
        Send TP hit notification.

        Args:
            symbol: Trading symbol
            direction: Trade direction
            tp_level: Which TP was hit (1, 2, or 3)
            price: TP price
            profit: Profit amount
            remaining_pct: Remaining position percentage

        Returns:
            True if successful
        """
        profit_emoji = "💰" if profit >= 0 else "📉"
        direction_emoji = "🟢" if direction == "BUY" else "🔴"

        if tp_level == 3:
            remaining_text = "Position fully closed!"
        else:
            remaining_text = f"Remaining: {remaining_pct}%"

        message = f"""
{profit_emoji} <b>TP{tp_level} HIT!</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction_emoji} {direction}
<b>TP{tp_level} Price:</b> {price:.5f}
<b>Partial Profit:</b> ${profit:.2f}

{remaining_text}

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def send_sl_hit(self, symbol: str, direction: str,
                    entry: float, sl_price: float, loss: float) -> bool:
        """
        Send SL hit notification.

        Args:
            symbol: Trading symbol
            direction: Trade direction
            entry: Entry price
            sl_price: SL price
            loss: Loss amount

        Returns:
            True if successful
        """
        direction_emoji = "🔴" if direction == "BUY" else "🟢"

        message = f"""
⛔ <b>STOP LOSS HIT</b>

<b>Symbol:</b> {symbol}
<b>Direction:</b> {direction_emoji} {direction}
<b>Entry:</b> {entry:.5f}
<b>SL:</b> {sl_price:.5f}
<b>Loss:</b> ${loss:.2f}

Position closed.

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def send_position_closed(self, symbol: str, direction: str,
                             entry: float, exit_price: float,
                             profit: float, reason: str = "Manual") -> bool:
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
                           win_rate: float, symbol: str) -> bool:
        """
        Send daily summary notification.

        Args:
            trades: Number of trades
            pnl: Total P/L
            win_rate: Win rate percentage
            symbol: Trading symbol

        Returns:
            True if successful
        """
        pnl_emoji = "📈" if pnl >= 0 else "📉"

        message = f"""
📊 <b>Daily Summary - {symbol}</b>

<b>Trades:</b> {trades}
<b>P/L:</b> ${pnl:.2f}
<b>Win Rate:</b> {win_rate:.1f}%

{pnl_emoji} {'Profitable day!' if pnl >= 0 else 'Better luck tomorrow!'}

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def send_bot_started(self, symbol: str, timeframe: str, config: dict) -> bool:
        """
        Send bot started notification.

        Args:
            symbol: Trading symbol
            timeframe: Chart timeframe
            config: Configuration dictionary

        Returns:
            True if successful
        """
        filters = config.get('filters', {})
        filter_text = []
        if filters.get('trend', True):
            filter_text.append("✅ Trend")
        if filters.get('volume', True):
            filter_text.append("✅ Volume")
        if filters.get('volatility', True):
            filter_text.append("✅ Volatility")
        if filters.get('rr', True):
            filter_text.append("✅ R:R")

        message = f"""
🤖 <b>BMS Fibo Liquidity Bot Started</b>

<b>Symbol:</b> {symbol}
<b>Timeframe:</b> {timeframe}
<b>Risk:</b> {config.get('risk_percent', 1.0)}% per trade
<b>Max Daily Trades:</b> {config.get('max_daily_trades', 3)}

<b>Active Filters:</b>
{' | '.join(filter_text)}

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def send_bot_stopped(self, reason: str = "User stopped") -> bool:
        """Send bot stopped notification."""
        message = f"""
🛑 <b>BMS Fibo Liquidity Bot Stopped</b>

<b>Reason:</b> {reason}

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

    def send_risk_warning(self, symbol: str, rr_ratio: float,
                          min_rr: float) -> bool:
        """
        Send R:R warning notification.

        Args:
            symbol: Trading symbol
            rr_ratio: Current R:R ratio
            min_rr: Minimum required R:R

        Returns:
            True if successful
        """
        message = f"""
⚠️ <b>Risk Warning</b>

<b>Symbol:</b> {symbol}
<b>Current R:R:</b> 1:{rr_ratio:.1f}
<b>Minimum R:R:</b> 1:{min_rr:.1f}

Trade setup does not meet minimum R:R requirement.

⏰ {self._get_timestamp()}
"""
        return self.send_message(message)

    def _get_timestamp(self) -> str:
        """Get formatted timestamp."""
        return datetime.now().strftime('%Y-%m-%d %H:%M:%S')
