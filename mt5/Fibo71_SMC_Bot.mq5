//+------------------------------------------------------------------+
//|                                          Fibo71_SMC_Bot.mq5       |
//|                                    BOS from SMC + Fibonacci       |
//+------------------------------------------------------------------+
#property copyright "Fibo71 Bot - SMC Integration"
#property version   "1.20"
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
input ENUM_TIMEFRAMES Timeframe = PERIOD_M1;          // Trading Timeframe
input int      MagicNumber = 710071;                  // Magic Number

// SMC Indicator
input string   Section2 = "════════ SMC Indicator ════════";
input string   SMC_IndicatorName = "Smart Money Concepts";  // Indicator name

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

// Working symbol (auto-set from chart if input is empty)
string g_symbol = "";

// SMC Indicator handle
int smcHandle = INVALID_HANDLE;

// BOS data from indicator
struct BOSData
{
    bool       detected;
    bool       isBullish;
    double     swingHigh;
    double     swingLow;
    int        swingHighIdx;
    int        swingLowIdx;
    datetime   time;
};

BOSData currentBOS;

// Fibonacci levels
double fib0 = 0;      // TP (0%)
double fib71 = 0;     // Entry zone start
double fib79 = 0;     // Entry zone end
double fib100 = 0;    // SL (100%)

// State
bool setupActive = false;
int dailyTrades = 0;
datetime lastTradeDate = 0;
ulong pendingTicket = 0;
int bosBarIdx = 0;  // BOS bar for line drawing

// Chart prefix
string prefix = "Fibo71_";

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    // Auto-detect symbol from chart if not specified
    g_symbol = (TradeSymbol == "") ? _Symbol : TradeSymbol;

    // Initialize trade
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(20);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    // Check symbol
    if(!symbolInfo.Name(g_symbol))
    {
        Print("❌ Symbol not found: ", g_symbol);
        return INIT_FAILED;
    }

    // Load SMC indicator
    smcHandle = iCustom(g_symbol, Timeframe, SMC_IndicatorName);
    if(smcHandle == INVALID_HANDLE)
    {
        Print("❌ Cannot load SMC indicator: ", SMC_IndicatorName);
        Print("⚠️ Make sure indicator is in Indicators folder");
        return INIT_FAILED;
    }

    Print("══════════════════════════════════════════════════");
    Print("🤖 Fibo 71 Bot - SMC Integration v1.20");
    Print("══════════════════════════════════════════════════");
    Print("Symbol: ", g_symbol, " | Timeframe: ", EnumToString(Timeframe));
    Print("SMC Indicator: ", SMC_IndicatorName);
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
    if(smcHandle != INVALID_HANDLE)
        IndicatorRelease(smcHandle);

    ObjectsDeleteAll(0, prefix);
    Print("🛑 Fibo 71 SMC Bot stopped");
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

        // Check for new BOS from indicator
        CheckBOSFromIndicator();

        // Check trade setup
        if(setupActive)
        {
            CheckTradeSetup();
        }
    }

    // Check pending order
    if(pendingTicket > 0)
        CheckPendingOrder();
}

//+------------------------------------------------------------------+
//| Check BOS from SMC Indicator                                      |
//+------------------------------------------------------------------+
void CheckBOSFromIndicator()
{
    // SMC Indicator buffers (typical structure - may need adjustment)
    // Buffer 0: BOS Bullish
    // Buffer 1: BOS Bearish
    // Buffer 2: Swing High
    // Buffer 3: Swing Low
    // etc.

    double bosBull[], bosBear[], swingH[], swingL[];

    ArraySetAsSeries(bosBull, true);
    ArraySetAsSeries(bosBear, true);
    ArraySetAsSeries(swingH, true);
    ArraySetAsSeries(swingL, true);

    // Copy buffers - adjust indices based on actual indicator
    if(CopyBuffer(smcHandle, 0, 0, 10, bosBull) < 0 ||
       CopyBuffer(smcHandle, 1, 0, 10, bosBear) < 0)
    {
        Print("⚠️ Cannot read SMC buffers");
        return;
    }

    // Check for BOS signal on candle 1 (confirmed)
    bool newBullishBOS = (bosBull[1] != 0 && bosBull[1] != EMPTY_VALUE);
    bool newBearishBOS = (bosBear[1] != 0 && bosBear[1] != EMPTY_VALUE);

    if(newBullishBOS || newBearishBOS)
    {
        // Get swing points from indicator
        // This needs adjustment based on actual buffer structure
        GetSwingPointsFromIndicator(newBullishBOS);

        if(currentBOS.swingHigh > 0 && currentBOS.swingLow > 0)
        {
            currentBOS.detected = true;
            currentBOS.isBullish = newBullishBOS;
            currentBOS.time = iTime(g_symbol, Timeframe, 1);
            bosBarIdx = 1;  // BOS confirmed on previous candle

            // Calculate Fibonacci
            CalculateFibonacci();
            DrawFibonacciLines();

            setupActive = true;

            Print(newBullishBOS ? "🟢 BULLISH BOS detected" : "🔴 BEARISH BOS detected");
            Print("Swing H: ", currentBOS.swingHigh, " | Swing L: ", currentBOS.swingLow);
            Print("Fib 0%: ", fib0, " | Entry: ", fib71, " - ", fib79, " | Fib 100%: ", fib100);

            if(EnableTelegram)
                SendBOSNotification();
        }
    }
}

