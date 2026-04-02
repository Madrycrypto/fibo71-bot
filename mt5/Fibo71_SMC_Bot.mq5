//+------------------------------------------------------------------+
//|                                          Fibo71_SMC_Bot.mq5       |
//|                                    BOS Detection + Fibonacci      |
//|                                    Standalone (no external indi)  |
//+------------------------------------------------------------------+
#property copyright "Fibo71 Bot - Standalone"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

// Basic Settings
input string   Section1 = "════════ Basic Settings ════════";
input string   TradeSymbol = "";                      // Symbol (empty = chart symbol)
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;          // Trading Timeframe
input int      MagicNumber = 710071;                  // Magic Number

// BOS Detection
input string   Section2 = "════════ BOS Detection ════════";
input int      SwingLookback = 2;                     // Candles on each side for swing
input int      BOSLookback = 100;                     // Max lookback for swing points

// Fibonacci Settings
input string   Section3 = "════════ Fibonacci Settings ════════";
input double   FibEntryMin = 0.71;                    // Fib Entry Min (71%)
input double   FibEntryMax = 0.79;                    // Fib Entry Max (79%)

// Risk Management
input string   Section4 = "════════ Risk Management ════════";
input double   RiskPercent = 1.0;                     // Risk per trade (%)
input int      MaxDailyTrades = 3;                    // Max trades per day

// Telegram
input string   Section5 = "════════ Telegram ════════";
input bool     EnableTelegram = false;                // Enable Telegram
input string   TelegramBotToken = "";                 // Bot Token
input string   TelegramChatID = "";                   // Chat ID

// Display
input string   Section6 = "════════ Display ════════";
input int      LineExtensionBars = 50;                // How far lines extend (bars)
input color    ColorTP = clrLime;                     // TP (0%) line color
input color    ColorSL = clrRed;                      // SL (100%) line color
input color    ColorEntry = clrBlue;                  // Entry zone color
input color    ColorBullish = clrGreen;               // Bullish setup color
input color    ColorBearish = clrRed;                 // Bearish setup color
input int      LineWidthMain = 2;                     // TP/SL line width
input int      LineWidthZone = 1;                     // Entry zone line width

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;

// Working symbol
string g_symbol = "";

// Swing points structure
struct SwingPoint {
    double price;
    int    barIdx;
    bool   valid;
};

SwingPoint lastSwingHigh;
SwingPoint lastSwingLow;

// Fibonacci levels
double fib0 = 0;      // TP (0%)
double fib71 = 0;     // Entry zone start
double fib79 = 0;     // Entry zone end
double fib100 = 0;    // SL (100%)

// State
bool setupActive = false;
bool isBullishSetup = false;
int dailyTrades = 0;
datetime lastTradeDate = 0;
ulong pendingTicket = 0;
int bosBarIdx = 0;

// Chart prefix
string prefix = "Fibo71_";

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    g_symbol = (TradeSymbol == "") ? _Symbol : TradeSymbol;

    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(20);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    if(!symbolInfo.Name(g_symbol))
    {
        Print("❌ Symbol not found: ", g_symbol);
        return INIT_FAILED;
    }

    Print("══════════════════════════════════════════════════");
    Print("🤖 Fibo 71 Bot - Standalone v2.00");
    Print("══════════════════════════════════════════════════");
    Print("Symbol: ", g_symbol, " | Timeframe: ", EnumToString(Timeframe));
    Print("Swing Lookback: ", SwingLookback, " | BOS Lookback: ", BOSLookback);
    Print("Entry Zone: ", FibEntryMin * 100, "% - ", FibEntryMax * 100, "%");
    Print("Line Extension: ", LineExtensionBars, " bars");
    Print("══════════════════════════════════════════════════");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, prefix);
    Print("🛑 Fibo 71 Bot stopped");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!symbolInfo.RefreshRates())
        return;

    // Check for setup invalidation
    if(setupActive)
    {
        if(CheckSetupInvalidation())
        {
            CancelSetup();
            return;
        }

        // Check entry
        CheckEntry();
    }

    // Check for new candle
    static datetime lastCandleTime = 0;
    bool isNewCandle = (iTime(g_symbol, Timeframe, 0) != lastCandleTime);

    if(isNewCandle)
    {
        lastCandleTime = iTime(g_symbol, Timeframe, 0);

        // Reset daily counter
        if(TimeCurrent() - lastTradeDate > 86400)
        {
            dailyTrades = 0;
            lastTradeDate = TimeCurrent();
        }

        // Analyze
        FindSwingPoints();
        DetectBOS();
    }

    // Check pending order
    if(pendingTicket > 0)
        CheckPendingOrder();
}

