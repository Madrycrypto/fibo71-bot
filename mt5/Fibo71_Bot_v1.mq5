//+------------------------------------------------------------------+
//|                                          Fibo71_Bot_v1.mq5        |
//|                                    Clean BOS + Fibonacci Bot      |
//+------------------------------------------------------------------+
#property copyright "Fibo71 Bot v1"
#property version   "1.20"
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
input int      SwingLookback = 3;          // Candles on each side for swing point
input int      BOSLookback = 50;           // Max age of swing point (bars)
input int      SwingMinDistance = 5;       // Min distance between swings (bars)

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

// Swing points
double swingHigh = 0;
double swingLow = 0;
int swingHighIdx = -1;
int swingLowIdx = -1;

// Setup
bool setupActive = false;
bool isBullishSetup = false;
bool bosSignalDetected = false;      // BOS detected, waiting for retracement
bool bosSignalIsBullish = false;     // Direction of BOS signal
double bosLevel = 0;                  // The BOS level (swing high or low)

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
    Print("🤖 Fibo71 Bot v1.20");
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
    FindSwingPoints();
    DetectBOS();
}

//═══════════════════════════════════════════════════════════════════════════════
// FIND SWING POINTS
//═══════════════════════════════════════════════════════════════════════════════

void FindSwingPoints()
{
    swingHigh = 0;
    swingLow = 0;
    swingHighIdx = -1;
    swingLowIdx = -1;

    int lookback = BOSLookback;

    // Find most recent swing high
    for(int i = SwingLookback; i < lookback - SwingLookback; i++)
    {
        bool isSwing = true;
        double h = iHigh(g_symbol, Timeframe, i);

        // Check candles on each side
        for(int j = 1; j <= SwingLookback; j++)
        {
            if(iHigh(g_symbol, Timeframe, i+j) >= h ||
               iHigh(g_symbol, Timeframe, i-j) >= h)
            {
                isSwing = false;
                break;
            }
        }

        if(isSwing)
        {
            swingHigh = h;
            swingHighIdx = i;
            break;
        }
    }

    // Find most recent swing low
    for(int i = SwingLookback; i < lookback - SwingLookback; i++)
    {
        bool isSwing = true;
        double l = iLow(g_symbol, Timeframe, i);

        for(int j = 1; j <= SwingLookback; j++)
        {
            if(iLow(g_symbol, Timeframe, i+j) <= l ||
               iLow(g_symbol, Timeframe, i-j) <= l)
            {
                isSwing = false;
                break;
            }
        }

        if(isSwing)
        {
            swingLow = l;
            swingLowIdx = i;
            break;
        }
    }
}

//═══════════════════════════════════════════════════════════════════════════════
// DETECT BOS
//═══════════════════════════════════════════════════════════════════════════════

void DetectBOS()
{
    if(swingHigh == 0 || swingLow == 0) return;
    if(swingHighIdx < 0 || swingLowIdx < 0) return;

    // Check swing points are far enough apart
    int dist = MathAbs(swingHighIdx - swingLowIdx);
    if(dist < SwingMinDistance) return;

    double close = iClose(g_symbol, Timeframe, 0);

    // === BULLISH BOS ===
    // Swing LOW is more recent (lower index), price breaks above swing HIGH
    if(swingLowIdx < swingHighIdx && close > swingHigh)
    {
        // BOS signal detected!
        bosSignalDetected = true;
        bosSignalIsBullish = true;
        bosLevel = swingHigh;  // The level to watch for retracement

        Print("🔵 BULLISH BOS signal - waiting for retracement below ", swingHigh);
    }

    // === BEARISH BOS ===
    // Swing HIGH is more recent (lower index), price breaks below swing LOW
    if(swingHighIdx < swingLowIdx && close < swingLow)
    {
        // BOS signal detected!
        bosSignalDetected = true;
        bosSignalIsBullish = false;
        bosLevel = swingLow;  // The level to watch for retracement

        Print("🔵 BEARISH BOS signal - waiting for retracement above ", swingLow);
    }

    // === CHECK RETRACEMENT CONFIRMATION ===
    if(bosSignalDetected && !setupActive)
    {
        CheckRetracementConfirmation();
    }
}

