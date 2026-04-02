//+------------------------------------------------------------------+
//|                                          Fibo71_CP2_Bot.mq5       |
//|                                    CP 2.0 Strategy - MT5 Bot      |
//|                                     Break of Structure + Fibo      |
//|                                        WITH GRID ORDERS           |
//+------------------------------------------------------------------+
#property copyright "Fibo71 Bot"
#property link      ""
#property version   "3.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - ORGANIZED BY FUNCTION                          |
//+------------------------------------------------------------------+

// ================================================================
//                    1. BASIC SETTINGS
// ================================================================
input group "========== 1. BASIC SETTINGS =========="

input string   TradeComment = "Fibo71 v3";           // Comment (visible in trade history)
input int      MagicNumber = 710071;                 // Magic Number (unique EA ID)
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;    // Timeframe (CURRENT = use chart TF)

// ================================================================
//                    2. RISK MANAGEMENT
// ================================================================
input group "========== 2. RISK MANAGEMENT =========="

input double   RiskPercent = 1.0;                    // Risk % per trade (of balance)
                                                     // 0 = DISABLED, use FixedLot instead
input double   FixedLot = 0.0;                       // Fixed lot size
                                                     // Only used when RiskPercent = 0

input int      MaxDailyTrades = 3;                   // Max trades per day
                                                     // 0 = DISABLED (unlimited)
input int      MaxOpenPositions = 2;                 // Max simultaneous positions
                                                     // 0 = DISABLED (unlimited)

// ================================================================
//                    3. FIBONACCI SETTINGS
// ================================================================
input group "========== 3. FIBONACCI LEVELS =========="

input double   FibEntryMin = 0.62;                   // Entry Zone START (62% = 0.62)
input double   FibEntryMax = 0.71;                   // Entry Zone END (71% = 0.71)
// Note: TP is at 0% (swing extreme in profit direction)
// Note: SL is at 100% (swing extreme in loss direction)

// ================================================================
//                    4. BOS DETECTION
// ================================================================
input group "========== 4. BOS DETECTION =========="

input int      BOSLookback = 50;                     // Swing point lookback (candles)
                                                     // Higher = more history analyzed
input int      SwingConfirmBars = 2;                 // Bars to confirm swing (each side)
                                                     // 2 = swing needs 2 higher/lower on each side

// ================================================================
//                    4a. ATR SETTINGS (for dynamic levels)
// ================================================================
input group "========== 4a. ATR SETTINGS =========="

input bool     UseATR = true;                        // [ON/OFF] Use ATR for dynamic calculations
input int      ATRPeriod = 14;                       // ATR Period (default 14)
input double   ATRMultiplierSL = 2.0;                // ATR multiplier for Stop Loss
                                                     // SL = Entry +/- (ATR * Multiplier)
                                                     // Ignored if UseATR = false

input bool     UseATRForImbalance = false;           // [ON/OFF] Use ATR for imbalance detection
                                                     // true = imbalance = ATR * MinImbalanceATR
                                                     // false = use fixed MinImbalancePips
input double   MinImbalanceATR = 1.5;                // Min imbalance in ATR multiples
                                                     // Ignored if UseATRForImbalance = false

input bool     UseATRForGrid = false;                // [ON/OFF] Use ATR for grid spacing
                                                     // true = grid spacing = ATR * GridATRSpacing
                                                     // false = use fibonacci spacing
input double   GridATRSpacing = 0.5;                // Grid spacing in ATR multiples

// ================================================================
//                    5. ENTRY FILTERS
//                    (Set to false to DISABLE each filter)
// ================================================================
input group "========== 5. ENTRY FILTERS =========="

// --- Imbalance Filter ---
input bool     FilterImbalance = true;               // [ON/OFF] Require imbalance
input double   MinImbalancePips = 10.0;              // Min imbalance size (pips)
                                                     // Ignored if FilterImbalance = false

// --- Liquidity Sweep Filter ---
input bool     FilterLiquiditySweep = true;          // [ON/OFF] Require liquidity sweep

// --- Spread Filter ---
input bool     FilterSpread = true;                  // [ON/OFF] Check max spread
input int      MaxSpreadPips = 10;                   // Max spread allowed (pips)
                                                     // Ignored if FilterSpread = false

// --- Trading Hours Filter ---
input bool     FilterTradingHours = true;            // [ON/OFF] Limit trading hours
input string   TradingHoursStart = "08:00";          // Trading start (HH:MM)
input string   TradingHoursEnd = "15:00";            // Trading end (HH:MM)
                                                     // Ignored if FilterTradingHours = false

// --- Consolidation Filter (ATR-based) ---
input bool     FilterConsolidation = true;            // [ON/OFF] Skip trading in ranging markets
input int      ConsolidationBars = 20;               // Bars to check for consolidation
input double   ConsolidationATRMultiplier = 1.5;     // If range < ATR * X = consolidation
                                                     // Example: ATR=50, Multiplier=1.5
                                                     // If (High-Low) < 75 pips = CONSOLIDATION

// --- Fake Breakout Filter (ATR-based) ---
input bool     FilterFakeBreakout = true;             // [ON/OFF] Detect weak/overextended BOS
input double   MinBreakoutATR = 0.5;                  // Min BOS candle range = ATR * X
                                                     // Range < ATR * 0.5 = FAKE (too weak)
