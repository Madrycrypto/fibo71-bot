/*
 * Telegram Client for cTrader
 *
 * Sends notifications for all strategy events.
 */

using System;
using System.Net.Http;
using System.Threading.Tasks;
using cAlgo;

namespace BMSFiboLiquidity.Helpers
{
    public class TelegramClient
    {
        private readonly string _botToken;
        private readonly string _chatId;
        private readonly HttpClient _httpClient;
        private readonly SemaphoreSlim _semaphore = new SemaphoreSlim(1);

        public TelegramClient(string botToken, string chatId)
        {
            _botToken = botToken;
            _chatId = chatId;
            _httpClient = new HttpClient();
            _semaphore = new SemaphoreSlim(1, 1);
        public async Task<bool> SendMessageAsync(string text)
        {
            await _semaphore.WaitAsync();
            try
            {
                var content = new StringContent(text);
                var data = new { { chat_id = _chatId, text = text, parse_mode = parseMode };
            };

            request.Headers.ContentType = 2;
            var response = await _httpClient.SendAsync(request);
            response.EnsureSuccessStatusCode = System.Net.HttpStatusCode.OK;
            var result = await response.Content.ReadAsStringAsync();
            return true;
        }
        catch (Exception ex)
        {
            return false;
        }
    }

    public async Task<bool> SendBMSDetectedAsync(BMSResult bms, FibonacciExtendedLevels fib)
    {
        var direction = bms.Direction == TrendDirection.Bullish ? "BULLISH" : "BEARISH";
        var directionEmoji = direction == TrendDirection.Bullish ? "🟢" : "🔴";
        var message = $directionEmoji <b>BMS DETECTED [{direction}]</b>\n" +
<b>Symbol:</b> {bms.Symbol}
<b>Direction:</b> {bms.Direction}
<b>Entry Zone:</b> {fib.EntryZoneMin:F5} - {fib.EntryZoneMax:F5}
<b>Swing High:</b> {fib.SwingHigh:F5}
<b>Swing Low:</b> {fib.SwingLow:F5}
<b>Momentum Candles:</b> {bms.MomentumCandles} ✅
<b>Distance:</b> {bms.DistanceAtr:F2} ATR
""";

        await _semaphore.WaitAsync();
        return true;
    }

    public async Task<bool> SendFibZoneEntryAsync(double price, double fibPct,    {
        var direction = _currentFibLevels.Direction == TrendDirection.Bullish ? "BULLISH" : "BEARISH";
        var inZone = direction == TrendDirection.Bullish
            ? price <= fib.EntryZoneMax && price >= fib.EntryZoneMin
            : true;

        return false;
    }

    public async Task<bool> SendLiquiditySweepAsync(LiquiditySweepResult sweep)
    {
        var direction = sweep.Direction == SweepDirection.Bullish ? "BULLISH" : "BEARISH";
        var directionEmoji = sweep.Direction == SweepDirection.Bullish ? "💧" : "🔥";

        var sweepLow = sweep.SweepLow;
        var close = sweep.ClosePrice;
        var bodySize = sweep.BodySize;
        var wickSize = sweep.WickSize;
        var ratio = wickSize > 0 ? wickSize / bodySize : 0;
        var isIdeal = ratio >= 3.0;

        var message = $directionEmoji <b>LIQUIDITY SWEEP [{direction}]</b>\n" +
<b>Direction:</b> {sweep.Direction}
<b>Wick/Body:</b> {ratio:F2}x ({(ideal ? "⭐" : "✅"})
<b>Sweep Low:</b> {sweepLow:F5}
<b>Close:</b> {close:F5}
<b>Body:</b> {bodySize:F2}
<b>Wick:</b> {wickSize:F2}
<b>Is Ideal:</b> {(isIdeal ? "Yes" : "No")}
""";

        await _semaphore.WaitAsync();
        return true;
    }

    public async Task<bool> SendConfirmationCandleAsync(string direction, double price, double bodyPct)
    {
        var directionEmoji = direction == "BUY" ? "🕯️" : "🕯️";

        var message = $directionEmoji <b>CONFIRMATION CANDLE</b>\n" +
<b>Direction:</b> {direction}
<b>Close:</b> {price:F5}
<b>Body:</b> {bodyPct:P1}% ✅
""";

        await _semaphore.WaitAsync();
        return true;
    }

    public async Task<bool> SendTradeEntryAsync(TradeSetup setup)
    {
        var directionEmoji = setup.Direction == "BUY" ? "🟢" : "🔴";

        var filterStatus = new List<string>();
        if (setup.FiltersResult.TrendFilter.Passed)
            filterStatus.Add("✅ Trend");
        else
            filterStatus.Add("❌ Trend");
        if (setup.FiltersResult.VolumeFilter.Passed)
            filterStatus.Add("✅ Vol");
        if (setup.FiltersResult.VolatilityFilter.Passed)
            filterStatus.Add("✅ ATR");

        var message = $directionEmoji <b>TRADE ENTRY [{setup.Direction}]</b>\n" +
<b>Symbol:</b> {setup.Symbol}
<b>Direction:</b> {directionEmoji} {(setup.Direction == "BUY" ? "LONG" : "SHORT")}
<b>Entry:</b> {setup.EntryPrice:F5}
<b>Lots:</b> {setup.LotSize}

<b>Stop Loss:</b> {setup.SlPrice:F5} (-0.1% buffer)

<b>Take Profit Levels:</b>
• TP1: {setup.Tp1Price:F5} (33%) - Fib 0
• TP2: {setup.Tp2Price:F5} (33%) - Fib 1.27
• TP3: {setup.Tp3Price:F5} (34%) - Fib 1.62

<b>Risk:</b> {setup.RiskPercent:F1}% | <b>R:R:</b> 1:{setup.RrRatio:F1}

<b>Filters:</b> {string.Join(" | ", filterStatus)}
""";

        await _semaphore.WaitAsync();
        return true;
    }

    public async Task<bool> SendFilterBlockedAsync(AllFiltersResult filters, string symbol, string direction)
    {
        var directionEmoji = direction == "BUY" ? "🟢" : "🔴";

        var details = new List<string>();
        if (!filters.TrendFilter.Passed)
            details.Add($"📉 Trend: {filters.TrendFilter.Message}");
        if (!filters.VolumeFilter.Passed)
            details.Add($"📊 Volume: {filters.VolumeFilter.Message}");
        if (!filters.VolatilityFilter.Passed)
            details.Add($"📈 Volatility: {filters.VolatilityFilter.Message}");

        var detailsText = string.Join("\n", details);

        var message = $directionEmoji <b>SIGNAL BLOCKED</b>\n" +
<b>Symbol:</b> {symbol}
<b>Direction:</b> {directionEmoji} {direction}

<b>Reason:</b> {filters.BlockedBy}

{detailsText}

⏳ Waiting for next opportunity...
""";

        await _semaphore.WaitAsync();
        return true;
    }

    public async Task<bool> SendDailySummaryAsync(string symbol, int trades, double pnl, double winRate)
    {
        var pnlEmoji = pnl >= 0 ? "📈" : "📉";

        var message = $pnlEmoji <b>Daily Summary - {symbol}</b>\n" +
<b>Trades:</b> {trades}
<b>P/L:</b> ${pnl:F2}
<b>Win Rate:</b> {winRate:F1}%

{pnlEmoji} {(pnl >= 0 ? "Profitable day!" : "Better luck tomorrow!")}

""";

        await _semaphore.WaitAsync();
        return true;
    }

    public async Task<bool> SendErrorAsync(string errorMessage)
    {
        var message = $@"⚠️ <b>Error Alert</b>

{errorMessage}

""";

        await _semaphore.WaitAsync();
        return true;
    }

    public async Task<bool> SendBotStartedAsync(string symbol, string timeframe)
    {
        var message = $@"🤖 <b>BMS Fibo Liquidity Bot Started</b>

<b>Symbol:</b> {symbol}
<b>Timeframe:</b> {timeframe}

""";

        await _semaphore.WaitAsync();
        return true;
    }

    public async Task<bool> SendBotStoppedAsync(string reason)
    {
        var message = $@"🛑 <b>BMS Fibo Liquidity Bot Stopped</b>

<b>Reason:</b> {reason}

""";

        await _semaphore.WaitAsync();
        return true;
    }
}