//+------------------------------------------------------------------+
//| Get Swing Points from Indicator                                   |
//+------------------------------------------------------------------+
void GetSwingPointsFromIndicator(bool isBullish)
{
    // Reset
    currentBOS.swingHigh = 0;
    currentBOS.swingLow = 0;

    // Try to read swing points from indicator buffers
    // Buffer indices may need adjustment
    double swingH[], swingL[];
    ArraySetAsSeries(swingH, true);
    ArraySetAsSeries(swingL, true);

    if(CopyBuffer(smcHandle, 2, 0, 100, swingH) < 0 ||
       CopyBuffer(smcHandle, 3, 0, 100, swingL) < 0)
    {
        // Fallback: find manually
        FindSwingPointsManually(isBullish);
        return;
    }

    // Find most recent swing points
    for(int i = 2; i < 100; i++)
    {
        if(swingH[i] != 0 && swingH[i] != EMPTY_VALUE)
        {
            currentBOS.swingHigh = swingH[i];
            currentBOS.swingHighIdx = i;
            break;
        }
    }

    for(int i = 2; i < 100; i++)
    {
        if(swingL[i] != 0 && swingL[i] != EMPTY_VALUE)
        {
            currentBOS.swingLow = swingL[i];
            currentBOS.swingLowIdx = i;
            break;
        }
    }

    // If not found, use manual detection
    if(currentBOS.swingHigh == 0 || currentBOS.swingLow == 0)
    {
        FindSwingPointsManually(isBullish);
    }
}