input double   MaxBreakoutATR = 3.0;                  // Max BOS candle range = ATR * X
                                                     // Range > ATR * 3.0 = OVEREXTENDED (too strong)

// ================================================================
//                    6. GRID ORDERS
// ================================================================
input group "========== 6. GRID ORDERS =========="

input bool     EnableGridOrders = true;              // [ON/OFF] Enable grid entries
input int      GridOrdersCount = 5;                  // Number of grid orders (1-10)
input string   GridSpacingMode = "equal";            // equal = equal spacing
                                                     // fib = fibonacci spacing
input string   GridDistribution = "equal";           // equal = same lot size
                                                     // weighted = progressive lots

// ================================================================
//                    7. EXIT MANAGEMENT
// ================================================================
input group "========== 7. EXIT MANAGEMENT =========="

input bool     EnableDailyClose = true;              // [ON/OFF] Auto-close at time
input string   DailyCloseTime = "16:00";             // Daily close time (HH:MM)
                                                     // Ignored if EnableDailyClose = false

input double   PartialClosePercent = 50.0;           // Partial close at X% of TP
                                                     // 0 = DISABLED (no partial close)
                                                     // 50 = close 50% position at 50% to TP

// ================================================================
//                    8. TELEGRAM NOTIFICATIONS
// ================================================================
input group "========== 8. TELEGRAM =========="

input bool     EnableTelegram = false;               // [ON/OFF] Enable Telegram alerts
input string   TelegramBotToken = "";                // Bot Token (from @BotFather)
input string   TelegramChatID = "";                  // Chat ID (from @userinfobot)
input bool     SendFilterRejections = false;         // [ON/OFF] Send msg when setup rejected
                                                     // Shows why setup was rejected
// Both token AND chat ID required when EnableTelegram = true

// ================================================================
//                    9. DISPLAY - MAIN LINES
// ================================================================
input group "========== 9. DISPLAY - MAIN LINES =========="

input int      LineExtensionBars = 50;               // How far lines extend (bars)
input bool     ShowFibLines = true;                  // [ON/OFF] Show Fibonacci lines

// --- TP Line (0%) ---
input int      WidthTP = 2;                          // TP line width (0-5, 0 = invisible)
input color    ColorTP = clrLime;                    // TP line color
input ENUM_LINE_STYLE StyleTP = STYLE_SOLID;         // TP line style

// --- SL Line (100%) ---
input int      WidthSL = 2;                          // SL line width (0-5, 0 = invisible)
input color    ColorSL = clrRed;                     // SL line color
input ENUM_LINE_STYLE StyleSL = STYLE_SOLID;         // SL line style

// ================================================================
//                    10. DISPLAY - ENTRY ZONE
// ================================================================
input group "========== 10. DISPLAY - ENTRY ZONE =========="

input bool     ShowEntryZone = true;                 // [ON/OFF] Show entry zone rectangle

// --- Entry Lines (62%, 71%) ---
input int      WidthEntry = 2;                       // Entry lines width (0-5)
input color    ColorEntry = clrDodgerBlue;           // Entry lines color
input ENUM_LINE_STYLE StyleEntry = STYLE_SOLID;      // Entry lines style

// --- Entry Zone Background ---
input color    ColorZoneLong = clrLightGreen;        // LONG zone background
input color    ColorZoneShort = clrLightCoral;       // SHORT zone background
input int      ZoneOpacity = 70;                     // Zone opacity (0-100%)
                                                     // 0 = transparent, 100 = solid

// ================================================================
//                    11. DISPLAY - OTHER FIB LEVELS
// ================================================================
input group "========== 11. DISPLAY - OTHER FIB LEVELS =========="

input bool     ShowOtherFibs = true;                 // [ON/OFF] Show 38.2% and 50% lines

// --- 38.2% Level ---
input int      WidthFib38 = 1;                       // 38.2% line width (0-5)
input color    ColorFib38 = clrGray;                 // 38.2% line color

// --- 50% Level ---
input int      WidthFib50 = 1;                       // 50% line width (0-5)
input color    ColorFib50 = clrGray;                 // 50% line color

input ENUM_LINE_STYLE StyleFib = STYLE_DASH;         // Other fib lines style

// ================================================================
//                    12. DISPLAY - LABELS
// ================================================================
input group "========== 12. DISPLAY - LABELS =========="

input bool     ShowLabels = true;                    // [ON/OFF] Show text labels
input bool     ShowSwingPoints = true;               // [ON/OFF] Show HH/LL arrows
input int      LabelFontSize = 9;                    // Label font size

// ================================================================
//                    13. STATISTICS
// ================================================================
input group "========== 13. STATISTICS =========="

input bool     EnableMonthlyStats = true;            // [ON/OFF] Track monthly stats
input bool     EnableLast10Stats = true;             // [ON/OFF] Track last 10 trades