//+------------------------------------------------------------------+
//| Find Swing Points                                                 |
//+------------------------------------------------------------------+
void FindSwingPoints()
{
    lastSwingHigh.valid = false;
    lastSwingLow.valid = false;

    // Find most recent swing high
    for(int i = SwingLookback; i < BOSLookback - SwingLookback; i++)
    {
        if(IsSwingHigh(i))
        {
            lastSwingHigh.price = iHigh(g_symbol, Timeframe, i);
            lastSwingHigh.barIdx = i;
            lastSwingHigh.valid = true;
            break;
        }
    }

    // Find most recent swing low
    for(int i = SwingLookback; i < BOSLookback - SwingLookback; i++)
    {
        if(IsSwingLow(i))
        {
            lastSwingLow.price = iLow(g_symbol, Timeframe, i);
            lastSwingLow.barIdx = i;
            lastSwingLow.valid = true;
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Is Swing High/Low                                                 |
//+------------------------------------------------------------------+
bool IsSwingHigh(int bar)
{
    double h = iHigh(g_symbol, Timeframe, bar);
    for(int j = 1; j <= SwingLookback; j++)
    {
        if(iHigh(g_symbol, Timeframe, bar + j) >= h) return false;
        if(iHigh(g_symbol, Timeframe, bar - j) >= h) return false;
    }
    return true;
}

bool IsSwingLow(int bar)
{
    double l = iLow(g_symbol, Timeframe, bar);
    for(int j = 1; j <= SwingLookback; j++)
    {
        if(iLow(g_symbol, Timeframe, bar + j) <= l) return false;
        if(iLow(g_symbol, Timeframe, bar - j) <= l) return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Detect BOS                                                        |
//+------------------------------------------------------------------+
void DetectBOS()
{
    if(setupActive) return;
    if(!lastSwingHigh.valid || !lastSwingLow.valid) return;

    double close = iClose(g_symbol, Timeframe, 1);

    // BULLISH BOS: Swing LOW is more recent, price breaks above swing HIGH
    if(lastSwingLow.barIdx < lastSwingHigh.barIdx)
    {
        if(close > lastSwingHigh.price)
        {
            Print("🟢 BULLISH BOS: Close ", close, " > Swing High ", lastSwingHigh.price);
            ActivateBullishSetup(lastSwingHigh.price, lastSwingLow.price);
        }
    }

    // BEARISH BOS: Swing HIGH is more recent, price breaks below swing LOW
    if(lastSwingHigh.barIdx < lastSwingLow.barIdx)
    {
        if(close < lastSwingLow.price)
        {
            Print("🔴 BEARISH BOS: Close ", close, " < Swing Low ", lastSwingLow.price);
            ActivateBearishSetup(lastSwingHigh.price, lastSwingLow.price);
        }
    }
}

//+------------------------------------------------------------------+
//| Activate Bullish/Bearish Setup                                    |
//+------------------------------------------------------------------+
void ActivateBullishSetup(double swingH, double swingL)
{
    if(setupActive) return;

    double range = swingH - swingL;
    fib0 = swingH;
    fib100 = swingL;
    fib71 = swingH - range * FibEntryMin;
    fib79 = swingH - range * FibEntryMax;

    isBullishSetup = true;
    setupActive = true;
    bosBarIdx = 1;

    DrawFibonacciLines();
    PrintSetup("BULLISH");

    if(EnableTelegram)
        SendBOSNotification();
}

void ActivateBearishSetup(double swingH, double swingL)
{
    if(setupActive) return;

    double range = swingH - swingL;
    fib0 = swingL;
    fib100 = swingH;
    fib71 = swingL + range * FibEntryMin;
    fib79 = swingL + range * FibEntryMax;

    isBullishSetup = false;
    setupActive = true;
    bosBarIdx = 1;

    DrawFibonacciLines();
    PrintSetup("BEARISH");

    if(EnableTelegram)
        SendBOSNotification();
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Lines                                              |
//+------------------------------------------------------------------+
void DrawFibonacciLines()
{
    int bars = iBars(g_symbol, Timeframe);
    if(bars < bosBarIdx + 1)
        return;

    ObjectsDeleteAll(0, prefix);

    datetime bosTime = iTime(g_symbol, Timeframe, bosBarIdx);
    datetime endTime = bosTime + PeriodSeconds(Timeframe) * LineExtensionBars;

    color setupColor = isBullishSetup ? ColorBullish : ColorBearish;

    // TP line (0%)
    TrendLine(prefix + "TP", bosTime, fib0, endTime, fib0, ColorTP, LineWidthMain, "0% TP");

    // Entry zone
    TrendLine(prefix + "Entry71", bosTime, fib71, endTime, fib71, ColorEntry, LineWidthZone, "71%");
    TrendLine(prefix + "Entry79", bosTime, fib79, endTime, fib79, ColorEntry, LineWidthZone, "79%");

    // Zone rectangle
    RectCreate(prefix + "Zone", bosTime, fib71, endTime, fib79, setupColor);

    // SL line (100%)
    TrendLine(prefix + "SL", bosTime, fib100, endTime, fib100, ColorSL, LineWidthMain, "100% SL");

    // Swing arrows
    if(lastSwingHigh.valid)
        Arrow(prefix + "SH", lastSwingHigh.barIdx, lastSwingHigh.price, clrRed, 233);
    if(lastSwingLow.valid)
        Arrow(prefix + "SL", lastSwingLow.barIdx, lastSwingLow.price, clrGreen, 234);

    // BOS label
    string bosText = isBullishSetup ? "🟢 BULLISH" : "🔴 BEARISH";
    double bosPrice = isBullishSetup ? lastSwingLow.price : lastSwingHigh.price;
    Label(prefix + "BOS", bosTime, bosPrice, bosText, setupColor);

    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Drawing Helpers                                                   |
//+------------------------------------------------------------------+
void TrendLine(string name, datetime t1, double p1, datetime t2, double p2, color col, int width, string label)
{
    ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetString(0, name, OBJPROP_TEXT, label);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

void RectCreate(string name, datetime t1, double p1, datetime t2, double p2, color col)
{
    ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

void Label(string name, datetime t, double p, string text, color col)
{
    ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
}

void Arrow(string name, int bar, double price, color col, int code)
{
    datetime t = iTime(g_symbol, Timeframe, bar);
    ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
    ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

//+------------------------------------------------------------------+
//| Check Setup Invalidation                                          |
//+------------------------------------------------------------------+
bool CheckSetupInvalidation()
{
    if(fib0 == 0 || fib100 == 0) return false;

    double bid = symbolInfo.Bid();
    double ask = symbolInfo.Ask();

    double higherEntry = MathMax(fib71, fib79);
    double lowerEntry = MathMin(fib71, fib79);
    bool inZone = (bid >= lowerEntry && bid <= higherEntry);

    if(inZone) return false;

    if(isBullishSetup)
    {
        if(ask >= fib0) return true;
        if(bid <= fib100) return true;
    }
    else
    {
        if(bid <= fib0) return true;
        if(ask >= fib100) return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Cancel Setup                                                      |
//+------------------------------------------------------------------+
void CancelSetup()
{
    ObjectsDeleteAll(0, prefix);
    setupActive = false;
    fib0 = fib71 = fib79 = fib100 = 0;

    if(pendingTicket > 0)
    {
        trade.OrderDelete(pendingTicket);
        pendingTicket = 0;
    }

    Print("⚪ Setup CANCELLED");
}

//+------------------------------------------------------------------+
//| Check Entry                                                       |
//+------------------------------------------------------------------+
void CheckEntry()
{
    if(!setupActive || dailyTrades >= MaxDailyTrades) return;
    if(pendingTicket > 0) return;

    double bid = symbolInfo.Bid();
    double higherEntry = MathMax(fib71, fib79);
    double lowerEntry = MathMin(fib71, fib79);

    bool inZone = (bid >= lowerEntry && bid <= higherEntry);

    if(inZone)
    {
        PlaceLimitOrder();
    }
}

//+------------------------------------------------------------------+
//| Place Limit Order                                                 |
//+------------------------------------------------------------------+
void PlaceLimitOrder()
{
    double entryPrice = (fib71 + fib79) / 2.0;
    double lotSize = CalculateLotSize();
    int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);

    entryPrice = NormalizeDouble(entryPrice, digits);

    bool success;
    if(isBullishSetup)
        success = trade.BuyLimit(lotSize, entryPrice, g_symbol, fib0, fib100, ORDER_TIME_GTC, 0, "Fibo71");
    else
        success = trade.SellLimit(lotSize, entryPrice, g_symbol, fib0, fib100, ORDER_TIME_GTC, 0, "Fibo71");

    if(success)
    {
        pendingTicket = trade.ResultOrder();
        dailyTrades++;
        Print("✅ Order placed: ", isBullishSetup ? "BUY" : "SELL", " @ ", entryPrice);
    }
    else
    {
        Print("❌ Order failed: ", trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| Check Pending Order                                               |
//+------------------------------------------------------------------+
void CheckPendingOrder()
{
    if(!OrderSelect(pendingTicket))
    {
        pendingTicket = 0;
        return;
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk = RiskPercent / 100.0 * balance;
    double entryPrice = (fib71 + fib79) / 2.0;
    double slDistance = MathAbs(entryPrice - fib100);
    double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);

    double lots = risk / (slDistance / point * tickValue);

    double minLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
    double step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

    lots = MathFloor(lots / step) * step;
    lots = MathMax(minLot, MathMin(maxLot, lots));

    return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Print Setup                                                       |
//+------------------------------------------------------------------+
void PrintSetup(string dir)
{
    Print("══════════════════════════════════════════════════");
    Print(dir == "BULLISH" ? "🟢 BULLISH BOS" : "🔴 BEARISH BOS");
    Print("Swing H: ", lastSwingHigh.price, " @ bar[", lastSwingHigh.barIdx, "]");
    Print("Swing L: ", lastSwingLow.price, " @ bar[", lastSwingLow.barIdx, "]");
    Print("TP (0%): ", fib0);
    Print("Entry: ", MathMin(fib71, fib79), " - ", MathMax(fib71, fib79));
    Print("SL (100%): ", fib100);
    Print("══════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Send BOS Notification                                             |
//+------------------------------------------------------------------+
void SendBOSNotification()
{
    string dir = isBullishSetup ? "🟢 BULLISH" : "🔴 BEARISH";
    string msg = dir + " BOS Detected\n\n";
    msg += "Symbol: " + g_symbol + "\n";
    msg += "TP (0%): " + DoubleToString(fib0, 5) + "\n";
    msg += "Entry: " + DoubleToString(fib71, 5) + " - " + DoubleToString(fib79, 5) + "\n";
    msg += "SL (100%): " + DoubleToString(fib100, 5);

    SendTelegram(msg);
}

//+------------------------------------------------------------------+
//| Send Telegram Message                                             |
//+------------------------------------------------------------------+
bool SendTelegram(string message)
{
    if(TelegramBotToken == "" || TelegramChatID == "")
        return false;

    string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage";
    string postData = "chat_id=" + TelegramChatID + "&text=" + URLEncode(message);

    char data[], result[];
    string headers;

    StringToCharArray(postData, data, 0, WHOLE_ARRAY, CP_UTF8);
    ArrayResize(data, ArraySize(data) - 1);

    int res = WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n",
                         5000, data, result, headers);

    return (res != -1);
}

//+------------------------------------------------------------------+
//| URL Encode                                                        |
//+------------------------------------------------------------------+
string URLEncode(string text)
{
    string result = "";
    string hex = "0123456789ABCDEF";

    for(int i = 0; i < StringLen(text); i++)
    {
        ushort ch = StringGetCharacter(text, i);
        if((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
           (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.')
        {
            result += CharToString((uchar)ch);
        }
        else if(ch == ' ')
        {
            result += "+";
        }
        else
        {
            result += "%";
            result += StringSubstr(hex, (ch >> 4) & 15, 1);
            result += StringSubstr(hex, ch & 15, 1);
        }
    }
    return result;
}
//+------------------------------------------------------------------+
