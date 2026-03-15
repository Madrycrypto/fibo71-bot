//+------------------------------------------------------------------+
//|                                          Telegram_Messages.mqh      |
//|                                    Fibo 71 - Telegram Message Templates   |
//+------------------------------------------------------------------+
#property copyright "Fibo71 Bot"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| TELEGRAM MESSAGE TEMPLATES                                        |
//+------------------------------------------------------------------+

// Emoji sets
string EMOJI_BUY = "🟢";
string EMOJI_SELL = "🔴";
string EMOJI_TP = "✅";
string EMOJI_SL = "❌";
string EMOJI_ENTRY = "📍";
string EMOJI_WARNING = "⚠️";
string EMOJI_INFO = "ℹ️";
string EMOJI_MONEY = "💰";
string EMOJI_CHART = "📊";
string EMOJI_CLOCK = "⏰";
string EMOJI_TARGET = "🎯";
string EMOJI_STOP = "🛑";
string EMOJI_ROCKET = "🚀";
string EMOJI_PENCIL = "📝";
string EMOJI_STAR = "⭐";

//+------------------------------------------------------------------+
//| FORMAT HELPERS                                                     |
//+------------------------------------------------------------------+

string FormatPips(double pips)
{
    if(pips >= 1000)
        return DoubleToString(pips, 0);
    else if(pips >= 100)
        return DoubleToString(pips, 1);
    else
        return DoubleToString(pips, 2);
}

string FormatPrice(double price, int digits)
{
    return DoubleToString(price, digits);
}

string FormatTime(datetime time)
{
    return TimeToString(time, TIME_DATE|TIME_MINUTES);
}

string FormatRR(double rr)
{
    if(rr >= 10)
        return DoubleToString(rr, 0) + ":1";
    else
        return DoubleToString(rr, 1) + ":1";
}

string FormatPercent(double pct)
{
    return DoubleToString(pct, 1) + "%";
}

//+------------------------------------------------------------------+
//| MESSAGE TEMPLATES                                                 |
//+------------------------------------------------------------------+

// Bot Started
string MsgBotStarted(string symbol, string timeframe, double riskPct,
                    double fibMin, double fibMax, double balance)
{
    string msg = EMOJI_ROCKET + " <b>FIBO 71 BOT STARTED</b>\n\n";
    msg += EMOJI_CHART + " <b>Symbol:</b> <code>" + symbol + "</code>\n";
    msg += "⏱ <b>Timeframe:</b> " + timeframe + "\n";
    msg += EMOJI_MONEY + " <b>Risk:</b> " + FormatPercent(riskPct) + "\n";
    msg += "📍 <b>Entry Zone:</b> " + DoubleToString(fibMin * 100, 0) + "% - " + DoubleToString(fibMax * 100, 0) + "%\n";
    msg += EMOJI_INFO + " <b>Balance:</b> $" + DoubleToString(balance, 2) + "\n";
    msg += "\n" + EMOJI_CLOCK + " " + FormatTime(TimeCurrent());
    return msg;
}

// Bot Stopped
string MsgBotStopped(string reason)
{
    string msg = EMOJI_STOP + " <b>FIBO 71 BOT STOPPED</b>\n\n";
    msg += EMOJI_PENCIL + " <b>Reason:</b> " + reason + "\n";
    msg += "\n" + EMOJI_CLOCK + " " + FormatTime(TimeCurrent());
    return msg;
}

// Daily Summary Start
string MsgDailyStart(int date, double balance, int tradesYesterday, double pipsYesterday)
{
    string msg = "🌅 <b>NEW TRADING DAY</b>\n\n";
    msg += EMOJI_MONEY + " <b>Balance:</b> $" + DoubleToString(balance, 2) + "\n";
    msg += "📊 <b>Yesterday:</b> " + IntegerToString(tradesYesterday) + " trades";
    if(pipsYesterday != 0)
        msg += " (" + (pipsYesterday >= 0 ? "+" : "") + FormatPips(pipsYesterday) + " pips)";
    msg += "\n";
    msg += "\n" + EMOJI_STAR + " Ready for new opportunities!";
    return msg;
}