//+------------------------------------------------------------------+
//| GRID ORDER STRUCTURE                                              |
//+------------------------------------------------------------------+
struct GridOrderStruct
{
    double fibLevel;
    double price;
    double riskPercent;
    double lotSize;
    ulong  ticket;
    bool   isFilled;
    bool   isPending;
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;

// ATR Indicator Handle
int atrHandle = INVALID_HANDLE;
double atrBuffer[];

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

// Filter status
bool isConsolidation = false;
bool isFakeBreakout = false;

// Fibonacci levels
double fib0 = 0;     // TP
double fib38 = 0;    // 38.2%
double fib50 = 0;    // 50%
double fib62 = 0;    // Entry zone start
double fib71 = 0;    // Entry zone end
double fib100 = 0;   // SL

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

    // Initialize ATR indicator if enabled
    if(UseATR || UseATRForImbalance || UseATRForGrid)
    {
        atrHandle = iATR(g_Symbol, Period(), ATRPeriod);
        if(atrHandle == INVALID_HANDLE)
        {
            Print("ERROR: Failed to create ATR indicator");
            return INIT_FAILED;
        }
        ArraySetAsSeries(atrBuffer, true);
        Print("ATR initialized: Period=", ATRPeriod);
    }

    // Initialize grid orders array
    ArrayResize(gridOrders, GridOrdersCount);
    ResetGridOrders();

    // Check Telegram
    if(EnableTelegram && (TelegramBotToken == "" || TelegramChatID == ""))
    {
        Print("WARNING: Telegram enabled but credentials missing");
    }

    Print("========================================");
    Print("Fibo 71 Bot - CP 2.0 Strategy v3.10");
    Print("========================================");
    Print("Symbol: ", g_Symbol, " | Timeframe: ", EnumToString(chartTF));
    Print("Risk: ", RiskPercent, "% | Entry Zone: ", FibEntryMin * 100, "% - ", FibEntryMax * 100, "%");
    Print("Grid Orders: ", EnableGridOrders ? IntegerToString(GridOrdersCount) + " orders" : "Disabled");
    Print("Filters:");
    Print("  - Imbalance: ", FilterImbalance ? "ON" : "OFF");
    Print("  - Liquidity Sweep: ", FilterLiquiditySweep ? "ON" : "OFF");
    Print("  - Spread: ", FilterSpread ? "ON (max " + IntegerToString(MaxSpreadPips) + " pips)" : "OFF");
    Print("  - Trading Hours: ", FilterTradingHours ? TradingHoursStart + "-" + TradingHoursEnd : "OFF");
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
    // Reset
    swingHigh = 0;
    swingLow = 0;
    swingHighIdx = 0;
    swingLowIdx = 0;

    int confirmBars = SwingConfirmBars;

    // Look for swing high (higher than N candles on each side)
    for(int i = confirmBars; i < BOSLookback - confirmBars; i++)
    {
        double h = iHigh(g_Symbol, Period(), i);
        bool isSwingHigh = true;

        // Check N bars on each side
        for(int j = 1; j <= confirmBars; j++)
        {
            if(h <= iHigh(g_Symbol, Period(), i - j) ||
               h <= iHigh(g_Symbol, Period(), i + j))
            {
                isSwingHigh = false;
                break;
            }
        }

        if(isSwingHigh)
        {
            swingHigh = h;
            swingHighIdx = i;
            break;  // Found most recent swing high
        }
    }

    // Look for swing low (lower than N candles on each side)
    for(int i = confirmBars; i < BOSLookback - confirmBars; i++)
    {
        double lo = iLow(g_Symbol, Period(), i);
        bool isSwingLow = true;

        // Check N bars on each side
        for(int j = 1; j <= confirmBars; j++)
        {
            if(lo >= iLow(g_Symbol, Period(), i - j) ||
               lo >= iLow(g_Symbol, Period(), i + j))
            {
                isSwingLow = false;
                break;
            }
        }

        if(isSwingLow)
        {
            swingLow = lo;
            swingLowIdx = i;
            break;  // Found most recent swing low
        }
    }
}

