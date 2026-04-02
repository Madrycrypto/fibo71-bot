//+------------------------------------------------------------------+
//|                                          Fibo71_Bot_v1.mq5        |
//|                                    Clean BOS + Fibonacci Bot      |
//+------------------------------------------------------------------+
#property copyright "Fibo71 Bot v1"
#property version   "1.30"
#property strict

#include <Trade\Trade.mqh>

//═══════════════════════════════════════════════════════════════════════════════
// INPUT PARAMETERS
//═══════════════════════════════════════════════════════════════════════════════

// Basic
input string   Section1 = "═══ Basic ═══";
input string   TradeSymbol = "";          // Symbol (empty = chart symbol)
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;
input int      MagicNumber = 710071;

// BOS Detection - Adjust these to match SMC indicator
input string   Section2 = "═══ BOS Detection ═══";
input int      SwingLookback = 2;          // Candles on each side for swing point
input int      BOSLookback = 100;          // Max age of swing point (bars)

// Fibonacci
input string   Section3 = "═══ Fibonacci ═══";
input double   FibEntryMin = 0.71;         // Entry zone start (71%)
input double   FibEntryMax = 0.79;         // Entry zone end (79%)

// Risk
input string   Section4 = "═══ Risk ═══";
input double   RiskPercent = 1.0;
input double   FixedLot = 0.0;             // If > 0, use fixed lot instead of %

// Telegram
input string   Section5 = "═══ Telegram ═══";
input bool     EnableTelegram = false;
input string   TelegramBotToken = "";
input string   TelegramChatID = "";

// Display
input string   Section6 = "═══ Display ═══";
input int      LineExtensionBars = 50;      // How far lines extend (bars)
input color    ColorTP = clrLime;           // TP (0%) line color
input color    ColorSL = clrRed;            // SL (100%) line color
input color    ColorEntry = clrBlue;        // Entry zone color
input color    ColorBullish = clrGreen;     // Bullish setup color
input color    ColorBearish = clrRed;       // Bearish setup color
input int      LineWidthMain = 2;           // TP/SL line width
input int      LineWidthZone = 1;           // Entry zone line width

//═══════════════════════════════════════════════════════════════════════════════
// GLOBALS
//═══════════════════════════════════════════════════════════════════════════════

CTrade trade;

// Working symbol (auto-set from chart if input is empty)
string g_symbol = "";

// Swing points structure
struct SwingPoint {
    double price;
    int    barIdx;
    bool   isHigh;  // true = swing high, false = swing low
    bool   valid;
};

SwingPoint lastSwingHigh;
SwingPoint lastSwingLow;
SwingPoint prevSwingHigh;
SwingPoint prevSwingLow;

// Setup
bool setupActive = false;
bool isBullishSetup = false;

// Fibonacci
double fib0 = 0;      // TP (0%)
double fib71 = 0;     // Entry start
double fib79 = 0;     // Entry end
double fib100 = 0;    // SL (100%)

// Pending order
ulong pendingTicket = 0;

// BOS bar for line drawing
int bosBarIdx = 0;

//═══════════════════════════════════════════════════════════════════════════════
// INIT
//═══════════════════════════════════════════════════════════════════════════════

int OnInit()
{
    // Auto-detect symbol from chart if not specified
    g_symbol = (TradeSymbol == "") ? _Symbol : TradeSymbol;

    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(20);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    Print("══════════════════════════════════════════════════");
    Print("🤖 Fibo71 Bot v1.30 - BOS Detection");
    Print("══════════════════════════════════════════════════");
    Print("Symbol: ", g_symbol, " | TF: ", EnumToString(Timeframe));
    Print("Swing Lookback: ", SwingLookback, " | BOS Lookback: ", BOSLookback);
    Print("Entry Zone: ", FibEntryMin*100, "% - ", FibEntryMax*100, "%");
    Print("Line Extension: ", LineExtensionBars, " bars");
    Print("══════════════════════════════════════════════════");

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, "F71_");
    Print("🛑 Bot stopped");
}

//═══════════════════════════════════════════════════════════════════════════════
// ON TICK
//═══════════════════════════════════════════════════════════════════════════════

void OnTick()
{
    // Check invalidation
    if(setupActive)
    {
        if(CheckInvalidation())
        {
            CancelSetup();
            return;
        }

        // Check entry
        CheckEntry();
    }

    // New candle
    static datetime lastBar = 0;
    if(iTime(g_symbol, Timeframe, 0) == lastBar) return;
    lastBar = iTime(g_symbol, Timeframe, 0);

    // Analyze
    FindAllSwingPoints();
    DetectBOS();
}

//═══════════════════════════════════════════════════════════════════════════════
// FIND ALL SWING POINTS (Improved)
//═══════════════════════════════════════════════════════════════════════════════