// BOS Detected - SETUP FORMED
string MsgBOSDetected(string symbol, string direction,
                     double swingHigh, double swingLow, double fib71, double fib79,
                     double tp, double sl, double rr, bool hasImbalance, bool hasLiqSweep)
{
    string dirEmoji = (direction == "SELL") ? EMOJI_SELL : EMOJI_BUY;

    string msg = dirEmoji + " <b>BOS DETECTED - SETUP READY</b>\n\n";
    msg += EMOJI_CHART + " <b>" + symbol + "</b> | <b>" + direction + "</b>\n\n";

    msg += "📐 <b>Fibonacci Levels:</b>\n";
    msg += "├─ TP (0%): <code>" + FormatPrice(tp, 5) + "</code>\n";
    msg += "├─ Entry: <code>" + FormatPrice(fib71, 5) + " - " + FormatPrice(fib79, 5) + "</code>\n";
    msg += "└─ SL (100%): <code>" + FormatPrice(sl, 5) + "</code>\n\n";

    msg += "📊 <b>Statistics:</b>\n";
    msg += "├─ Range: " + FormatPips(MathAbs(swingHigh - swingLow) / 0.0001) + " pips\n";
    msg += "├─ R:R: " + FormatRR(rr) + "\n";
    msg += "├─ Imbalance: " + (hasImbalance ? "✅" : "❌") + "\n";
    msg += "└─ Liq Sweep: " + (hasLiqSweep ? "✅" : "❌") + "\n\n";

    msg += EMOJI_CLOCK + " " + FormatTime(TimeCurrent());
    msg += "\n\n🎯 <b>Waiting for entry...</b>";
    return msg;
}

// Order Placed - PENDING
string MsgOrderPlaced(string symbol, string direction, double lots,
                     double entry, double sl, double tp, double rr)
{
    string dirEmoji = (direction == "SELL") ? EMOJI_SELL : EMOJI_BUY;
    string orderType = (direction == "SELL") ? "SELL LIMIT" : "BUY LIMIT";

    string msg = EMOJI_ENTRY + " <b>ORDER PLACED</b>\n\n";
    msg += dirEmoji + " <b>" + orderType + "</b>\n\n";

    msg += "📊 <b>" + symbol + "</b>\n";
    msg += "├─ Lots: <code>" + DoubleToString(lots, 2) + "</code>\n";
    msg += "├─ Entry: <code>" + FormatPrice(entry, 5) + "</code>\n";
    msg += "├─ SL: <code>" + FormatPrice(sl, 5) + "</code>\n";
    msg += "├─ TP: <code>" + FormatPrice(tp, 5) + "</code>\n";
    msg += "└─ R:R: <code>" + FormatRR(rr) + "</code>\n\n";

    msg += EMOJI_CLOCK + " " + FormatTime(TimeCurrent());
    msg += "\n\n⏳ <b>Pending execution...</b>";
    return msg;
}

// Position Opened - ORDER FILLED
string MsgPositionOpened(string symbol, string direction, double lots,
                        double entry, double sl, double tp, double rr)
{
    string dirEmoji = (direction == "SELL") ? EMOJI_SELL : EMOJI_BUY;

    string msg = "✨ <b>POSITION OPENED</b>\n\n";
    msg += dirEmoji + " <b>" + direction + " " + DoubleToString(lots, 2) + " lots</b>\n\n";

    msg += "📊 <b>" + symbol + "</b>\n";
    msg += "├─ Entry: <code>" + FormatPrice(entry, 5) + "</code>\n";
    msg += "├─ SL: <code>" + FormatPrice(sl, 5) + "</code> (" + FormatPips(MathAbs(entry - sl) / 0.0001) + " pips)\n";
    msg += "├─ TP: <code>" + FormatPrice(tp, 5) + "</code> (" + FormatPips(MathAbs(entry - tp) / 0.0001) + " pips)\n";
    msg += "└─ R:R: <code>" + FormatRR(rr) + "</code>\n\n";

    msg += EMOJI_CLOCK + " " + FormatTime(TimeCurrent());
    msg += "\n\n🎯 <b>Target:</b> " + FormatPrice(tp, 5);
    return msg;
}

// TP Hit - WIN
string MsgTPHit(string symbol, string direction, double lots,
                double entry, double exitPrice, double pips, double pnl, double rr)
{
    string dirEmoji = (direction == "SELL") ? EMOJI_SELL : EMOJI_BUY;

    string msg = EMOJI_TP + " <b>TAKE PROFIT HIT!</b>\n\n";
    msg += dirEmoji + " <b>" + direction + " " + DoubleToString(lots, 2) + " lots</b>\n\n";

    msg += "📊 <b>" + symbol + "</b>\n";
    msg += "├─ Entry: <code>" + FormatPrice(entry, 5) + "</code>\n";
    msg += "└─ Exit: <code>" + FormatPrice(exitPrice, 5) + "</code>\n\n";

    msg += "💰 <b>RESULT:</b>\n";
    msg += "├─ Pips: <b>+" + FormatPips(pips) + "</b>\n";
    msg += "├─ P/L: <b>$" + DoubleToString(pnl, 2) + "</b>\n";
    msg += "└─ R:R achieved: <b>" + FormatRR(rr) + "</b>\n\n";

    msg += EMOJI_CLOCK + " " + FormatTime(TimeCurrent());
    return msg;
}