//+------------------------------------------------------------------+
//| Find Next Swing Point Time - for dynamic zone extension          |
//| Returns time of next swing point after current setup              |
//+------------------------------------------------------------------+
datetime FindNextSwingPointTime(bool isShortSetup)
{
    // For SHORT setup: find next swing HIGH (zone extends until next HH)
    // For LONG setup: find next swing LOW (zone extends until next LL)

    int bars = iBars(g_Symbol, Period());
    if(bars < 5)
        return 0;

    // Start from bar 1 (current candle) and look for swing point
    int confirmBars = SwingConfirmBars;
    if(confirmBars < 2)
        confirmBars = 2;

    if(isShortSetup)
    {
        // Find next swing HIGH (higher than N bars on each side)
        for(int i = 1; i < bars - confirmBars; i++)
        {
            double h = iHigh(g_Symbol, Period(), i);

            // Check if this is a swing high
            bool isSwingHigh = true;
            for(int j = 1; j <= confirmBars; j++)
            {
                if(iHigh(g_Symbol, Period(), i + j) >= h || iHigh(g_Symbol, Period(), i - j) >= h)
                {
                    isSwingHigh = false;
                    break;
                }
            }

            if(isSwingHigh)
            {
                // Found next swing high - return its time
                return iTime(g_Symbol, Period(), i);
            }
        }
    }
    else
    {
        // Find next swing LOW (lower than N bars on each side)
        for(int i = 1; i < bars - confirmBars; i++)
        {
            double l = iLow(g_Symbol, Period(), i);

            // Check if this is a swing low
            bool isSwingLow = true;
            for(int j = 1; j <= confirmBars; j++)
            {
                if(iLow(g_Symbol, Period(), i + j) <= l || iLow(g_Symbol, Period(), i - j) <= l)
                {
                    isSwingLow = false;
                    break;
                }
            }

            if(isSwingLow)
            {
                // Found next swing low - return its time
                return iTime(g_Symbol, Period(), i);
            }
        }
    }

    // No next swing point found
    return 0;
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
//| Check All Filters - Imbalance, LiqSweep, Consolidation, FakeBOS   |
//+------------------------------------------------------------------+
void CheckFilters()
{
    bullishBOSConfirmed = false;
    bearishBOSConfirmed = false;
    liquiditySweep = false;
    isConsolidation = false;
    isFakeBreakout = false;

    // ========================================
    // 1. CONSOLIDATION FILTER (check first)
    // ========================================
    if(FilterConsolidation)
    {
        isConsolidation = IsConsolidation();
        if(isConsolidation)
        {
            Print("FILTER: Market is CONSOLIDATING - skipping");
            return;  // Reject immediately
        }
    }

    // ========================================
    // 2. FAKE/OVEREXTENDED BREAKOUT FILTER
    // ========================================
    if(FilterFakeBreakout)
    {
        isFakeBreakout = IsFakeBreakout();
        if(isFakeBreakout)
        {
            Print("FILTER: FAKE or OVEREXTENDED breakout - skipping");
            return;  // Reject immediately
        }
    }

    // ========================================
    // 3. IMBALANCE FILTER
    // ========================================
    double minImbalancePrice = GetMinImbalance();

    if(FilterImbalance)
    {
        double low2 = iLow(g_Symbol, Period(), 2);
        double high0 = iHigh(g_Symbol, Period(), 0);
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
        else
        {
            Print("FILTER: No IMBALANCE detected (", DoubleToString(minImbalancePrice, _Digits), ")");
            return;
        }
    }
    else
    {
        bullishBOSConfirmed = bullishBOS;
        bearishBOSConfirmed = bearishBOS;
    }

    // ========================================
    // 4. LIQUIDITY SWEEP FILTER
    // ========================================
    if(FilterLiquiditySweep && (bullishBOSConfirmed || bearishBOSConfirmed))
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

        if(!liquiditySweep)
        {
            Print("FILTER: No LIQUIDITY SWEEP detected");
            bullishBOSConfirmed = false;
            bearishBOSConfirmed = false;
            return;
        }
    }

    // All filters passed!
    if(bullishBOSConfirmed || bearishBOSConfirmed)
    {
        string dir = bullishBOSConfirmed ? "BULLISH" : "BEARISH";
        Print(">>> ALL FILTERS PASSED! ", dir, " BOS CONFIRMED <<<");
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
        fib0 = swingLow;                           // TP
        fib100 = swingHigh;                        // SL
        double range = swingHigh - swingLow;
        fib38 = swingLow + range * 0.382;
        fib50 = swingLow + range * 0.5;
        fib62 = swingLow + range * FibEntryMin;
        fib71 = swingLow + range * FibEntryMax;

        // Use ATR for SL if enabled
        if(UseATR)
        {
            double atr = GetATR();
            if(atr > 0)
            {
                fib100 = fib62 + (atr * ATRMultiplierSL);  // SL = Entry + ATR * multiplier
            }
        }
    }
    else if(bullishBOSConfirmed)
    {
        // Bullish: swingLow is start (100%), swingHigh is end (0%)
        fib0 = swingHigh;                          // TP
        fib100 = swingLow;                         // SL
        double range = swingHigh - swingLow;
        fib38 = swingHigh - range * 0.382;
        fib50 = swingHigh - range * 0.5;
        fib62 = swingHigh - range * FibEntryMin;
        fib71 = swingHigh - range * FibEntryMax;

        // Use ATR for SL if enabled
        if(UseATR)
        {
            double atr = GetATR();
            if(atr > 0)
            {
                fib100 = fib71 - (atr * ATRMultiplierSL);  // SL = Entry - ATR * multiplier
            }
        }
    }

    // Calculate grid order levels if enabled
    if(EnableGridOrders)
    {
        CalculateGridLevels();
    }
}

//+------------------------------------------------------------------+
//| Get Current ATR Value                                             |
//+------------------------------------------------------------------+
double GetATR()
{
    if(atrHandle == INVALID_HANDLE)
        return 0;

    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) <= 0)
        return 0;

    return atrBuffer[0];
}

//+------------------------------------------------------------------+
//| Get Min Imbalance (ATR or Fixed)                                  |
//+------------------------------------------------------------------+
double GetMinImbalance()
{
    if(UseATRForImbalance)
    {
        double atr = GetATR();
        return atr * MinImbalanceATR;
    }
    else
    {
        return MinImbalancePips * SymbolInfoDouble(g_Symbol, SYMBOL_POINT) * 10;
    }
}