void FindAllSwingPoints()
{
    // Reset
    lastSwingHigh.valid = false;
    lastSwingLow.valid = false;
    prevSwingHigh.valid = false;
    prevSwingLow.valid = false;

    int foundHighs = 0;
    int foundLows = 0;

    // Find swing points in order (most recent first)
    for(int i = SwingLookback; i < BOSLookback - SwingLookback; i++)
    {
        // Check for swing high
        if(foundHighs < 2 && IsSwingHigh(i))
        {
            if(foundHighs == 0)
            {
                lastSwingHigh.price = iHigh(g_symbol, Timeframe, i);
                lastSwingHigh.barIdx = i;
                lastSwingHigh.isHigh = true;
                lastSwingHigh.valid = true;
                foundHighs = 1;
            }
            else if(foundHighs == 1)
            {
                prevSwingHigh.price = iHigh(g_symbol, Timeframe, i);
                prevSwingHigh.barIdx = i;
                prevSwingHigh.isHigh = true;
                prevSwingHigh.valid = true;
                foundHighs = 2;
            }
        }

        // Check for swing low
        if(foundLows < 2 && IsSwingLow(i))
        {
            if(foundLows == 0)
            {
                lastSwingLow.price = iLow(g_symbol, Timeframe, i);
                lastSwingLow.barIdx = i;
                lastSwingLow.isHigh = false;
                lastSwingLow.valid = true;
                foundLows = 1;
            }
            else if(foundLows == 1)
            {
                prevSwingLow.price = iLow(g_symbol, Timeframe, i);
                prevSwingLow.barIdx = i;
                prevSwingLow.isHigh = false;
                prevSwingLow.valid = true;
                foundLows = 2;
            }
        }

        // Stop if we found everything
        if(foundHighs >= 2 && foundLows >= 2) break;
    }
}

//═══════════════════════════════════════════════════════════════════════════════
// IS SWING HIGH/LOW HELPERS
//═══════════════════════════════════════════════════════════════════════════════

bool IsSwingHigh(int bar)
{
    double h = iHigh(g_symbol, Timeframe, bar);

    // Check if this bar's high is higher than surrounding bars
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

    // Check if this bar's low is lower than surrounding bars
    for(int j = 1; j <= SwingLookback; j++)
    {
        if(iLow(g_symbol, Timeframe, bar + j) <= l) return false;
        if(iLow(g_symbol, Timeframe, bar - j) <= l) return false;
    }
    return true;
}

//═══════════════════════════════════════════════════════════════════════════════
// DETECT BOS (Simplified SMC Logic)
//═══════════════════════════════════════════════════════════════════════════════

void DetectBOS()
{
    if(setupActive) return;  // Already have a setup

    // Need valid swing points
    if(!lastSwingHigh.valid || !lastSwingLow.valid) return;

    double close = iClose(g_symbol, Timeframe, 1);  // Use candle 1 (confirmed)
    double high = iHigh(g_symbol, Timeframe, 1);
    double low = iLow(g_symbol, Timeframe, 1);

    // ================================================================
    // BULLISH BOS: Price breaks above swing HIGH
    // - Last swing LOW is more recent than last swing HIGH
    // - Price closes above the swing HIGH
    // ================================================================
    if(lastSwingLow.barIdx < lastSwingHigh.barIdx)  // Low is more recent
    {
        if(close > lastSwingHigh.price)  // Break above swing high
        {
            // BULLISH BOS detected!
            Print("🟢 BULLISH BOS: Close ", close, " broke above ", lastSwingHigh.price);

            // Setup: swing HIGH is 0% (TP), swing LOW is 100% (SL)
            ActivateBullishSetup(lastSwingHigh.price, lastSwingLow.price);
        }
    }

    // ================================================================
    // BEARISH BOS: Price breaks below swing LOW
    // - Last swing HIGH is more recent than last swing LOW
    // - Price closes below the swing LOW
    // ================================================================
    if(lastSwingHigh.barIdx < lastSwingLow.barIdx)  // High is more recent
    {
        if(close < lastSwingLow.price)  // Break below swing low
        {
            // BEARISH BOS detected!
            Print("🔴 BEARISH BOS: Close ", close, " broke below ", lastSwingLow.price);

            // Setup: swing LOW is 0% (TP), swing HIGH is 100% (SL)
            ActivateBearishSetup(lastSwingHigh.price, lastSwingLow.price);
        }
    }
}

//═══════════════════════════════════════════════════════════════════════════════
// ACTIVATE SETUP
//═══════════════════════════════════════════════════════════════════════════════