//+------------------------------------------------------------------+
//| Find Swing Points Manually (fallback)                             |
//+------------------------------------------------------------------+
void FindSwingPointsManually(bool isBullish)
{
    int lookback = 50;

    // Find swing high
    for(int i = 2; i < lookback - 2; i++)
    {
        double h = iHigh(g_symbol, Timeframe, i);
        if(h > iHigh(g_symbol, Timeframe, i+1) &&
           h > iHigh(g_symbol, Timeframe, i+2) &&
           h > iHigh(g_symbol, Timeframe, i-1) &&
           h > iHigh(g_symbol, Timeframe, i-2))
        {
            currentBOS.swingHigh = h;
            currentBOS.swingHighIdx = i;
            break;
        }
    }

    // Find swing low
    for(int i = 2; i < lookback - 2; i++)
    {
        double l = iLow(g_symbol, Timeframe, i);
        if(l < iLow(g_symbol, Timeframe, i+1) &&
           l < iLow(g_symbol, Timeframe, i+2) &&
           l < iLow(g_symbol, Timeframe, i-1) &&
           l < iLow(g_symbol, Timeframe, i-2))
        {
            currentBOS.swingLow = l;
            currentBOS.swingLowIdx = i;
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Levels                                        |
//+------------------------------------------------------------------+
void CalculateFibonacci()
{
    if(currentBOS.isBullish)
    {
        // Bullish: swingLow is 100%, swingHigh is 0%
        fib0 = currentBOS.swingHigh;
        fib100 = currentBOS.swingLow;
        double range = currentBOS.swingHigh - currentBOS.swingLow;
        fib71 = currentBOS.swingHigh - range * FibEntryMin;
        fib79 = currentBOS.swingHigh - range * FibEntryMax;
    }
    else
    {
        // Bearish: swingHigh is 100%, swingLow is 0%
        fib0 = currentBOS.swingLow;
        fib100 = currentBOS.swingHigh;
        double range = currentBOS.swingHigh - currentBOS.swingLow;
        fib71 = currentBOS.swingLow + range * FibEntryMin;
        fib79 = currentBOS.swingLow + range * FibEntryMax;
    }
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Lines                                              |
//+------------------------------------------------------------------+
void DrawFibonacciLines()
{
    ObjectsDeleteAll(0, prefix);

    // Get BOS candle time and calculate end time
    datetime bosTime = iTime(g_symbol, Timeframe, bosBarIdx);
    datetime endTime = bosTime + PeriodSeconds(Timeframe) * LineExtensionBars;

    color setupColor = currentBOS.isBullish ? ColorBullish : ColorBearish;

    // TP line (0%)
    TrendLine(prefix + "TP", bosTime, fib0, endTime, fib0, ColorTP, LineWidthMain, "0% TP");

    // Entry zone lines
    TrendLine(prefix + "Entry71", bosTime, fib71, endTime, fib71, ColorEntry, LineWidthZone, "71%");
    TrendLine(prefix + "Entry79", bosTime, fib79, endTime, fib79, ColorEntry, LineWidthZone, "79%");

    // Fill entry zone with rectangle
    RectCreate(prefix + "Zone", bosTime, fib71, endTime, fib79, setupColor);

    // SL line (100%)
    TrendLine(prefix + "SL", bosTime, fib100, endTime, fib100, ColorSL, LineWidthMain, "100% SL");

    // BOS label
    string bosText = currentBOS.isBullish ? "🟢 BULLISH" : "🔴 BEARISH";
    double bosPrice = currentBOS.isBullish ? currentBOS.swingLow : currentBOS.swingHigh;
    Label(prefix + "BOS", bosTime, bosPrice, bosText, setupColor);

    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Trend Line helper                                                 |
//+------------------------------------------------------------------+
void TrendLine(string name, datetime time1, double price1, datetime time2, double price2, color col, int width, string label)
{
    ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetString(0, name, OBJPROP_TEXT, label);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Rectangle helper                                                  |
//+------------------------------------------------------------------+
void RectCreate(string name, datetime time1, double price1, datetime time2, double price2, color col)
{
    ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

//+------------------------------------------------------------------+
//| Label helper                                                      |
//+------------------------------------------------------------------+
void Label(string name, datetime time, double price, string text, color col)
{
    ObjectCreate(0, name, OBJ_TEXT, 0, time, price);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
}

//+------------------------------------------------------------------+
//| Check Setup Invalidation                                          |
//+------------------------------------------------------------------+
bool CheckSetupInvalidation()
{
    if(fib0 == 0 || fib100 == 0)
        return false;

    double bid = symbolInfo.Bid();
    double ask = symbolInfo.Ask();

    // Check if in entry zone
    bool inEntryZone = false;
    if(currentBOS.isBullish)
        inEntryZone = (bid <= fib71 && bid >= fib79);
    else
        inEntryZone = (bid >= fib79 && bid <= fib71);

    // If not in entry zone and touched extreme -> cancel
    if(!inEntryZone)
    {
        // Touched 0%
        if(currentBOS.isBullish && ask >= fib0) return true;
        if(!currentBOS.isBullish && bid <= fib0) return true;

        // Touched 100%
        if(currentBOS.isBullish && bid <= fib100) return true;
        if(!currentBOS.isBullish && ask >= fib100) return true;
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
    currentBOS.detected = false;
    fib0 = fib71 = fib79 = fib100 = 0;

    if(pendingTicket > 0)
    {
        trade.OrderDelete(pendingTicket);
        pendingTicket = 0;
    }

    Print("⚪ Setup CANCELLED - price touched extreme");

    if(EnableTelegram)
        SendTelegram("⚪ Setup Cancelled - price touched 0% or 100%");
}

//+------------------------------------------------------------------+
//| Check Trade Setup                                                 |
//+------------------------------------------------------------------+
void CheckTradeSetup()
{
    if(!setupActive || dailyTrades >= MaxDailyTrades)
        return;

    double bid = symbolInfo.Bid();

    bool inEntryZone = false;
    if(currentBOS.isBullish)
        inEntryZone = (bid <= fib71 && bid >= fib79);
    else
        inEntryZone = (bid >= fib79 && bid <= fib71);

    if(inEntryZone && pendingTicket == 0)
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
    if(currentBOS.isBullish)
        success = trade.BuyLimit(lotSize, entryPrice, g_symbol, fib0, fib100, ORDER_TIME_GTC, 0, "Fibo71 SMC");
    else
        success = trade.SellLimit(lotSize, entryPrice, g_symbol, fib0, fib100, ORDER_TIME_GTC, 0, "Fibo71 SMC");

    if(success)
    {
        pendingTicket = trade.ResultOrder();
        dailyTrades++;
        Print("✅ Order placed: ", currentBOS.isBullish ? "BUY" : "SELL", " @ ", entryPrice);
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

    // Check if order expired or was triggered
    // If triggered, pendingTicket becomes 0
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
//| Send BOS Notification                                             |
//+------------------------------------------------------------------+
void SendBOSNotification()
{
    string dir = currentBOS.isBullish ? "🟢 BULLISH" : "🔴 BEARISH";
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

    return (res != -1 && StringFind(CharArrayToString(result), "\"ok\":true") >= 0);
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