//+------------------------------------------------------------------+
//| Check for Consolidation (Ranging Market)                          |
//+------------------------------------------------------------------+
bool IsConsolidation()
{
    if(!FilterConsolidation)
        return false;  // Filter disabled = not consolidation

    double atr = GetATR();
    if(atr <= 0)
        return false;

    // Find highest high and lowest low over consolidation bars
    double highestHigh = 0;
    double lowestLow = DBL_MAX;

    for(int i = 1; i <= ConsolidationBars; i++)
    {
        double h = iHigh(g_Symbol, Period(), i);
        double l = iLow(g_Symbol, Period(), i);

        if(h > highestHigh)
            highestHigh = h;
        if(l < lowestLow)
            lowestLow = l;
    }

    // Calculate range
    double range = highestHigh - lowestLow;
    double maxConsolidationRange = atr * ConsolidationATRMultiplier;

    // If range < ATR * multiplier = CONSOLIDATION (ranging)
    if(range < maxConsolidationRange)
    {
        Print("CONSOLIDATION detected: Range=", DoubleToString(range, _Digits),
              " < ATR*", ConsolidationATRMultiplier, " (", DoubleToString(maxConsolidationRange, _Digits), ")");
        return true;  // IS consolidation
    }

    return false;  // NOT consolidation
}

//+------------------------------------------------------------------+
//| Check for Fake Breakout                                          |
//+------------------------------------------------------------------+
bool IsFakeBreakout()
{
    if(!FilterFakeBreakout)
        return false;  // Filter disabled = not fake

    double atr = GetATR();
    if(atr <= 0)
        return false;

    // Get BOS candle range
    double bosHigh = iHigh(g_Symbol, Period(), 0);
    double bosLow = iLow(g_Symbol, Period(), 0);
    double bosRange = bosHigh - bosLow;

    double minBreakoutRange = atr * MinBreakoutATR;
    double maxBreakoutRange = atr * MaxBreakoutATR;

    // Check if too WEAK (fake breakout)
    if(bosRange < minBreakoutRange)
    {
        Print("FAKE BREAKOUT (too weak): Range=", DoubleToString(bosRange, _Digits),
              " < ATR*", MinBreakoutATR, " (", DoubleToString(minBreakoutRange, _Digits), ")");
        return true;
    }

    // Check if too STRONG (overextended)
    if(bosRange > maxBreakoutRange)
    {
        Print("OVEREXTENDED BREAKOUT (too strong): Range=", DoubleToString(bosRange, _Digits),
              " > ATR*", MaxBreakoutATR, " (", DoubleToString(maxBreakoutRange, _Digits), ")");
        return true;
    }

    // Real breakout (between min and max)
    Print("REAL BREAKOUT confirmed: Range=", DoubleToString(bosRange, _Digits),
          " (ATR*", MinBreakoutATR, "-", MaxBreakoutATR, ")");
    return false;
}

