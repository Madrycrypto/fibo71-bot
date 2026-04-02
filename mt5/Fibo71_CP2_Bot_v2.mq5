//+------------------------------------------------------------------+
//|                                          Fibo71_CP2_Bot.mq5       |
//|                                    CP 2.0 Strategy - MT5 Bot      |
//|                                     Break of Structure + Fibo      |
//|                                        WITH GRID ORDERS           |
//+------------------------------------------------------------------+
#property copyright "Fibo71 Bot"
#property link      ""
#property version   "2.20"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

// Basic Settings
input string   Section1 = "═════════ Basic Settings ════════";
// Symbol is AUTO-DETECTED from chart! No need to set manually.
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;    // Trading Timeframe (use chart TF)
input int      MagicNumber = 710071;                 // Magic Number
input string   TradeComment = "Fibo71 CP2.0";        // Trade Comment

input double   RiskPercent = 1.0;                    // Risk per trade (%)
input double   CorrelatedRiskPercent = 0.5;          // Risk on correlated pairs (%)
input int      MaxDailyTrades = 3;                   // Max trades per day
input int      MaxOpenPositions = 2;                 // Max simultaneous positions

input int      MaxSpreadPips = 10;                   // Max spread (pips)

// Fibonacci Settings
input string   Section2 = "═════════ Fibonacci Settings ════════";
input double   FibEntryMin = 0.62;                   // Fib Entry Min (default 62%)
input double   FibEntryMax = 0.71;                   // Fib Entry Max (default 71%)
input double   FibTP = 1.0;                          // Fib TP Level (0%)
input double   FibSL = 1.0;                          // Fib SL Level (100%)

// BOS Detection
input string   Section3 = "═════════ BOS Detection ════════";
input int      BOSLookback = 50;                     // BOS Lookback Period
input double   MinImbalancePips = 10.0;              // Min Imbalance (pips)

// Grid Order Settings
input string   SectionGrid = "═════════ Grid Orders ════════";
input bool     EnableGridOrders = true;              // Enable Grid Orders
input int      GridOrdersCount = 5;                  // Number of Grid Orders
input string   GridSpacingMode = "equal";            // Spacing: equal, fib
input string   GridDistribution = "equal";           // Distribution: equal, weighted

// Filters
input string   Section4 = "═════════ Filters ════════";
input bool     EnableImbalance = true;               // Require Imbalance filter
input bool     EnableLiquiditySweep = true;          // Require Liquidity Sweep filter
input string   TradingHoursStart = "08:00";          // Trading Hours Start
input string   TradingHoursEnd = "15:00";            // Trading Hours End

input bool     EnableDailyClose = true;              // Enable Daily Auto-Close
input string   DailyCloseTime = "16:00";             // Daily Close Time (HH:MM)
input double   PartialClosePercent = 50.0;           // Partial Close at % of profit

// Telegram Settings
input string   Section5 = "═════════ Telegram Settings ════════";
input bool     EnableTelegram = true;                // Enable Telegram
input string   TelegramBotToken = "";                // Bot Token (from @BotFather)
input string   TelegramChatID = "";                  // Chat ID (from userinfobot)

// Display Settings
input string   Section6 = "════════ Display Settings ════════";
input int      LineExtensionBars = 50;               // How far lines extend (bars)
input bool     ShowFibLines = true;                  // Show Fibonacci Lines
input bool     ShowLabels = true;                    // Show Labels on Chart
input color    ColorBullish = clrGreen;              // Bullish Color
input color    ColorBearish = clrRed;                // Bearish Color
input color    ColorTP = clrLime;                    // TP Line Color
input color    ColorSL = clrRed;                     // SL Line Color
input color    ColorEntry = clrBlue;                 // Entry Zone Color
input int      LineWidthMain = 2;                    // TP/SL line width
input int      LineWidthZone = 1;                    // Entry zone line width

// Performance tracking
input string   Section7 = "════════ Performance Tracking ════════";
input bool     EnableMonthlyStats = true;            // Enable Monthly Statistics
input bool     EnableLast10Stats = true;             // Enable Last 10 Trades Stats