void ActivateBullishSetup(double swingH, double swingL)
{
    if(setupActive) return;

    double range = swingH - swingL;

    fib0 = swingH;                              // TP (0%) = swing HIGH
    fib100 = swingL;                            // SL (100%) = swing LOW
    fib71 = swingH - range * FibEntryMin;       // Entry zone start
    fib79 = swingH - range * FibEntryMax;       // Entry zone end

    isBullishSetup = true;
    setupActive = true;
    bosBarIdx = 1;

    DrawLines();
    PrintSetup();

    SendTelegram("🟢 BULLISH BOS\nTP: " + DoubleToString(fib0, 5) +
                 "\nEntry: " + DoubleToString(fib79, 5) + " - " + DoubleToString(fib71, 5) +
                 "\nSL: " + DoubleToString(fib100, 5));
}

void ActivateBearishSetup(double swingH, double swingL)
{
    if(setupActive) return;

    double range = swingH - swingL;

    fib0 = swingL;                              // TP (0%) = swing LOW
    fib100 = swingH;                            // SL (100%) = swing HIGH
    fib71 = swingL + range * FibEntryMin;       // Entry zone start
    fib79 = swingL + range * FibEntryMax;       // Entry zone end

    isBullishSetup = false;
    setupActive = true;
    bosBarIdx = 1;

    DrawLines();
    PrintSetup();

    SendTelegram("🔴 BEARISH BOS\nTP: " + DoubleToString(fib0, 5) +
                 "\nEntry: " + DoubleToString(fib71, 5) + " - " + DoubleToString(fib79, 5) +
                 "\nSL: " + DoubleToString(fib100, 5));
}

//═══════════════════════════════════════════════════════════════════════════════
// CHECK INVALIDATION
//═══════════════════════════════════════════════════════════════════════════════

bool CheckInvalidation()
{
    double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);

    // Check if in entry zone
    double higherEntry = MathMax(fib71, fib79);
    double lowerEntry = MathMin(fib71, fib79);
    bool inZone = (bid >= lowerEntry && bid <= higherEntry);

    if(inZone) return false;  // Safe - in entry zone

    // Check if touched 0% or 100%
    if(isBullishSetup)
    {
        if(ask >= fib0) return true;   // Touched TP (0%)
        if(bid <= fib100) return true; // Touched SL (100%)
    }
    else
    {
        if(bid <= fib0) return true;   // Touched TP (0%)
        if(ask >= fib100) return true; // Touched SL (100%)
    }

    return false;
}

//═══════════════════════════════════════════════════════════════════════════════
// CANCEL SETUP
//═══════════════════════════════════════════════════════════════════════════════

void CancelSetup()
{
    ObjectsDeleteAll(0, "F71_");
    setupActive = false;
    fib0 = fib71 = fib79 = fib100 = 0;

    if(pendingTicket > 0)
    {
        trade.OrderDelete(pendingTicket);
        pendingTicket = 0;
    }

    Print("⚪ SETUP CANCELLED - price touched extreme");
    SendTelegram("⚪ Setup Cancelled");
}

//═══════════════════════════════════════════════════════════════════════════════
// CHECK ENTRY
//═══════════════════════════════════════════════════════════════════════════════

void CheckEntry()
{
    if(pendingTicket > 0) return;  // Already have order

    double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);

    double higherEntry = MathMax(fib71, fib79);
    double lowerEntry = MathMin(fib71, fib79);

    // Entry zone: price between fib79 and fib71
    bool inZone = (bid >= lowerEntry && bid <= higherEntry);

    if(inZone)
    {
        PlaceOrder();
    }
}

//═══════════════════════════════════════════════════════════════════════════════
// PLACE ORDER
//═══════════════════════════════════════════════════════════════════════════════

void PlaceOrder()
{
    double lot = FixedLot > 0 ? FixedLot : CalculateLot();
    double entry = (fib71 + fib79) / 2.0;
    int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
    entry = NormalizeDouble(entry, digits);

    bool ok;
    if(isBullishSetup)
        ok = trade.BuyLimit(lot, entry, g_symbol, fib0, fib100, ORDER_TIME_GTC, 0, "F71");
    else
        ok = trade.SellLimit(lot, entry, g_symbol, fib0, fib100, ORDER_TIME_GTC, 0, "F71");

    if(ok)
    {
        pendingTicket = trade.ResultOrder();
        Print("✅ Order placed: ", isBullishSetup ? "BUY" : "SELL", " @ ", entry);
        SendTelegram("✅ Order: " + (isBullishSetup ? "BUY" : "SELL") + " @ " + DoubleToString(entry, digits));
    }
    else
    {
        Print("❌ Order failed: ", trade.ResultRetcode());
    }
}

//═══════════════════════════════════════════════════════════════════════════════
// CALCULATE LOT
//═══════════════════════════════════════════════════════════════════════════════