//+------------------------------------------------------------------+
//| Calculate Grid Order Levels                                       |
//+------------------------------------------------------------------+
void CalculateGridLevels()
{
    double fibRange = MathAbs(fib100 - fib0);

    // Distribute risk across orders
    double riskPerOrder = RiskPercent / GridOrdersCount;
    if(GridDistribution == "weighted")
    {
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
            double fibLevels[] = {0.382, 0.5, 0.618, 0.65, 0.70, 0.786};
            if(i < ArraySize(fibLevels))
                level = fibLevels[i];
            else
                level = FibEntryMin + (FibEntryMax - FibEntryMin) * i / (GridOrdersCount - 1);
        }
        else
        {
            level = FibEntryMin + (FibEntryMax - FibEntryMin) * i / (GridOrdersCount - 1);
        }

        gridOrders[i].fibLevel = level;

        // Calculate price from fib level
        if(bearishBOSConfirmed)
            gridOrders[i].price = fib0 + fibRange * level;
        else
            gridOrders[i].price = fib100 + fibRange * (1 - level);

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

    double entryPrice = (fib62 + fib71) / 2;
    double slPips = MathAbs(entryPrice - fib100) / SymbolInfoDouble(g_Symbol, SYMBOL_POINT) / 10;
    double pipValue = SymbolInfoDouble(g_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = risk / (slPips * pipValue);

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

    int symDigits = (int)SymbolInfoInteger(g_Symbol, SYMBOL_DIGITS);
    datetime bosTime = iTime(g_Symbol, Period(), bosBarIdx);
    datetime timeEnd = bosTime + PeriodSeconds(Period()) * LineExtensionBars;

    // --- DYNAMIC ZONE EXTENSION ---
    // For entry zone: extend until next swing point (not just fixed bars)
    datetime zoneTimeEnd = timeEnd;  // Default to static extension

    bool isShortSetup = bearishBOSConfirmed;
    datetime nextSwingTime = FindNextSwingPointTime(isShortSetup);

    if(nextSwingTime > 0 && nextSwingTime > bosTime)
    {
        // Found next swing point - use it as zone end time
        zoneTimeEnd = nextSwingTime;
        Print("Zone extends to next swing point: ", TimeToString(zoneTimeEnd, TIME_DATE|TIME_MINUTES));
    }

    // --- ENTRY ZONE RECTANGLE ---
    if(ShowEntryZone)
    {
        double zoneTop = MathMax(fib62, fib71);
        double zoneBottom = MathMin(fib62, fib71);
        color zoneColor = bullishBOSConfirmed ? ColorZoneLong : ColorZoneShort;

        string zoneName = prefix + "EntryZone";
        // Use dynamic zoneTimeEnd for entry zone (extends to next swing point)
        ObjectCreate(0, zoneName, OBJ_RECTANGLE, 0, bosTime, zoneTop, zoneTimeEnd, zoneBottom);

        // Calculate alpha from opacity
        int alpha = 255 - (int)(255.0 * ZoneOpacity / 100.0);
        ObjectSetInteger(0, zoneName, OBJPROP_COLOR, ColorToARGB(zoneColor, (uchar)alpha));
        ObjectSetInteger(0, zoneName, OBJPROP_FILL, true);
        ObjectSetInteger(0, zoneName, OBJPROP_BACK, true);
        ObjectSetInteger(0, zoneName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, zoneName, OBJPROP_WIDTH, 1);
        ObjectSetString(0, zoneName, OBJPROP_TOOLTIP,
            "Entry Zone: " + DoubleToString(zoneBottom, symDigits) + " - " + DoubleToString(zoneTop, symDigits));
    }

    // --- TP LINE (0%) ---
    CreateTrendLine(prefix + "Fib_0", bosTime, fib0, timeEnd, fib0, ColorTP, WidthTP, "0% (TP)");

    // --- 38.2% LINE ---
    if(ShowOtherFibs && WidthFib38 > 0)
        CreateTrendLine(prefix + "Fib_38", bosTime, fib38, timeEnd, fib38, ColorFib38, WidthFib38, "38.2%");

    // --- 50% LINE ---
    if(ShowOtherFibs && WidthFib50 > 0)
        CreateTrendLine(prefix + "Fib_50", bosTime, fib50, timeEnd, fib50, ColorFib50, WidthFib50, "50%");

    // --- 62% LINE (Entry start) ---
    CreateTrendLine(prefix + "Fib_62", bosTime, fib62, zoneTimeEnd, fib62, ColorEntry, WidthEntry, "62%");

    // --- 71% LINE (Entry end) ---
    CreateTrendLine(prefix + "Fib_71", bosTime, fib71, zoneTimeEnd, fib71, ColorEntry, WidthEntry, "71%");

    // --- SL LINE (100%) ---
    CreateTrendLine(prefix + "Fib_100", bosTime, fib100, timeEnd, fib100, ColorSL, WidthSL, "100% (SL)");

    // --- SWING POINTS ---
    if(ShowSwingPoints)
    {
        // Swing High
        if(swingHigh > 0)
        {
            datetime swingHighTime = iTime(g_Symbol, Period(), swingHighIdx);

            string arrowName = prefix + "SwingHigh_Arrow";
            ObjectCreate(0, arrowName, OBJ_ARROW_DOWN, 0, swingHighTime, swingHigh);
            ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);

            if(ShowLabels)
            {
                string textName = prefix + "SwingHigh_Text";
                ObjectCreate(0, textName, OBJ_TEXT, 0, swingHighTime, swingHigh);
                ObjectSetString(0, textName, OBJPROP_TEXT, "HH");
                ObjectSetInteger(0, textName, OBJPROP_COLOR, clrRed);
                ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, LabelFontSize);
            }
        }

        // Swing Low
        if(swingLow > 0)
        {
            datetime swingLowTime = iTime(g_Symbol, Period(), swingLowIdx);

            string arrowName = prefix + "SwingLow_Arrow";
            ObjectCreate(0, arrowName, OBJ_ARROW_UP, 0, swingLowTime, swingLow);
            ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrGreen);
            ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);

            if(ShowLabels)
            {
                string textName = prefix + "SwingLow_Text";
                ObjectCreate(0, textName, OBJ_TEXT, 0, swingLowTime, swingLow);
                ObjectSetString(0, textName, OBJPROP_TEXT, "LL");
                ObjectSetInteger(0, textName, OBJPROP_COLOR, clrGreen);
                ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, LabelFontSize);
            }
        }
    }

    // --- BOS LABEL ---
    if(ShowLabels && (bullishBOSConfirmed || bearishBOSConfirmed))
    {
        string bosText = bullishBOSConfirmed ? "BULLISH BOS" : "BEARISH BOS";
        color bosColor = bullishBOSConfirmed ? clrGreen : clrRed;

        string bosLabel = prefix + "BOS_Label";
        ObjectCreate(0, bosLabel, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, bosLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, bosLabel, OBJPROP_XDISTANCE, 20);
        ObjectSetInteger(0, bosLabel, OBJPROP_YDISTANCE, 30);
        ObjectSetString(0, bosLabel, OBJPROP_TEXT, bosText);
        ObjectSetInteger(0, bosLabel, OBJPROP_COLOR, bosColor);
        ObjectSetInteger(0, bosLabel, OBJPROP_FONTSIZE, 14);
        ObjectSetString(0, bosLabel, OBJPROP_FONT, "Arial Bold");
    }

    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Create Horizontal Line with Label                                 |
