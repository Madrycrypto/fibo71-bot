//+------------------------------------------------------------------+
//|                                          Fibo71_CP2_Bot.mq5          |
//|                                    CP 2.0 Strategy - MT5 Bot               |
//|                                     Break of Structure + Fibo               |
//+------------------------------------------------------------------+
#property copyright "Fibo71 Bot"
#property link      ""
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

// Basic Settings
input string   Section1 = "═════════ Basic Settings ════════";
input string   Symbol = "AUDUSD";                    // Trading Symbol
input ENUM_TIMEFRAMES Timeframe = PERIOD_H1;         // Trading Timeframe
input int      MagicNumber = 710071;                 // Magic Number
input string   TradeComment = "Fibo71 CP2.0";        // Trade Comment

input double   RiskPercent = 1.0;                    // Risk per trade (%)
input double   CorrelatedRiskPercent = 0.5;          // Risk on correlated pairs (%)
input int      MaxDailyTrades = 3;                   // Max trades per day
input int      MaxOpenPositions = 2;                 // Max simultaneous positions

input int      MaxSpreadPips = 10;                // Max spread (pips)

// Fibonacci Settings
input string   Section2 = "═════════ Fibonacci Settings ════════";
input double   FibEntryMin = 0.71;                   // Fib Entry Min (default 71%)
input double   FibEntryMax = 0.79;                   // Fib Entry Max (default 79%)
input double   FibTP = 1.0;                          // Fib TP Level (0%)
input double   FibSL = 1.0;                          // Fib SL Level (100%)

// BOS Detection
input string   Section3 = "═════════ BOS Detection ════════";
input int      BOSLookback = 50;                     // BOS Lookback Period
input double   MinImbalancePips = 10.0;              // Min Imbalance (pips)

// Filters
input string   Section4 = "═════════ Filters ════════";
input bool     EnableImbalance = true;               // Require Imbalance filter
input bool     EnableLiquiditySweep = true;          // Require Liquidity Sweep filter
input string   TradingHoursStart = "08:00";          // Trading Hours Start
input string   TradingHoursEnd = "15:00";            // Trading Hours End

input bool     EnableDailyClose = true;                 // Enable Daily Auto-Close
input string   DailyCloseTime = "16:00";          // Daily Close Time (HH:MM)
input double   PartialClosePercent = 50.0;         // Partial Close at % of profit

// Telegram Settings
input string   Section5 = "═════════ Telegram Settings ════════";
input bool     EnableTelegram = true;                // Enable Telegram
input string   TelegramBotToken = "";                // Bot Token (from @BotFather)
input string   TelegramChatID = "";                  // Chat ID (from @userinfobot)

// Display Settings
input string   Section6 = "════════ Display Settings ════════";
input bool     ShowFibLines = true;                  // Show Fibonacci Lines
input bool     ShowLabels = true;                    // Show Labels on Chart
input color    ColorBullish = clrGreen;              // Bullish Color
input color    ColorBearish = clrRed;                // Bearish Color
input color    ColorTP = clrLime;                    // TP Line Color
input color    ColorSL = clrRed;                     // SL Line Color
input color    ColorEntry = clrBlue;                 // Entry Zone Color

// Performance tracking
input string   Section7 = "════════ Performance Tracking ════════";
input bool     EnableMonthlyStats = true;              // Enable Monthly Statistics
input bool     EnableLast10Stats = true;             // Enable Last 10 Trades Stats

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;

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
double fib71 = 1;    // Entry zone start
double fib75 = 1;    // Entry zone middle
double fib79 = 1;    // Entry zone end
double fib100 = 1;   // SL

// Chart objects
string prefix = "Fibo71_";

// Daily stats
int dailyTrades = 0;
datetime lastTradeDate = 0;