//═══════════════════════════════════════════════════════════════════════════════
// CHECK RETRACEMENT CONFIRMATION
//═══════════════════════════════════════════════════════════════════════════════

void CheckRetracementConfirmation()
{
    double close = iClose(g_symbol, Timeframe, 0);

    // BULLISH: Wait for price to close BACK BELOW the BOS level (swing HIGH)
    if(bosSignalIsBullish && close < bosLevel)
    {
        // Retracement confirmed! Draw Fibonacci
        // 100% = swing HIGH (BOS level), 0% = swing LOW
        ActivateSetup(true, swingHigh, swingLow);
        bosSignalDetected = false;  // Reset signal
    }

    // BEARISH: Wait for price to close BACK ABOVE the BOS level (swing LOW)
    if(!bosSignalIsBullish && close > bosLevel)
    {
        // Retracement confirmed! Draw Fibonacci
        // 100% = swing HIGH, 0% = swing LOW (BOS level)
        ActivateSetup(false, swingHigh, swingLow);
        bosSignalDetected = false;  // Reset signal
    }
}

//═══════════════════════════════════════════════════════════════════════════════
// ACTIVATE SETUP
//═══════════════════════════════════════════════════════════════════════════════

void ActivateSetup(bool bullish, double swingH, double swingL)
{
    if(setupActive) return;  // Already have active setup

    double range = swingH - swingL;

    if(bullish)
    {
        // BULLISH: TP at swing HIGH, SL at swing LOW
        // Entry zone is 71-79% retracement from HIGH toward LOW
        fib0 = swingH;                              // TP (0%) = swing HIGH
        fib100 = swingL;                            // SL (100%) = swing LOW
        fib71 = swingH - range * FibEntryMin;       // Higher entry (closer to HIGH)
        fib79 = swingH - range * FibEntryMax;       // Lower entry (closer to LOW)
    }
    else
    {
        // BEARISH: TP at swing LOW, SL at swing HIGH
        // Entry zone is 71-79% retracement from LOW toward HIGH
        fib0 = swingL;                              // TP (0%) = swing LOW
        fib100 = swingH;                            // SL (100%) = swing HIGH
        fib71 = swingL + range * FibEntryMin;       // Lower entry (closer to LOW)
        fib79 = swingL + range * FibEntryMax;       // Higher entry (closer to HIGH)
    }

    isBullishSetup = bullish;
    setupActive = true;
    bosBarIdx = 1;  // BOS confirmed on previous candle

    DrawLines();
    PrintSetup();
    SendTelegram("🔵 NEW SETUP: " + (bullish ? "BULLISH" : "BEARISH") +
                 "\n0% (TP): " + DoubleToString(fib0, 5) +
                 "\nEntry: " + DoubleToString(fib79, 5) + " - " + DoubleToString(fib71, 5) +
                 "\n100% (SL): " + DoubleToString(fib100, 5));
}

//═══════════════════════════════════════════════════════════════════════════════
// CHECK INVALIDATION
//═══════════════════════════════════════════════════════════════════════════════

bool CheckInvalidation()
{
    double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);

    // Check if in entry zone
    bool inZone = false;
    if(isBullishSetup)
        inZone = (bid >= fib79 && bid <= fib71);
    else
        inZone = (bid >= fib79 && bid <= fib71);

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

    // fib71 is always the higher price, fib79 is always the lower price
    // Entry zone: price between fib79 and fib71
    bool inZone = (bid >= fib79 && bid <= fib71);

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
    if(swingHighIdx >= 0)
        Arrow("F71_SH", swingHighIdx, swingHigh, clrRed, 233);  // Arrow down
    if(swingLowIdx >= 0)
        Arrow("F71_SLp", swingLowIdx, swingLow, clrGreen, 234); // Arrow up

    // BOS label
    string bosText = isBullishSetup ? "🟢 BULLISH" : "🔴 BEARISH";
    double bosPrice = isBullishSetup ? swingLow : swingHigh;
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
    // Make rectangle semi-transparent (using alpha)
    long clr = col;
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
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
    Print("Swing High: ", swingHigh, " @ bar[", swingHighIdx, "]");
    Print("Swing Low: ", swingLow, " @ bar[", swingLowIdx, "]");
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

    // Ignore response - fire and forget
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