//+------------------------------------------------------------------+
bool CreateHLineWithLabel(string name, double price, color clr, int width, ENUM_LINE_STYLE style, string labelText, datetime labelTime)
{
    int symDigits = (int)SymbolInfoInteger(g_Symbol, SYMBOL_DIGITS);

    // Create the horizontal line
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

    ObjectSetDouble(0, name, OBJPROP_PRICE, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetString(0, name, OBJPROP_TOOLTIP, labelText + ": " + DoubleToString(price, symDigits));

    // Create text label
    if(ShowLabels)
    {
        string textName = name + "_Text";
        if(ObjectFind(0, textName) < 0)
            ObjectCreate(0, textName, OBJ_TEXT, 0, labelTime, price);

        ObjectSetString(0, textName, OBJPROP_TEXT, labelText);
        ObjectSetInteger(0, textName, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, LabelFontSize);
        ObjectSetString(0, textName, OBJPROP_FONT, "Arial");
    }

    return true;
}

//+------------------------------------------------------------------+
//| Create Trend Line (horizontal segment)                            |
//+------------------------------------------------------------------+
bool CreateTrendLine(string name, datetime time1, double price1, datetime time2, double price2, color clr, int width, string labelText)
{
    int symDigits = (int)SymbolInfoInteger(g_Symbol, SYMBOL_DIGITS);

    // Create the trend line (horizontal segment)
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price2);

    ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price1);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price2);
    ObjectSetInteger(0, name, OBJPROP_TIME, 0, time1);
    ObjectSetInteger(0, name, OBJPROP_TIME, 1, time2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetString(0, name, OBJPROP_TEXT, labelText);
    ObjectSetString(0, name, OBJPROP_TOOLTIP, labelText + ": " + DoubleToString(price1, symDigits));

    return true;
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
    double zoneTop = MathMax(fib62, fib71);
    double zoneBottom = MathMin(fib62, fib71);

    inEntryZone = (currentPrice >= zoneBottom && currentPrice <= zoneTop);

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
    if(MaxDailyTrades > 0 && dailyTrades >= MaxDailyTrades)
        return false;

    // Check open positions
    if(MaxOpenPositions > 0)
    {
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
    }

    // Check spread filter
    if(FilterSpread && MaxSpreadPips > 0)
    {
        double spread = SymbolInfoInteger(g_Symbol, SYMBOL_SPREAD) / 10.0;
        if(spread > MaxSpreadPips)
            return false;
    }

    // Check trading hours filter
    if(FilterTradingHours)
    {
        MqlDateTime dt;
        TimeCurrent(dt);
        int currentMinutes = dt.hour * 60 + dt.min;

        int startHour = (int)StringToInteger(StringSubstr(TradingHoursStart, 0, 2));
        int startMin = (int)StringToInteger(StringSubstr(TradingHoursStart, 3, 2));
        int startMinutes = startHour * 60 + startMin;

        int endHour = (int)StringToInteger(StringSubstr(TradingHoursEnd, 0, 2));
        int endMin = (int)StringToInteger(StringSubstr(TradingHoursEnd, 3, 2));
        int endMinutes = endHour * 60 + endMin;

        if(currentMinutes < startMinutes || currentMinutes >= endMinutes)
            return false;
    }

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
        entryPrice = (fib62 + fib71) / 2;
        sl = fib100;
        tp = fib0;
    }
    else if(bullishBOSConfirmed)
    {
        orderType = ORDER_TYPE_BUY_LIMIT;
        entryPrice = (fib62 + fib71) / 2;
        sl = fib100;
        tp = fib0;
    }
    else
    {
        return;
    }

    int symDigits = (int)SymbolInfoInteger(g_Symbol, SYMBOL_DIGITS);

    entryPrice = NormalizeDouble(entryPrice, symDigits);
    sl = NormalizeDouble(sl, symDigits);
    tp = NormalizeDouble(tp, symDigits);

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

        string dirText = bearishBOSConfirmed ? "SELL LIMIT" : "BUY LIMIT";
        Print("Order placed: ", dirText, " ", lotSize, " @ ", entryPrice);
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
    ENUM_ORDER_TYPE orderType = bearishBOSConfirmed ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;

    double sl = NormalizeDouble(fib100, symDigits);
    double tp = NormalizeDouble(fib0, symDigits);

    int ordersPlaced = 0;

    for(int i = 0; i < GridOrdersCount; i++)
    {
        double entryPrice = NormalizeDouble(gridOrders[i].price, symDigits);
        double lotSize = gridOrders[i].lotSize;

        if(lotSize <= 0)
            continue;

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
            Print("Grid order ", i+1, " placed: ", lotSize, " @ ", entryPrice);
        }
        else
        {
            Print("Grid order ", i+1, " failed: ", GetLastError());
        }
    }

    if(ordersPlaced > 0)
        dailyTrades++;
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
            for(int j = PositionsTotal() - 1; j >= 0; j--)
            {
                if(positionInfo.SelectByIndex(j))
                {
                    if(positionInfo.Magic() == MagicNumber &&
                       positionInfo.Comment() == TradeComment + "_Grid" + IntegerToString(i))
                    {
                        gridOrders[i].isFilled = true;
                        gridOrders[i].isPending = false;
                        filledGridOrders++;
                        totalGridRisk += gridOrders[i].riskPercent;

                        Print("Grid order ", i+1, " filled @ ", positionInfo.PriceOpen());
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
    // Use fixed lot if RiskPercent is 0
    if(RiskPercent <= 0 && FixedLot > 0)
        return FixedLot;

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk = RiskPercent / 100.0 * balance;

    double entryPrice = (fib62 + fib71) / 2;
    double slPips = MathAbs(entryPrice - fib100) / SymbolInfoDouble(g_Symbol, SYMBOL_POINT) / 10;
    double pipValue = SymbolInfoDouble(g_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = risk / (slPips * pipValue);

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
    string dirEmoji = bearishBOSConfirmed ? "🔴" : "🟢";
    int symDigits = (int)SymbolInfoInteger(g_Symbol, SYMBOL_DIGITS);
    double atr = GetATR();

    string message = dirEmoji + " " + dirText + " BOS CONFIRMED\n\n";
    message += "━━━━━━━━━━━━━━━━━━━━\n";
    message += "Symbol: " + g_Symbol + "\n";
    message += "Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\n";
    message += "━━━━━━━━━━━━━━━━━━━━\n\n";

    // Fibonacci Levels
    message += "📊 FIBONACCI LEVELS:\n";
    message += "TP (0%): " + DoubleToString(fib0, symDigits) + "\n";
    message += "Entry Zone:\n";
    message += "  62%: " + DoubleToString(fib62, symDigits) + "\n";
    message += "  71%: " + DoubleToString(fib71, symDigits) + "\n";
    message += "SL (100%): " + DoubleToString(fib100, symDigits) + "\n\n";

    // ATR Info
    if(UseATR)
    {
        message += "📈 ATR INFO:\n";
        message += "ATR(" + IntegerToString(ATRPeriod) + "): " + DoubleToString(atr, symDigits) + "\n";
        if(UseATR)
            message += "SL Distance: ATR × " + DoubleToString(ATRMultiplierSL, 1) + "\n";
        message += "\n";
    }

    // Filter Status
    message += "🔍 FILTER STATUS:\n";
    message += "Imbalance: ";
    message += FilterImbalance ? "✅ PASS" : "⚪ OFF";
    message += "\n";

    message += "Liq Sweep: ";
    if(!FilterLiquiditySweep)
        message += "⚪ OFF";
    else if(liquiditySweep)
        message += "✅ PASS";
    else
        message += "❌ FAIL";
    message += "\n";

    message += "Consolidation: ";
    if(!FilterConsolidation)
        message += "⚪ OFF";
    else if(isConsolidation)
        message += "❌ CONSOLIDATION";
    else
        message += "✅ TRENDING";
    message += "\n";

    message += "Fake BO: ";
    if(!FilterFakeBreakout)
        message += "⚪ OFF";
    else if(isFakeBreakout)
        message += "❌ FAKE/OVER";
    else
        message += "✅ REAL";
    message += "\n\n";

    // Grid info
    if(EnableGridOrders)
    {
        message += "📐 GRID ORDERS: " + IntegerToString(GridOrdersCount) + " orders\n";
        message += "Risk Total: " + DoubleToString(RiskPercent, 1) + "%\n";
    }
    else
    {
        message += "📐 SINGLE ORDER\n";
        message += "Risk: " + DoubleToString(RiskPercent, 1) + "%\n";
    }

    SendTelegram(message);
}

//+------------------------------------------------------------------+
//| Send Filter Rejection Notification                                |
//+------------------------------------------------------------------+
void SendFilterRejectionNotification(string filterName, string reason)
{
    if(!EnableTelegram || !SendFilterRejections)
        return;

    string message = "⚠️ SETUP REJECTED\n\n";
    message += "━━━━━━━━━━━━━━━━━━━━\n";
    message += "Symbol: " + g_Symbol + "\n";
    message += "Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\n";
    message += "━━━━━━━━━━━━━━━━━━━━\n\n";
    message += "Filter: " + filterName + "\n";
    message += "Reason: " + reason + "\n\n";

    double atr = GetATR();
    if(atr > 0)
    {
        message += "ATR: " + DoubleToString(atr, (int)SymbolInfoInteger(g_Symbol, SYMBOL_DIGITS)) + "\n";
    }

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
    string encodedMessage = URLEncode(message);
    string postData = "chat_id=" + TelegramChatID + "&text=" + encodedMessage + "&parse_mode=HTML";

    char data[];
    char result[];
    string resultHeaders;

    StringToCharArray(postData, data, 0, WHOLE_ARRAY, CP_UTF8);
    ArrayResize(data, ArraySize(data) - 1);

    int timeout = 5000;
    int res = WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n",
                         timeout, data, result, resultHeaders);

    if(res == -1)
    {
        int errorCode = GetLastError();
        Print("Telegram error: ", errorCode);
        Print("Add https://api.telegram.org to Tools > Options > Expert Advisors > Allow WebRequest");
        return false;
    }

    string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
    if(StringFind(response, "\"ok\":true") >= 0)
    {
        Print("Telegram message sent");
        return true;
    }

    Print("Telegram failed: ", response);
    return false;
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