double CalculateLot()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk = balance * RiskPercent / 100.0;
    double sl = MathAbs((fib71 + fib79) / 2.0 - fib100);
    double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);

    double lot = risk / (sl / point * tickValue);

    double min = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
    double max = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
    double step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

    lot = MathFloor(lot / step) * step;
    lot = MathMax(min, MathMin(max, lot));

    return NormalizeDouble(lot, 2);
}

//═══════════════════════════════════════════════════════════════════════════════
// DRAW LINES
//═══════════════════════════════════════════════════════════════════════════════

void DrawLines()
{
    // Check if we have enough bars
    int bars = iBars(g_symbol, Timeframe);
    if(bars < bosBarIdx + 1)
        return;

    ObjectsDeleteAll(0, "F71_");

    // Get BOS candle time and calculate end time
    datetime bosTime = iTime(g_symbol, Timeframe, bosBarIdx);
    datetime endTime = bosTime + PeriodSeconds(Timeframe) * LineExtensionBars;

    color setupColor = isBullishSetup ? ColorBullish : ColorBearish;

    // TP (0%) - target line
    TrendLine("F71_TP", bosTime, fib0, endTime, fib0, ColorTP, LineWidthMain, "0% TP");

    // Entry zone lines
    TrendLine("F71_Entry71", bosTime, fib71, endTime, fib71, ColorEntry, LineWidthZone, "71%");
    TrendLine("F71_Entry79", bosTime, fib79, endTime, fib79, ColorEntry, LineWidthZone, "79%");

    // Fill entry zone with rectangle
    RectCreate("F71_Zone", bosTime, fib71, endTime, fib79, setupColor);

    // SL (100%) line
    TrendLine("F71_SL", bosTime, fib100, endTime, fib100, ColorSL, LineWidthMain, "100% SL");

    // Swing points arrows
    if(lastSwingHigh.valid)
        Arrow("F71_SH", lastSwingHigh.barIdx, lastSwingHigh.price, clrRed, 233);
    if(lastSwingLow.valid)
        Arrow("F71_SL", lastSwingLow.barIdx, lastSwingLow.price, clrGreen, 234);

    // BOS label
    string bosText = isBullishSetup ? "🟢 BULLISH" : "🔴 BEARISH";
    double bosPrice = isBullishSetup ? lastSwingLow.price : lastSwingHigh.price;
    Label("F71_BOS", bosTime, bosPrice, bosText, setupColor);

    ChartRedraw(0);
}

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

void RectCreate(string name, datetime time1, double price1, datetime time2, double price2, color col)
{
    ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

void Label(string name, datetime time, double price, string text, color col)
{
    ObjectCreate(0, name, OBJ_TEXT, 0, time, price);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
}

void Arrow(string name, int bar, double price, color col, int code)
{
    datetime time = iTime(g_symbol, Timeframe, bar);
    ObjectCreate(0, name, OBJ_ARROW, 0, time, price);
    ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

//═══════════════════════════════════════════════════════════════════════════════
// PRINT SETUP
//═══════════════════════════════════════════════════════════════════════════════

void PrintSetup()
{
    Print("══════════════════════════════════════════════════");
    Print(isBullishSetup ? "🟢 BULLISH BOS" : "🔴 BEARISH BOS");
    Print("Swing High: ", lastSwingHigh.price, " @ bar[", lastSwingHigh.barIdx, "]");
    Print("Swing Low: ", lastSwingLow.price, " @ bar[", lastSwingLow.barIdx, "]");
    Print("Fib 0% (TP): ", fib0);
    Print("Entry Zone: ", fib71, " - ", fib79);
    Print("Fib 100% (SL): ", fib100);
    Print("══════════════════════════════════════════════════");
}

//═══════════════════════════════════════════════════════════════════════════════
// TELEGRAM
//═══════════════════════════════════════════════════════════════════════════════

void SendTelegram(string msg)
{
    if(!EnableTelegram) return;
    if(TelegramBotToken == "" || TelegramChatID == "") return;

    string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage";
    string data = "chat_id=" + TelegramChatID + "&text=" + UrlEncode(msg);

    char req[], res[];
    string resHeaders;
    StringToCharArray(data, req, 0, WHOLE_ARRAY, CP_UTF8);
    ArrayResize(req, ArraySize(req) - 1);

    WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n", 5000, req, res, resHeaders);
}

string UrlEncode(string s)
{
    string hex = "0123456789ABCDEF";
    string out = "";
    for(int i = 0; i < StringLen(s); i++)
    {
        ushort c = StringGetCharacter(s, i);
        if((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
           c == '-' || c == '_' || c == '.')
            out += CharToString((uchar)c);
        else if(c == ' ')
            out += "+";
        else
        {
            out += "%";
            out += StringSubstr(hex, (c >> 4) & 15, 1);
            out += StringSubstr(hex, c & 15, 1);
        }
    }
    return out;
}
//+------------------------------------------------------------------+