// Pending order
ulong pendingTicket = 0;
bool setupActive = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize trade
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(20);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    // Check symbol
    if(!symbolInfo.Name(Symbol))
    {
        Print("❌ Symbol not found: ", Symbol);
        return INIT_FAILED;
    }

    // Check Telegram
    if(EnableTelegram && (TelegramBotToken == "" || TelegramChatID == ""))
    {
        Print("⚠️ Telegram enabled but credentials missing");
    }

    // Send startup notification
    string message = "🚀 <b>Fibo 71 Bot Started</b>\n\n";
    message += "Symbol: " + Symbol + "\n";
    message += "Timeframe: " + EnumToString(Timeframe) + "\n";
    message += "Risk: " + DoubleToString(RiskPercent, 1) + "%\n";
    message += "Entry Zone: " + DoubleToString(FibEntryMin * 100, 0) + "% - " + DoubleToString(FibEntryMax * 100, 0) + "%\n";
    message += "\n⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
    SendTelegram(message);

    Print("══════════════════════════════════════════════════");
    Print("🤖 Fibo 71 Bot - CP 2.0 Strategy");
    Print("══════════════════════════════════════════════════");
    Print("Symbol: ", Symbol, " | Timeframe: ", EnumToString(Timeframe));
    Print("Risk: ", RiskPercent, "% | Entry Zone: ", FibEntryMin * 100, "% - ", FibEntryMax * 100, "%");
    Print("Filters: Imbalance = ", EnableImbalance ? "ON" : "OFF",
          " | Liquidity Sweep = ", EnableLiquiditySweep ? "ON" : "OFF");
    Print("Telegram: ", EnableTelegram ? "ENABLED" : "DISABLED");
    Print("══════════════════════════════════════════════════");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new candle
    static datetime lastCandleTime = 0;
    bool isNewCandle = (Time[0] != lastCandleTime);

    if(isNewCandle)
    {
        lastCandleTime = Time[0];

        // Analyze market
        AnalyzeMarket();

        // Check for trade setup
        CheckTradeSetup();
    }

    // Check pending order status
    if(pendingTicket > 0)
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
    int bars = iBars(Symbol, Timeframe);
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
    double h_1 = iHigh(Symbol, Timeframe, 1);
    double h_2 = iHigh(Symbol, Timeframe, 2);
    double h = iHigh(Symbol, Timeframe, 0);
    double l_1 = iLow(Symbol, Timeframe, 1);
    double l_2 = iLow(Symbol, Timeframe, 2);
    double l = iLow(Symbol, Timeframe, 0);

    // Look for swing high (higher than 2 candles on each side)
    for(int i = 2; i < BOSLookback - 2; i++)
    {
        double h = iHigh(Symbol, Timeframe, i);
        if(h > h_1 && h > h_2 && h > iHigh(Symbol, Timeframe, i + 1) && h > iHigh(Symbol, Timeframe, i + 2))
        {
            swingHigh = h;
            swingHighIdx = i;
            break;
        }
    }

    // Look for swing low (lower than 2 candles on each side)
    for(int i = 2; i < BOSLookback - 2; i++)
    {
        double l = iLow(Symbol, Timeframe, i);
        if(l < l_1 && l < l_2 && l < iLow(Symbol, Timeframe, i + 1) && l < iLow(Symbol, Timeframe, i + 2))
        {
            swingLow = l;
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
    double close = iClose(Symbol, Timeframe, 0);

    // Reset
    bullishBOS = false;
    bearishBOS = false;

    // Bearish BOS: close below swing low
    if(swingLow > 0 && close < swingLow && (0 - swingLowIdx) <= BOSLookback)
    {
        bearishBOS = true;
    }

    // Bullish BOS: close above swing high
    if(swingHigh > 0 && close > swingHigh && (0 - swingHighIdx) <= BOSLookback)
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

    double point = SymbolInfoDouble(Symbol, SYMBOL_POINT);
    double minImbalancePrice = MinImbalancePips * point * 10;

    // Check for imbalance
    if(EnableImbalance)
    {
        // Bearish imbalance: gap between candle 2 low and current high
        double low2 = iLow(Symbol, Timeframe, 2);
        double high0 = iHigh(Symbol, Timeframe, 0);

        // Bullish imbalance: gap between candle 2 high and current low
        double high2 = iHigh(Symbol, Timeframe, 2);
        double low0 = iLow(Symbol, Timeframe, 0);

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
                double h = iHigh(Symbol, Timeframe, i);
                double c = iClose(Symbol, Timeframe, i);
                if(h > swingHigh && c < swingHigh)
                {
                    liquiditySweep = true;
                    break;
                }
            }
            else if(bullishBOSConfirmed)
            {
                double l = iLow(Symbol, Timeframe, i);
                double c = iClose(Symbol, Timeframe, i);
                if(l < swingLow && c > swingLow)
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
        fib71 = swingLow + (swingHigh - swingLow) * FibEntryMin;
        fib75 = swingLow + (swingHigh - swingLow) * 0.75;
        fib79 = swingLow + (swingHigh - swingLow) * FibEntryMax;
    }
    else if(bullishBOSConfirmed)
    {
        // Bullish: swingLow is start (100%), swingHigh is end (0%)
        fib0 = swingHigh;                         // TP
        fib100 = swingLow;                        // SL
        fib71 = swingHigh - (swingHigh - swingLow) * FibEntryMin;
        fib75 = swingHigh - (swingHigh - swingLow) * 0.75;
        fib79 = swingHigh - (swingHigh - swingLow) * FibEntryMax;
    }
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Lines on Chart                                     |
//+------------------------------------------------------------------+
void DrawFibonacciLines()
{
    if(!ShowFibLines)
        return;

    // Delete old objects
    ObjectsDeleteAll(0, prefix);

    datetime timeStart = Time[1];
    datetime timeEnd = Time[1] + PeriodSeconds() * 50;

    color lineColor = bearishBOSConfirmed ? ColorBearish : ColorBullish;

    // Draw TP line (0%)
    HLineCreate(0, prefix + "TP_0", 0, fib0, ColorTP, STYLE_SOLID, 2, "TP (0%)", true);

    // Draw entry zone lines
    HLineCreate(0, prefix + "Entry_71", 0, fib71, ColorEntry, STYLE_DASH, 1, "71%", true);
    HLineCreate(0, prefix + "Entry_75", 0, fib75, ColorEntry, STYLE_SOLID, 1, "75%", true);
    HLineCreate(0, prefix + "Entry_79", 0, fib79, ColorEntry, STYLE_DASH, 1, "79%", true);

    // Draw SL line (100%)
    HLineCreate(0, prefix + "SL_100", 0, fib100, ColorSL, STYLE_SOLID, 2, "SL (100%)", true);

    // Draw swing points
    if(ShowLabels)
    {
        string labelName = prefix + "SwingHigh";
        ObjectCreate(0, labelName, OBJ_ARROW_DOWN, 0, Time[swingHighIdx], swingHigh);
        ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, labelName, OBJPROP_WIDTH, 2);

        labelName = prefix + "SwingLow";
        ObjectCreate(0, labelName, OBJ_ARROW_UP, 0, Time[swingLowIdx], swingLow);
        ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrGreen);
        ObjectSetInteger(0, labelName, OBJPROP_WIDTH, 2);
    }

    ChartRedraw(0);
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
    double currentPrice = SymbolInfo.Double(Symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(Symbol, SYMBOL_POINT);

    // Check if price is in entry zone
    bool inEntryZone = false;
    double entryPrice = fib75; // Use middle of zone

    if(bearishBOSConfirmed)
    {
        // For sell, price needs to retrace UP into entry zone
        inEntryZone = (currentPrice >= fib79 && currentPrice <= fib71);
    }
    else if(bullishBOSConfirmed)
    {
        // For buy, price needs to retrace DOWN into entry zone
        inEntryZone = (currentPrice <= fib71 && currentPrice >= fib79);
    }

    if(inEntryZone && pendingTicket == 0)
    {
        PlaceLimitOrder();
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
//| Place Limit Order                                                 |
//+------------------------------------------------------------------+
void PlaceLimitOrder()
{
    double lotSize = CalculateLotSize();
    double entryPrice, sl, tp;
    ENUM_ORDER_TYPE orderType;

    if(bearishBOSConfirmed)
    {
        orderType = ORDER_TYPE_SELL_LIMIT;
        entryPrice = fib75;  // Middle of entry zone
        sl = fib100;
        tp = fib0;
    }
    else if(bullishBOSConfirmed)
    {
        orderType = ORDER_TYPE_BUY_LIMIT;
        entryPrice = fib75;  // Middle of entry zone
        sl = fib100;
        tp = fib0;
    }
    else
    {
        return;
    }

    // Normalize prices
    double point = SymbolInfoDouble(Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol, SYMBOL_DIGITS);

    entryPrice = NormalizeDouble(entryPrice, digits);
    sl = NormalizeDouble(sl, digits);
    tp = NormalizeDouble(tp, digits);

    // Place order
    if(trade.OrderOpen(Symbol, orderType, lotSize, entryPrice, sl, tp, ORDER_TIME_GTC, 0, TradeComment))
    {
        pendingTicket = trade.ResultOrder();
        dailyTrades++;

        string dirEmoji = bearishBOSConfirmed ? "🔴" : "🟢";
        string dirText = bearishBOSConfirmed ? "SELL LIMIT" : "BUY LIMIT";

        Print("✅ Order placed: ", dirText, " ", lotSize, " @ ", entryPrice);

        if(EnableTelegram)
        {
            int digits = (int)SymbolInfoInteger(Symbol, SYMBOL_DIGITS);

            string message = dirEmoji + " <b>Order Placed</b>\n\n";
            message += "Symbol: " + Symbol + "\n";
            message += "Type: " + dirText + "\n";
            message += "Lots: " + DoubleToString(lotSize, 2) + "\n";
            message += "Entry: " + DoubleToString(entryPrice, digits) + "\n";
            message += "SL: " + DoubleToString(sl, digits) + "\n";
            message += "TP: " + DoubleToString(tp, digits) + "\n";
            message += "\n⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

            SendTelegram(message);
        }
    }
    else
    {
        Print("❌ Order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
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

    // Check if order was triggered (now a position)
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Magic() == MagicNumber)
            {
                // Position opened from our pending order
                // The TP/SL are already set, just monitor
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk = RiskPercent / 100.0 * balance;

    double slPips = MathAbs(fib75 - fib100) / SymbolInfoDouble(Symbol, SYMBOL_POINT) / 10;
    double pipValue = SymbolInfoDouble(Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = risk / (slPips * pipValue);

    // Normalize
    double minLot = SymbolInfoDouble(Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(Symbol, SYMBOL_VOLUME_STEP);

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

    string dirEmoji = bearishBOSConfirmed ? "🔴" : "🟢";
    string dirText = bearishBOSConfirmed ? "BEARISH" : "BULLISH";

    int digits = (int)SymbolInfoInteger(Symbol, SYMBOL_DIGITS);

    string message = dirEmoji + " <b>BOS Detected</b>\n\n";
    message += "Symbol: " + Symbol + "\n";
    message += "Direction: " + dirText + "\n";
    message += "\n<b>Fibonacci Levels:</b>\n";
    message += "• TP (0%): " + DoubleToString(fib0, digits) + "\n";
    message += "• Entry: " + DoubleToString(fib71, digits) + " - " + DoubleToString(fib79, digits) + "\n";
    message += "• SL (100%): " + DoubleToString(fib100, digits) + "\n";
    message += "\nFilters:\n";
    message += "• Imbalance: " + (EnableImbalance ? "✅" : "❌") + "\n";
    message += "• Liq Sweep: " + (liquiditySweep ? "✅" : "❌") + "\n";
    message += "\n⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

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
        Print("❌ Telegram error: ", errorCode, " - ", ErrorDescription(errorCode));
        Print("⚠️ Make sure to add https://api.telegram.org to Tools > Options > Expert Advisors > Allow WebRequest");
        return false;
    }

    string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);

    if(StringFind(response, "\"ok\":true") >= 0)
    {
        Print("✅ Telegram message sent");
        return true;
    }
    else
    {
        Print("❌ Telegram failed: ", response);
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