//+------------------------------------------------------------------+
//| GRID ORDER STRUCTURE                                              |
//+------------------------------------------------------------------+
struct GridOrderStruct
{
    double fibLevel;        // Fibonacci level (0.62, 0.65, etc.)
    double price;           // Actual price
    double riskPercent;     // Risk % for this order
    double lotSize;         // Position size
    ulong  ticket;          // Order ticket (0 if not placed)
    bool   isFilled;        // Whether order was filled
    bool   isPending;       // Whether limit order is pending
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;

// Current symbol (auto-detected from chart)
string g_Symbol;

// Swing points
double swingHigh = 0;
double swingLow = 0;
int swingHighIdx = 0;
int swingLowIdx = 0;

// BOS state
bool bullishBOS = false;
bool bearishBOS = false;
bool bullishBOSConfirmed = false;
bool bearishBOSConfirmed = false;

// Imbalance
double imbStart = 0;
double imbEnd = 0;
bool liquiditySweep = false;

// Fibonacci levels
double fib0 = 1;     // TP
double fib62 = 1;    // Entry zone start
double fib71 = 1;    // Entry zone end
double fib100 = 1;   // SL

// Grid orders
GridOrderStruct gridOrders[];
int filledGridOrders = 0;
double totalGridRisk = 0;

// Chart objects
string prefix = "Fibo71_";

// Daily stats
int dailyTrades = 0;
datetime lastTradeDate = 0;

// Pending order
ulong pendingTicket = 0;
bool setupActive = false;

// BOS bar for line drawing
int bosBarIdx = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    // Auto-detect symbol from chart
    g_Symbol = _Symbol;

    // If Timeframe is PERIOD_CURRENT, use chart timeframe
    ENUM_TIMEFRAMES chartTF = Timeframe;
    if(chartTF == PERIOD_CURRENT)
        chartTF = Period();

    // Initialize trade
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(20);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    // Check symbol
    if(!symbolInfo.Name(g_Symbol))
    {
        Print("Symbol not found: ", g_Symbol);
        return INIT_FAILED;
    }

    // Initialize grid orders array
    ArrayResize(gridOrders, GridOrdersCount);
    ResetGridOrders();

    // Check Telegram
    if(EnableTelegram && (TelegramBotToken == "" || TelegramChatID == ""))
    {
        Print("WARNING: Telegram enabled but credentials missing");
    }

    // Send startup notification
    string message = "Fibo 71 Bot Started v2.10\n\n";
    message += "Symbol: " + g_Symbol + "\n";
    message += "Timeframe: " + EnumToString(chartTF) + "\n";
    message += "Risk: " + DoubleToString(RiskPercent, 1) + "%\n";
    message += "Entry Zone: " + DoubleToString(FibEntryMin * 100, 0) + "% - " + DoubleToString(FibEntryMax * 100, 0) + "%\n";
    message += "Grid: " + (EnableGridOrders ? IntegerToString(GridOrdersCount) + " orders" : "Disabled") + "\n";
    message += "\nTime: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
    SendTelegram(message);