// SL Hit - LOSS
string MsgSLHit(string symbol, string direction, double lots,
                double entry, double exitPrice, double pips, double pnl)
{
    string dirEmoji = (direction == "SELL") ? EMOJI_SELL : EMOJI_BUY;

    string msg = EMOJI_SL + " <b>STOP LOSS HIT</b>\n\n";
    msg += dirEmoji + " <b>" + direction + " " + DoubleToString(lots, 2) + " lots</b>\n\n";

    msg += "📊 <b>" + symbol + "</b>\n";
    msg += "├─ Entry: <code>" + FormatPrice(entry, 5) + "</code>\n";
    msg += "└─ Exit: <code>" + FormatPrice(exitPrice, 5) + "</code>\n\n";

    msg += "📉 <b>RESULT:</b>\n";
    msg += "├─ Pips: <b>" + FormatPips(pips) + "</b>\n";
    msg += "└─ P/L: <b>$" + DoubleToString(pnl, 2) + "</b>\n\n";

    msg += EMOJI_CLOCK + " " + FormatTime(TimeCurrent());
    msg += "\n\n💪 <b>Next setup coming...</b>";
    return msg;
}

// Daily Summary
string MsgDailySummary(int totalTrades, int wins, int losses,
                       double totalPips, double totalPnl, double winRate,
                       double balance, double dailyChange)
{
    string trend = (totalPips >= 0) ? "📈" : "📉";
    string changeEmoji = (dailyChange >= 0) ? "🟢" : "🔴";

    string msg = "📊 <b>DAILY SUMMARY</b>\n\n";

    msg += "🎯 <b>Trades:</b> " + IntegerToString(totalTrades) + "\n";
    msg += "├─ " + EMOJI_TP + " Wins: " + IntegerToString(wins) + "\n";
    msg += "├─ " + EMOJI_SL + " Losses: " + IntegerToString(losses) + "\n";
    msg += "└─ WR: " + FormatPercent(winRate) + "\n\n";

    msg += trend + " <b>Performance:</b>\n";
    msg += "├─ Pips: <b>" + (totalPips >= 0 ? "+" : "") + FormatPips(totalPips) + "</b>\n";
    msg += "└─ P/L: <b>$" + DoubleToString(totalPnl, 2) + "</b>\n\n";

    msg += EMOJI_MONEY + " <b>Balance:</b> $" + DoubleToString(balance, 2);
    msg += " (" + changeEmoji + " " + (dailyChange >= 0 ? "+" : "") + FormatPercent(dailyChange) + ")\n\n";

    msg += EMOJI_CLOCK + " " + FormatTime(TimeCurrent());
    return msg;
}

// Warning - Risk Limit
string MsgRiskWarning(string warningType, string details)
{
    string msg = EMOJI_WARNING + " <b>RISK WARNING</b>\n\n";
    msg += "⚠️ <b>" + warningType + "</b>\n";
    msg += details + "\n\n";
    msg += EMOJI_CLOCK + " " + FormatTime(TimeCurrent());
    return msg;
}

// Setup Cancelled - Entry zone expired
string MsgSetupCancelled(string symbol, string direction, string reason)
{
    string dirEmoji = (direction == "SELL") ? EMOJI_SELL : EMOJI_BUY;

    string msg = "❌ <b>SETUP CANCELLED</b>\n\n";
    msg += dirEmoji + " " + symbol + " " + direction + "\n";
    msg += "📝 Reason: " + reason + "\n\n";
    msg += EMOJI_CLOCK + " " + FormatTime(TimeCurrent());
    return msg;
}

// Equity Milestone
string MsgEquityMilestone(double balance, double startingBalance, double pctGain, int days)
{
    string msg = "🏆 <b>EQUITY MILESTONE!</b>\n\n";
    msg += EMOJI_MONEY + " <b>Balance:</b> $" + DoubleToString(balance, 2) + "\n";
    msg += "📈 <b>Gain:</b> +" + FormatPercent(pctGain) + "\n";
    msg += "📅 <b>Days:</b> " + IntegerToString(days) + "\n\n";
    msg += EMOJI_STAR + " Great progress!";
    return msg;
}

//+------------------------------------------------------------------+
//| EXAMPLE USAGE IN OnTick()                                          |
//+------------------------------------------------------------------+
/*
Example usage in your EA:

// On Bot Start:
string msg = MsgBotStarted(Symbol, EnumToString(Timeframe), RiskPercent,
                          FibEntryMin, FibEntryMax, AccountInfoDouble(ACCOUNT_BALANCE));
SendTelegram(msg);

// On BOS Detection:
string msg = MsgBOSDetected(Symbol, direction, swingHigh, swingLow,
                           fib71, fib79, tp, sl, rr, hasImbalance, hasLiqSweep);
SendTelegram(msg);

// On TP Hit:
string msg = MsgTPHit(Symbol, positionDirection, positionVolume,
                     positionOpenPrice, positionClosePrice, pips, pnl, rr);
SendTelegram(msg);

// On SL Hit:
string msg = MsgSLHit(Symbol, positionDirection, positionVolume,
                     positionOpenPrice, positionClosePrice, pips, pnl);
SendTelegram(msg);
*/