    Print("========================================");
    Print("Fibo 71 Bot - CP 2.0 Strategy v2.10");
    Print("========================================");
    Print("Symbol: ", g_Symbol, " | Timeframe: ", EnumToString(chartTF));
    Print("Risk: ", RiskPercent, "% | Entry Zone: ", FibEntryMin * 100, "% - ", FibEntryMax * 100, "%");
    Print("Grid Orders: ", EnableGridOrders ? IntegerToString(GridOrdersCount) + " orders" : "Disabled");
    Print("Filters: Imbalance = ", EnableImbalance ? "ON" : "OFF",
          " | Liquidity Sweep = ", EnableLiquiditySweep ? "ON" : "OFF");
    Print("Telegram: ", EnableTelegram ? "ENABLED" : "DISABLED");
    Print("========================================");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Reset Grid Orders                                                 |
//+------------------------------------------------------------------+
void ResetGridOrders()
{
    for(int i = 0; i < GridOrdersCount; i++)
    {
        gridOrders[i].fibLevel = 0;
        gridOrders[i].price = 0;
        gridOrders[i].riskPercent = 0;
        gridOrders[i].lotSize = 0;
        gridOrders[i].ticket = 0;
        gridOrders[i].isFilled = false;
        gridOrders[i].isPending = false;
    }
    filledGridOrders = 0;
    totalGridRisk = 0;
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new candle
    static datetime lastCandleTime = 0;
    datetime currentCandleTime = iTime(g_Symbol, Period(), 0);
    bool isNewCandle = (currentCandleTime != lastCandleTime);

    if(isNewCandle)
    {
        lastCandleTime = currentCandleTime;

        // Analyze market
        AnalyzeMarket();

        // Check for trade setup
        CheckTradeSetup();
    }

    // Check pending orders status
    if(EnableGridOrders)
    {
        CheckGridOrderFills();
    }
    else if(pendingTicket > 0)
    {
        CheckPendingOrder();
    }
}

//+------------------------------------------------------------------+
//| Analyze Market - BOS Detection                                    |
//+------------------------------------------------------------------+
void AnalyzeMarket()
{
    // Get historical data
    int bars = iBars(g_Symbol, Period());
    if(bars < BOSLookback + 10)
        return;

    // Find swing points
    FindSwingPoints();

    // Detect BOS
    DetectBOS();

    // Check filters
    if(bullishBOS || bearishBOS)
    {
        CheckFilters();
    }

    // Calculate Fibonacci levels
    if(bullishBOSConfirmed || bearishBOSConfirmed)
    {
        bosBarIdx = 1;  // BOS confirmed on previous candle
        CalculateFibonacci();
        DrawFibonacciLines();

        // Send setup notification (once per setup)
        if(!setupActive)
        {
            SendSetupNotification();
            setupActive = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Find Swing Points                                                 |
//+------------------------------------------------------------------+
void FindSwingPoints()
{
    // Look for swing high (higher than 2 candles on each side)
    for(int i = 2; i < BOSLookback - 2; i++)
    {
        double h = iHigh(g_Symbol, Period(), i);
        double hPrev1 = iHigh(g_Symbol, Period(), i - 1);
        double hPrev2 = iHigh(g_Symbol, Period(), i - 2);
        double hNext1 = iHigh(g_Symbol, Period(), i + 1);
        double hNext2 = iHigh(g_Symbol, Period(), i + 2);

        if(h > hPrev1 && h > hPrev2 && h > hNext1 && h > hNext2)
        {
            swingHigh = h;
            swingHighIdx = i;
            break;
        }
    }

    // Look for swing low (lower than 2 candles on each side)
    for(int i = 2; i < BOSLookback - 2; i++)
    {
        double lo = iLow(g_Symbol, Period(), i);
        double lPrev1 = iLow(g_Symbol, Period(), i - 1);
        double lPrev2 = iLow(g_Symbol, Period(), i - 2);
        double lNext1 = iLow(g_Symbol, Period(), i + 1);
        double lNext2 = iLow(g_Symbol, Period(), i + 2);

        if(lo < lPrev1 && lo < lPrev2 && lo < lNext1 && lo < lNext2)
        {
            swingLow = lo;
            swingLowIdx = i;
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Break of Structure                                         |
//+------------------------------------------------------------------+
void DetectBOS()
{
    double close = iClose(g_Symbol, Period(), 0);

    // Reset
    bullishBOS = false;
    bearishBOS = false;

    // Bearish BOS: close below swing low
    if(swingLow > 0 && close < swingLow && swingLowIdx <= BOSLookback)
    {
        bearishBOS = true;
    }

    // Bullish BOS: close above swing high
    if(swingHigh > 0 && close > swingHigh && swingHighIdx <= BOSLookback)
    {
        bullishBOS = true;
    }
}

//+------------------------------------------------------------------+
//| Check Filters - Imbalance & Liquidity Sweep                       |
//+------------------------------------------------------------------+
void CheckFilters()
{
    bullishBOSConfirmed = false;
    bearishBOSConfirmed = false;
    liquiditySweep = false;

    double point = SymbolInfoDouble(g_Symbol, SYMBOL_POINT);
    double minImbalancePrice = MinImbalancePips * point * 10;

    // Check for imbalance
    if(EnableImbalance)
    {
        // Bearish imbalance: gap between candle 2 low and current high
        double low2 = iLow(g_Symbol, Period(), 2);
        double high0 = iHigh(g_Symbol, Period(), 0);

        // Bullish imbalance: gap between candle 2 high and current low
        double high2 = iHigh(g_Symbol, Period(), 2);
        double low0 = iLow(g_Symbol, Period(), 0);

        if(bearishBOS && (low2 - high0) >= minImbalancePrice)
        {
            imbStart = low2;
            imbEnd = high0;
            bearishBOSConfirmed = true;
        }
        else if(bullishBOS && (low0 - high2) >= minImbalancePrice)
        {
            imbStart = high2;
            imbEnd = low0;
            bullishBOSConfirmed = true;
        }
    }
    else
    {
        bullishBOSConfirmed = bullishBOS;
        bearishBOSConfirmed = bearishBOS;
    }

    // Check liquidity sweep
    if(EnableLiquiditySweep && (bullishBOSConfirmed || bearishBOSConfirmed))
    {
        for(int i = 1; i <= 5; i++)
        {
            if(bearishBOSConfirmed)
            {
                double h = iHigh(g_Symbol, Period(), i);
                double c = iClose(g_Symbol, Period(), i);
                if(h > swingHigh && c < swingHigh)
                {
                    liquiditySweep = true;
                    break;
                }
            }
            else if(bullishBOSConfirmed)
            {
                double lo = iLow(g_Symbol, Period(), i);
                double c = iClose(g_Symbol, Period(), i);
                if(lo < swingLow && c > swingLow)
                {
                    liquiditySweep = true;
                    break;
                }
            }
        }

        // If no liquidity sweep, reject the setup
        if(!liquiditySweep)
        {
            bullishBOSConfirmed = false;
            bearishBOSConfirmed = false;
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Levels                                        |
//+------------------------------------------------------------------+
void CalculateFibonacci()
{
    if(bearishBOSConfirmed)
    {
        // Bearish: swingHigh is start (100%), swingLow is end (0%)
        fib0 = swingLow;                          // TP
        fib100 = swingHigh;                       // SL
        fib62 = swingLow + (swingHigh - swingLow) * FibEntryMin;
        fib71 = swingLow + (swingHigh - swingLow) * FibEntryMax;
    }
    else if(bullishBOSConfirmed)
    {
        // Bullish: swingLow is start (100%), swingHigh is end (0%)
        fib0 = swingHigh;                         // TP
        fib100 = swingLow;                        // SL
        fib62 = swingHigh - (swingHigh - swingLow) * FibEntryMin;
        fib71 = swingHigh - (swingHigh - swingLow) * FibEntryMax;
    }

    // Calculate grid order levels if enabled
    if(EnableGridOrders)
    {
        CalculateGridLevels();
    }
}

//+------------------------------------------------------------------+
//| Calculate Grid Order Levels                                       |
//+------------------------------------------------------------------+
void CalculateGridLevels()
{
    double fibRange;
    bool isBullish = bullishBOSConfirmed;

    if(bearishBOSConfirmed)
        fibRange = swingHigh - swingLow;
    else
        fibRange = swingHigh - swingLow;

    // Distribute risk across orders
    double riskPerOrder = RiskPercent / GridOrdersCount;
    if(GridDistribution == "weighted")
    {
        // Weighted: more risk at better levels
        double totalWeight = 0;
        for(int i = 0; i < GridOrdersCount; i++)
            totalWeight += 1.0 + (i * 0.2);
        riskPerOrder = RiskPercent / totalWeight;
    }

    // Calculate levels based on spacing mode
    for(int i = 0; i < GridOrdersCount; i++)
    {
        double level;

        if(GridSpacingMode == "fib")
        {
            // Fibonacci spacing
            double fibLevels[] = {0.382, 0.5, 0.618, 0.65, 0.70, 0.786};
            if(i < ArraySize(fibLevels))
                level = fibLevels[i];
            else
                level = FibEntryMin + (FibEntryMax - FibEntryMin) * i / (GridOrdersCount - 1);
        }
        else
        {
            // Equal spacing
            level = FibEntryMin + (FibEntryMax - FibEntryMin) * i / (GridOrdersCount - 1);
        }

        gridOrders[i].fibLevel = level;

        // Calculate price from fib level
        if(bearishBOSConfirmed)
            gridOrders[i].price = swingLow + fibRange * level;
        else
            gridOrders[i].price = swingHigh - fibRange * level;

        // Calculate risk per order
        if(GridDistribution == "weighted")
            gridOrders[i].riskPercent = riskPerOrder * (1.0 + (i * 0.2));
        else
            gridOrders[i].riskPercent = RiskPercent / GridOrdersCount;

        // Calculate lot size
        gridOrders[i].lotSize = CalculateLotSizeForRisk(gridOrders[i].riskPercent);
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size for Specific Risk                              |
//+------------------------------------------------------------------+
double CalculateLotSizeForRisk(double riskPct)
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk = riskPct / 100.0 * balance;

    double entryPrice = (fib62 + fib71) / 2;  // Middle of zone
    double slPips = MathAbs(entryPrice - fib100) / SymbolInfoDouble(g_Symbol, SYMBOL_POINT) / 10;
    double pipValue = SymbolInfoDouble(g_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = risk / (slPips * pipValue);

    // Normalize
    double minLot = SymbolInfoDouble(g_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(g_Symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(g_Symbol, SYMBOL_VOLUME_STEP);

    lotSize = MathFloor(lotSize / stepLot) * stepLot;
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

    return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Lines on Chart                                     |
//+------------------------------------------------------------------+
void DrawFibonacciLines()
{
    if(!ShowFibLines)
        return;

    // Check if we have enough bars
    int bars = iBars(g_Symbol, Period());
    if(bars < bosBarIdx + 1)
        return;

    // Delete old objects
    ObjectsDeleteAll(0, prefix);

    // Get BOS candle time and calculate end time
    datetime bosTime = iTime(g_Symbol, Period(), bosBarIdx);
    datetime endTime = bosTime + PeriodSeconds(Period()) * LineExtensionBars;

    color setupColor = bearishBOSConfirmed ? ColorBearish : ColorBullish;

    // Draw TP line (0%)
    TrendLine(prefix + "TP", bosTime, fib0, endTime, fib0, ColorTP, LineWidthMain, "0% TP");

    // Draw entry zone lines
    TrendLine(prefix + "Entry62", bosTime, fib62, endTime, fib62, ColorEntry, LineWidthZone, "62%");
    TrendLine(prefix + "Entry71", bosTime, fib71, endTime, fib71, ColorEntry, LineWidthZone, "71%");

    // Fill entry zone with rectangle
    RectCreate(prefix + "Zone", bosTime, fib62, endTime, fib71, setupColor);

    // Draw grid order levels if enabled
    if(EnableGridOrders && ShowLabels)
    {
        for(int i = 0; i < GridOrdersCount; i++)
        {
            string gridName = prefix + "Grid_" + IntegerToString(i);
            TrendLine(gridName, bosTime, gridOrders[i].price, endTime, gridOrders[i].price, clrGray, 1,
                     "Grid " + IntegerToString(i+1));
        }
    }

    // Draw SL line (100%)
    TrendLine(prefix + "SL", bosTime, fib100, endTime, fib100, ColorSL, LineWidthMain, "100% SL");

    // Draw swing points
    if(ShowLabels)
    {
        datetime swingHighTime = iTime(g_Symbol, Period(), swingHighIdx);
        datetime swingLowTime = iTime(g_Symbol, Period(), swingLowIdx);

        string labelName = prefix + "SwingHigh";
        ObjectCreate(0, labelName, OBJ_ARROW_DOWN, 0, swingHighTime, swingHigh);
        ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, labelName, OBJPROP_WIDTH, 2);

        labelName = prefix + "SwingLow";
        ObjectCreate(0, labelName, OBJ_ARROW_UP, 0, swingLowTime, swingLow);
        ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrGreen);
        ObjectSetInteger(0, labelName, OBJPROP_WIDTH, 2);
    }

    // BOS label
    string bosText = bearishBOSConfirmed ? "🔴 BEARISH" : "🟢 BULLISH";
    double bosPrice = bearishBOSConfirmed ? swingHigh : swingLow;
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
//| Check Trade Setup and Place Orders                                |
//+------------------------------------------------------------------+
void CheckTradeSetup()
{
    // Check if we can trade
    if(!CanOpenTrade())
        return;

    // Check if setup is active
    if(!bullishBOSConfirmed && !bearishBOSConfirmed)
        return;

    // Get current price
    double currentPrice = SymbolInfoDouble(g_Symbol, SYMBOL_BID);

    // Check if price is in entry zone
    bool inEntryZone = false;

    if(bearishBOSConfirmed)
    {
        // For sell, price needs to retrace UP into entry zone
        inEntryZone = (currentPrice >= fib71 && currentPrice <= fib62);
    }
    else if(bullishBOSConfirmed)
    {
        // For buy, price needs to retrace DOWN into entry zone
        inEntryZone = (currentPrice <= fib62 && currentPrice >= fib71);
    }

    if(inEntryZone)
    {
        if(EnableGridOrders)
        {
            if(filledGridOrders == 0)
                PlaceGridOrders();
        }
        else
        {
            if(pendingTicket == 0)
                PlaceLimitOrder();
        }
    }
}

//+------------------------------------------------------------------+
//| Check if Trading is Allowed                                       |
//+------------------------------------------------------------------+
bool CanOpenTrade()
{
    // Check daily trade limit
    if(dailyTrades >= MaxDailyTrades)
        return false;

    // Check open positions
    int openPositions = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Magic() == MagicNumber)
                openPositions++;
        }
    }

    if(openPositions >= MaxOpenPositions)
        return false;

    // Check trading hours
    MqlDateTime dt;
    TimeCurrent(dt);
    int currentHour = dt.hour;

    int startHour = (int)StringToInteger(StringSubstr(TradingHoursStart, 0, 2));
    int endHour = (int)StringToInteger(StringSubstr(TradingHoursEnd, 0, 2));

    if(currentHour < startHour || currentHour >= endHour)
        return false;

    return true;
}

//+------------------------------------------------------------------+
//| Place Single Limit Order                                          |
//+------------------------------------------------------------------+
void PlaceLimitOrder()
{
    double lotSize = CalculateLotSize();
    double entryPrice, sl, tp;
    ENUM_ORDER_TYPE orderType;

    if(bearishBOSConfirmed)
    {
        orderType = ORDER_TYPE_SELL_LIMIT;
        entryPrice = (fib62 + fib71) / 2;  // Middle of entry zone
        sl = fib100;
        tp = fib0;
    }
    else if(bullishBOSConfirmed)
    {
        orderType = ORDER_TYPE_BUY_LIMIT;
        entryPrice = (fib62 + fib71) / 2;  // Middle of entry zone
        sl = fib100;
        tp = fib0;
    }
    else
    {
        return;
    }

    // Normalize prices
    int symDigits = (int)SymbolInfoInteger(g_Symbol, SYMBOL_DIGITS);

    entryPrice = NormalizeDouble(entryPrice, symDigits);
    sl = NormalizeDouble(sl, symDigits);
    tp = NormalizeDouble(tp, symDigits);

    // Place order using OrderSend (CTrade doesn't support comment)
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_PENDING;
    request.symbol = g_Symbol;
    request.volume = lotSize;
    request.type = orderType;
    request.price = entryPrice;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 20;
    request.magic = MagicNumber;
    request.comment = TradeComment;
    request.type_time = ORDER_TIME_GTC;
    request.type_filling = ORDER_FILLING_IOC;

    if(OrderSend(request, result))
    {
        pendingTicket = result.order;
        dailyTrades++;

        string dirEmoji = bearishBOSConfirmed ? "SELL" : "BUY";
        string dirText = bearishBOSConfirmed ? "SELL LIMIT" : "BUY LIMIT";

        Print("Order placed: ", dirText, " ", lotSize, " @ ", entryPrice);

        if(EnableTelegram)
        {
            string message = dirEmoji + " Order Placed\n\n";
            message += "Symbol: " + g_Symbol + "\n";
            message += "Type: " + dirText + "\n";
            message += "Lots: " + DoubleToString(lotSize, 2) + "\n";
            message += "Entry: " + DoubleToString(entryPrice, symDigits) + "\n";
            message += "SL: " + DoubleToString(sl, symDigits) + "\n";
            message += "TP: " + DoubleToString(tp, symDigits) + "\n";
            message += "\nTime: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

            SendTelegram(message);
        }
    }
    else
    {
        Print("Order failed: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Place Grid Orders                                                 |
//+------------------------------------------------------------------+
void PlaceGridOrders()
{
    int symDigits = (int)SymbolInfoInteger(g_Symbol, SYMBOL_DIGITS);
    string dirText = bearishBOSConfirmed ? "SELL" : "BUY";
    ENUM_ORDER_TYPE orderType = bearishBOSConfirmed ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;

    double sl = NormalizeDouble(fib100, symDigits);
    double tp = NormalizeDouble(fib0, symDigits);

    string message = "Grid Orders Placed\n\n";
    message += "Symbol: " + g_Symbol + "\n";
    message += "Direction: " + dirText + "\n";
    message += "Orders: " + IntegerToString(GridOrdersCount) + "\n\n";

    int ordersPlaced = 0;

    for(int i = 0; i < GridOrdersCount; i++)
    {
        double entryPrice = NormalizeDouble(gridOrders[i].price, symDigits);
        double lotSize = gridOrders[i].lotSize;

        if(lotSize <= 0)
            continue;

        // Place order using OrderSend (CTrade doesn't support comment)
        MqlTradeRequest request = {};
        MqlTradeResult result = {};

        request.action = TRADE_ACTION_PENDING;
        request.symbol = g_Symbol;
        request.volume = lotSize;
        request.type = orderType;
        request.price = entryPrice;
        request.sl = sl;
        request.tp = tp;
        request.deviation = 20;
        request.magic = MagicNumber;
        request.comment = TradeComment + "_Grid" + IntegerToString(i);
        request.type_time = ORDER_TIME_GTC;
        request.type_filling = ORDER_FILLING_IOC;

        if(OrderSend(request, result))
        {
            gridOrders[i].ticket = result.order;
            gridOrders[i].isPending = true;
            ordersPlaced++;

            message += "Order " + IntegerToString(i+1) + ": " + DoubleToString(lotSize, 2) + " @ " + DoubleToString(entryPrice, symDigits) + "\n";

            Print("Grid order ", i+1, " placed: ", lotSize, " @ ", entryPrice);
        }
        else
        {
            Print("Grid order ", i+1, " failed: ", GetLastError());
        }
    }

    dailyTrades++;

    message += "\nSL: " + DoubleToString(sl, symDigits) + "\n";
    message += "TP: " + DoubleToString(tp, symDigits) + "\n";
    message += "Total Risk: " + DoubleToString(RiskPercent, 1) + "%\n";
    message += "\nTime: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

    if(EnableTelegram && ordersPlaced > 0)
    {
        SendTelegram(message);
    }
}

//+------------------------------------------------------------------+
//| Check Grid Order Fills                                            |
//+------------------------------------------------------------------+
void CheckGridOrderFills()
{
    for(int i = 0; i < GridOrdersCount; i++)
    {
        if(gridOrders[i].isPending && gridOrders[i].ticket > 0)
        {
            // Check if order was filled (now a position)
            for(int j = PositionsTotal() - 1; j >= 0; j--)
            {
                if(positionInfo.SelectByIndex(j))
                {
                    if(positionInfo.Magic() == MagicNumber && positionInfo.Comment() == TradeComment + "_Grid" + IntegerToString(i))
                    {
                        gridOrders[i].isFilled = true;
                        gridOrders[i].isPending = false;
                        filledGridOrders++;
                        totalGridRisk += gridOrders[i].riskPercent;

                        Print("Grid order ", i+1, " filled @ ", positionInfo.PriceOpen());

                        if(EnableTelegram)
                        {
                            string msg = "Grid Order Filled\n\n";
                            msg += "Order: " + IntegerToString(i+1) + "/" + IntegerToString(GridOrdersCount) + "\n";
                            msg += "Entry: " + DoubleToString(positionInfo.PriceOpen(), (int)SymbolInfoInteger(g_Symbol, SYMBOL_DIGITS)) + "\n";
                            msg += "Filled: " + IntegerToString(filledGridOrders) + "/" + IntegerToString(GridOrdersCount) + "\n";
                            msg += "Risk Used: " + DoubleToString(totalGridRisk, 2) + "%";
                            SendTelegram(msg);
                        }
                        break;
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check Pending Order Status                                        |
//+------------------------------------------------------------------+
void CheckPendingOrder()
{
    if(!OrderSelect(pendingTicket))
    {
        // Order no longer exists (was triggered or cancelled)
        pendingTicket = 0;
        setupActive = false;
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

    double entryPrice = (fib62 + fib71) / 2;
    double slPips = MathAbs(entryPrice - fib100) / SymbolInfoDouble(g_Symbol, SYMBOL_POINT) / 10;
    double pipValue = SymbolInfoDouble(g_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = risk / (slPips * pipValue);

    // Normalize
    double minLot = SymbolInfoDouble(g_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(g_Symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(g_Symbol, SYMBOL_VOLUME_STEP);

    lotSize = MathFloor(lotSize / stepLot) * stepLot;
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

    return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Send Setup Notification                                           |
//+------------------------------------------------------------------+
void SendSetupNotification()
{
    if(!EnableTelegram)
        return;

    string dirText = bearishBOSConfirmed ? "BEARISH" : "BULLISH";

    int symDigits = (int)SymbolInfoInteger(g_Symbol, SYMBOL_DIGITS);

    string message = dirText + " BOS Detected\n\n";
    message += "Symbol: " + g_Symbol + "\n";
    message += "Direction: " + dirText + "\n";
    message += "\nFibonacci Levels:\n";
    message += "TP (0%): " + DoubleToString(fib0, symDigits) + "\n";
    message += "Entry: " + DoubleToString(fib62, symDigits) + " - " + DoubleToString(fib71, symDigits) + "\n";
    message += "SL (100%): " + DoubleToString(fib100, symDigits) + "\n";
    message += "\nGrid: " + (EnableGridOrders ? IntegerToString(GridOrdersCount) + " orders" : "Disabled") + "\n";
    message += "\nFilters:\n";
    message += "Imbalance: " + (EnableImbalance ? "YES" : "NO") + "\n";
    message += "Liq Sweep: " + (liquiditySweep ? "YES" : "NO") + "\n";
    message += "\nTime: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

    SendTelegram(message);
}

//+------------------------------------------------------------------+
//| Send Telegram Message                                             |
//+------------------------------------------------------------------+
bool SendTelegram(string message)
{
    if(TelegramBotToken == "" || TelegramChatID == "")
        return false;

    string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage";

    // URL encode the message
    string encodedMessage = URLEncode(message);

    string postData = "chat_id=" + TelegramChatID + "&text=" + encodedMessage + "&parse_mode=HTML";

    char data[];
    char result[];
    string resultHeaders;

    StringToCharArray(postData, data, 0, WHOLE_ARRAY, CP_UTF8);
    ArrayResize(data, ArraySize(data) - 1); // Remove null terminator

    int timeout = 5000;

    int res = WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n",
                         timeout, data, result, resultHeaders);

    if(res == -1)
    {
        int errorCode = GetLastError();
        Print("Telegram error: ", errorCode);
        Print("Make sure to add https://api.telegram.org to Tools > Options > Expert Advisors > Allow WebRequest");
        return false;
    }

    string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);

    if(StringFind(response, "\"ok\":true") >= 0)
    {
        Print("Telegram message sent");
        return true;
    }
    else
    {
        Print("Telegram failed: ", response);
        return false;
    }
}

//+------------------------------------------------------------------+
//| URL Encode Helper                                                 |
//+------------------------------------------------------------------+
string URLEncode(string text)
{
    string result = "";
    string hex = "0123456789ABCDEF";

    for(int i = 0; i < StringLen(text); i++)
    {
        ushort ch = StringGetCharacter(text, i);

        if((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
           (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' ||
           ch == '.' || ch == '~' || ch == ' ')
        {
            if(ch == ' ')
                result += "+";
            else
                result += CharToString((uchar)ch);
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
