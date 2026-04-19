//+------------------------------------------------------------------+
//|                                    Fibo71_CP2_Bot_v4.mq5          |
//|                         Fibo 71 CP 2.0 - BOS + Imbalance         |
//|        EA trading bot with full Pine Script indicator visuals      |
//+------------------------------------------------------------------+
#property copyright "Fibo 71 Bot - CP 2.0 Strategy"
#property link      ""
#property version   "4.00"
#property description "Fibo 71 CP 2.0 Trading Bot"
#property description "Pine Script visuals + automated trading"
#property strict

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

//--- Fibonacci Settings
input group "=== Fibonacci ==="
input double FibEntryMin        = 0.71;  // Fib Entry Min (0.5-0.95)
input double FibEntryMax        = 0.79;  // Fib Entry Max (0.5-0.95)

//--- BOS Detection Settings
input group "=== BOS Detection ==="
input int    BOSLookback        = 50;    // BOS Lookback (bars)
input int    SwingLookback      = 5;     // Swing Lookback (bars on each side)
input double MinImbalancePips   = 10.0;  // Min Imbalance (pips)

//--- Filter Settings
input group "=== Filters ==="
input bool   EnableImbalance      = true;  // Require Imbalance
input bool   EnableLiquiditySweep = true;  // Require Liquidity Sweep

//--- Setup Duration
input group "=== Setup Duration ==="
input int    SetupExpiryBars    = 500;   // Setup Expiry (bars)
input bool   SetupExpiryEnabled = true;  // Enable Setup Expiry

//--- Entry Positions (EP1/EP2/EP3)
input group "=== Entry Positions ==="
input int    PositionMode       = 1;       // Mode: 1=Single(71-79%), 2=Normal(EP1+EP2), 3=Aggressive(EP1+EP2+EP3)

//--- Trading Settings
input group "=== Trading ==="
input int    MagicNumber        = 710071;  // Magic Number
input double RiskPercent        = 1.0;     // Risk per Trade (%) [used only for Single mode]
input double FixedLot           = 0.0;     // Fixed Lot (0 = auto from risk%)
input int    MaxDailyTrades     = 3;       // Max Daily Trades
input int    MaxOpenPositions   = 6;       // Max Open Positions
input int    Slippage           = 10;      // Max Slippage (points)
input bool   PlacePendingOrders = true;    // Use Limit Orders (vs Market)
input int    OrderExpiryHours   = 48;      // Pending Order Expiry (hours)

//--- HTF Filter
input group "=== HTF Filter ==="
input bool   EnableHTF          = false;   // Enable Higher Timeframe Filter
input ENUM_TIMEFRAMES HTFTimeframe = PERIOD_H1; // HTF Timeframe
input int    HTFEMA             = 200;     // HTF EMA Period

//--- Trailing Stop
input group "=== Trailing Stop ==="
input bool   EnableTrailingStop = false;   // Enable Trailing Stop
input double TrailingStartPips  = 20.0;    // Start trailing after X pips profit
input double TrailingStopPips   = 15.0;    // Trailing stop distance in pips

//--- Daily Auto-Close
input group "=== Daily Close ==="
input bool   EnableDailyClose   = false;   // Enable Daily Auto-Close
input string DailyCloseTime     = "23:55"; // Close time HH:MM (server time)

//--- Session Filter
input group "=== Session Filter ==="
input bool   EnableSessionFilter= false;   // Enable Session Filter
input string SessionStart       = "08:00"; // Session start HH:MM (server time)
input string SessionEnd         = "20:00"; // Session end HH:MM (server time)

//--- Weekend Close
input group "=== Weekend Close ==="
input bool   EnableWeekendClose = false;   // Enable Friday Close + Block Weekend
input string WeekendCloseTime   = "21:00"; // Friday close time HH:MM

//--- ATR / Consolidation Filter
input group "=== ATR Filter ==="
input bool   EnableATRFilter    = false;   // Enable ATR Consolidation Filter
input int    ATRLength          = 14;      // ATR Period
input int    ATRSmooth          = 50;      // ATR Smoothing Period
input double ATRThreshold       = 1.0;     // ATR Threshold Multiplier

//--- Partial Close
input group "=== Partial Close ==="
input bool   EnablePartialClose = false;   // Enable Partial Close at TP1
input double PartialClosePercent = 70.0;   // Close % of position at TP1
input bool   PartialMoveSL      = true;    // Move SL to breakeven after partial

//--- Display Settings
input group "=== Display ==="
input bool   ShowSwingPoints    = true;  // Show Swing Points
input bool   ShowFibLines       = true;  // Show Fibonacci Lines
input bool   ShowLabels         = true;  // Show Labels
input bool   ShowEntryZone      = true;  // Show Entry Zone
input bool   ShowTradeLabels    = true;  // Show Trade Entry Labels
input int    MaxActiveSetups    = 5;     // Max Active Setups (1-10)

//--- Color Settings
input group "=== Colors ==="
input color  ColorBullish       = clrLime;        // Bullish Color
input color  ColorBearish       = clrRed;         // Bearish Color
input color  ColorFib0          = clrLime;        // Fib 0% (TP)
input color  ColorFib50         = clrDodgerBlue;  // Fib 50%
input color  ColorFib100        = clrRed;         // Fib 100% (SL)
input color  ColorFib71_79      = clrDodgerBlue;  // Fib 71%/79% (Entry)
input color  ColorEntryZone     = C'0,0,255';     // Entry Zone Color

//--- Telegram Settings
input group "=== Telegram ==="
input bool   EnableTelegram     = false;   // Enable Telegram
input string TelegramBotToken   = "";      // Bot Token
input string TelegramChatId     = "";      // Chat ID

//+------------------------------------------------------------------+
//| Setup Structure                                                   |
//+------------------------------------------------------------------+
struct SSetup
{
   bool   isBullish;       // Direction
   double fib0;            // TP level
   double fib236;
   double fib382;
   double fib50;
   double fib618;
   double fib786;          // Deep retracement (SL for EP2/EP3)
   double fib100;          // SL level
   double fib71;           // Entry zone boundary
   double fib79;           // Entry zone boundary
   int    createdBar;      // Bar index when created
   int    hitBar;          // Bar when TP/SL hit (-1 = active)
   int    hitResult;       // 0=active, 1=TP, 2=SL, 3=expired
   string objPrefix;       // Object name prefix for this setup
   ulong  orderTickets[3]; // Pending order tickets (up to 3 positions)
   bool   traded;          // Whether a trade was placed for this setup
};

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
SSetup   g_setups[];           // Array of active setups
double   g_swingHigh = 0;
double   g_swingLow  = 0;
int      g_swingHighIdx = -1;
int      g_swingLowIdx  = -1;
int      g_setupCounter = 0;
datetime g_lastBarTime  = 0;
string   g_prefix = "F71_";
int      g_dailyTrades = 0;
datetime g_lastTradeDate = 0;
int      g_htfHandle = INVALID_HANDLE;
int      g_atrHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(FibEntryMin >= FibEntryMax)
   {
      Print("ERROR: FibEntryMin must be less than FibEntryMax");
      return(INIT_PARAMETERS_INCORRECT);
   }

   ArrayResize(g_setups, 0);
   g_setupCounter = 0;
   g_dailyTrades = 0;

   // Create indicator handles
   if(EnableHTF)
      g_htfHandle = iMA(_Symbol, HTFTimeframe, HTFEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(EnableATRFilter)
      g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATRLength);

   Print("============================================");
   Print("  Fibo 71 CP 2.0 Trading Bot v4.0");
   Print("============================================");
   Print("Symbol: ", _Symbol, " | TF: ", EnumToString(Period()));
   Print("Fib Entry: ", FibEntryMin, " - ", FibEntryMax);
   Print("BOS Lookback: ", BOSLookback, " | Swing: ", SwingLookback);
   Print("Imbalance: ", EnableImbalance ? "ON" : "OFF",
         " | Liq Sweep: ", EnableLiquiditySweep ? "ON" : "OFF");
   Print("Risk: ", RiskPercent, "% | Magic: ", MagicNumber);
   Print("Trading: ", PlacePendingOrders ? "Limit Orders" : "Market Orders");
   Print("Max Daily: ", MaxDailyTrades, " | Max Open: ", MaxOpenPositions);
   Print("Telegram: ", EnableTelegram ? "ON" : "OFF");
   Print("============================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);
   if(g_htfHandle != INVALID_HANDLE) IndicatorRelease(g_htfHandle);
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   ChartRedraw(0);
   Print("=== Fibo 71 CP 2.0 Bot Stopped ===");
}

//+------------------------------------------------------------------+
//| Main tick handler                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == g_lastBarTime)
      return;
   g_lastBarTime = currentBarTime;

   int total = iBars(_Symbol, PERIOD_CURRENT);
   if(total < SwingLookback + 10)
      return;

   // Reset daily counter
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StringToTime(IntegerToString(dt.year) + "." +
                                  IntegerToString(dt.mon) + "." +
                                  IntegerToString(dt.day));
   if(today != g_lastTradeDate)
   {
      g_dailyTrades = 0;
      g_lastTradeDate = today;
   }

   // ---- STEP 1-4: Detection ----
   DetectSwingPoints(total);

   bool bullishBOS = false, bearishBOS = false;
   DetectBOS(total, bullishBOS, bearishBOS);

   bool bearishImbalance = false, bullishImbalance = false;
   DetectImbalance(total, bearishImbalance, bullishImbalance);

   // Liquidity sweep: only checked when BOS is detected (matching Pine Script)
   bool bearishLiqSweep = false, bullishLiqSweep = false;
   DetectLiquiditySweep(total, bearishBOS, bullishBOS, bearishLiqSweep, bullishLiqSweep);

   // ---- STEP 5: Check criteria ----
   bool newBearishSetup = bearishBOS &&
                          (!EnableImbalance || bearishImbalance) &&
                          (!EnableLiquiditySweep || bearishLiqSweep);

   bool newBullishSetup = bullishBOS &&
                          (!EnableImbalance || bullishImbalance) &&
                          (!EnableLiquiditySweep || bullishLiqSweep);

   // ---- STEP 6: Check existing setups ----
   CheckExistingSetups(total);

   // ---- STEP 7: Create new setup ----
   if(newBearishSetup)
      CreateSetup(false, total);

   if(newBullishSetup)
      CreateSetup(true, total);

   // ---- STEP 8: Draw swing points ----
   if(ShowSwingPoints)
      DrawSwingPoints(total);

   // ---- STEP 9: Check entry zone & trade ----
   CheckEntryZoneAndTrade(total);

   // ---- STEP 10: Update info table ----
   UpdateInfoTable(total);

   // ---- STEP 11: Manage existing positions ----
   ExecuteDailyClose();
   ExecuteWeekendClose();
   ManageTrailingStop();
   ManagePartialClose();

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| DETECTION FUNCTIONS (identical to Pine Script)                    |
//+------------------------------------------------------------------+

void DetectSwingPoints(int total)
{
   int idx = total - 1;
   bool isSwingHigh = true;
   bool isSwingLow  = true;

   for(int i = 1; i <= SwingLookback; i++)
   {
      if(idx - i < 0) continue;
      if(iHigh(_Symbol, PERIOD_CURRENT, idx - i) >= iHigh(_Symbol, PERIOD_CURRENT, idx))
         isSwingHigh = false;
      if(iLow(_Symbol, PERIOD_CURRENT, idx - i) <= iLow(_Symbol, PERIOD_CURRENT, idx))
         isSwingLow = false;
   }

   if(isSwingHigh)
   {
      g_swingHigh    = iHigh(_Symbol, PERIOD_CURRENT, idx);
      g_swingHighIdx = idx;
   }
   if(isSwingLow)
   {
      g_swingLow    = iLow(_Symbol, PERIOD_CURRENT, idx);
      g_swingLowIdx = idx;
   }
}

void DetectBOS(int total, bool &bullishBOS, bool &bearishBOS)
{
   bullishBOS = false;
   bearishBOS = false;

   int idx = total - 1;
   double closePrice = iClose(_Symbol, PERIOD_CURRENT, idx);

   if(g_swingLow > 0 && closePrice < g_swingLow)
   {
      int age = idx - g_swingLowIdx;
      if(age >= 3 && age <= BOSLookback)
         bearishBOS = true;
   }

   if(g_swingHigh > 0 && closePrice > g_swingHigh)
   {
      int age = idx - g_swingHighIdx;
      if(age >= 3 && age <= BOSLookback)
         bullishBOS = true;
   }
}

void DetectImbalance(int total, bool &bearishImbalance, bool &bullishImbalance)
{
   bearishImbalance = false;
   bullishImbalance = false;
   if(total < 3) return;

   int idx = total - 1;
   double pipMult = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   double minGap  = MinImbalancePips * pipMult;

   double low2  = iLow(_Symbol, PERIOD_CURRENT, idx - 2);
   double high0 = iHigh(_Symbol, PERIOD_CURRENT, idx);
   double high2 = iHigh(_Symbol, PERIOD_CURRENT, idx - 2);
   double low0  = iLow(_Symbol, PERIOD_CURRENT, idx);

   if(low2 > high0 && (low2 - high0) >= minGap)
      bearishImbalance = true;
   if(high2 < low0 && (low0 - high2) >= minGap)
      bullishImbalance = true;
}

// Pine Script: liquidity sweep is ONLY checked when BOS is detected
// if bearishBOS -> check if high[i] > swingHigh and close[i] < swingHigh
// if bullishBOS -> check if low[i] < swingLow and close[i] > swingLow
void DetectLiquiditySweep(int total, bool bearishBOS, bool bullishBOS,
                          bool &bearishLiqSweep, bool &bullishLiqSweep)
{
   bearishLiqSweep = false;
   bullishLiqSweep = false;
   int lookback = 5;
   int idx = total - 1;

   // Only check bearish sweep when bearish BOS is detected
   if(bearishBOS && g_swingHigh > 0)
   {
      for(int i = 1; i <= lookback; i++)
      {
         if(idx - i < 0) break;
         if(iHigh(_Symbol, PERIOD_CURRENT, idx - i) > g_swingHigh &&
            iClose(_Symbol, PERIOD_CURRENT, idx - i) < g_swingHigh)
         {
            bearishLiqSweep = true;
            break;
         }
      }
   }

   // Only check bullish sweep when bullish BOS is detected
   if(bullishBOS && g_swingLow > 0)
   {
      for(int i = 1; i <= lookback; i++)
      {
         if(idx - i < 0) break;
         if(iLow(_Symbol, PERIOD_CURRENT, idx - i) < g_swingLow &&
            iClose(_Symbol, PERIOD_CURRENT, idx - i) > g_swingLow)
         {
            bullishLiqSweep = true;
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK EXISTING SETUPS                                             |
//+------------------------------------------------------------------+
void CheckExistingSetups(int total)
{
   int idx = total - 1;
   double barHigh = iHigh(_Symbol, PERIOD_CURRENT, idx);
   double barLow  = iLow(_Symbol, PERIOD_CURRENT, idx);

   for(int i = 0; i < ArraySize(g_setups); i++)
   {
      SSetup &s = g_setups[i];
      if(s.hitBar >= 0) continue;

      bool isExpired = SetupExpiryEnabled &&
                       ((idx - s.createdBar) >= SetupExpiryBars);

      if(isExpired)
      {
         for(int t = 0; t < 3; t++)
            if(s.orderTickets[t] > 0)
               OrderCancelSafe(s.orderTickets[t], "Expired");

         DeleteSetupDrawings(s);
         s.hitBar    = idx;
         s.hitResult = 3;

         if(ShowLabels)
         {
            string name = s.objPrefix + "Expired";
            datetime cTime = iTime(_Symbol, PERIOD_CURRENT, s.createdBar);
            ObjectCreate(0, name, OBJ_TEXT, 0, cTime, s.fib100);
            ObjectSetString(0, name, OBJPROP_TEXT, "EXPIRED");
            ObjectSetInteger(0, name, OBJPROP_COLOR, clrGray);
            ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
         }
         Print("Setup EXPIRED: ", s.objPrefix, " | Age: ", idx - s.createdBar, " bars");
      }
      else
      {
         bool hitTP = s.isBullish ? (barLow <= s.fib0) : (barHigh >= s.fib0);
         bool hitSL = s.isBullish ? (barHigh >= s.fib100) : (barLow <= s.fib100);

         if(hitTP)
         {
            s.hitBar    = idx;
            s.hitResult = 1;

            for(int t = 0; t < 3; t++)
               if(s.orderTickets[t] > 0)
                  OrderCancelSafe(s.orderTickets[t], "TP hit");

            if(ShowLabels)
            {
               ObjectDelete(0, s.objPrefix + "BOS");
               string name = s.objPrefix + "TPHit";
               ObjectCreate(0, name, OBJ_TEXT, 0,
                            iTime(_Symbol, PERIOD_CURRENT, 0), s.fib0);
               ObjectSetString(0, name, OBJPROP_TEXT, CharToString(0x2705) + " TP HIT");
               ObjectSetInteger(0, name, OBJPROP_COLOR, clrLime);
               ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
            }
            if(ShowFibLines)
               ObjectSetInteger(0, s.objPrefix + "Fib0", OBJPROP_WIDTH, 3);

            Print("TP HIT | ", s.objPrefix, " | ",
                  s.isBullish ? "BULL" : "BEAR");
         }
         else if(hitSL)
         {
            s.hitBar    = idx;
            s.hitResult = 2;

            for(int t = 0; t < 3; t++)
               if(s.orderTickets[t] > 0)
                  OrderCancelSafe(s.orderTickets[t], "SL hit");

            if(ShowLabels)
            {
               ObjectDelete(0, s.objPrefix + "BOS");
               string name = s.objPrefix + "SLHit";
               ObjectCreate(0, name, OBJ_TEXT, 0,
                            iTime(_Symbol, PERIOD_CURRENT, 0), s.fib100);
               ObjectSetString(0, name, OBJPROP_TEXT, CharToString(0x26D4) + " SL HIT");
               ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
               ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
            }
            if(ShowFibLines)
               ObjectSetInteger(0, s.objPrefix + "Fib100", OBJPROP_WIDTH, 3);

            Print("SL HIT | ", s.objPrefix, " | ",
                  s.isBullish ? "BULL" : "BEAR");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CREATE NEW SETUP                                                  |
//+------------------------------------------------------------------+
void CreateSetup(bool isBullish, int total)
{
   int idx = total - 1;
   double range, fib0, fib100, fib236, fib382, fib50, fib618, fib786, fib71, fib79;

   if(!isBullish)
   {
      fib0   = g_swingLow;  fib100 = g_swingHigh;
      range  = g_swingHigh - g_swingLow;
      fib236 = g_swingLow + range * 0.236;
      fib382 = g_swingLow + range * 0.382;
      fib50  = g_swingLow + range * 0.5;
      fib618 = g_swingLow + range * 0.618;
      fib786 = g_swingLow + range * 0.786;
      fib71  = g_swingLow + range * FibEntryMin;
      fib79  = g_swingLow + range * FibEntryMax;
   }
   else
   {
      fib0   = g_swingHigh; fib100 = g_swingLow;
      range  = g_swingHigh - g_swingLow;
      fib236 = g_swingHigh - range * 0.236;
      fib382 = g_swingHigh - range * 0.382;
      fib50  = g_swingHigh - range * 0.5;
      fib618 = g_swingHigh - range * 0.618;
      fib786 = g_swingHigh - range * 0.786;
      fib71  = g_swingHigh - range * FibEntryMin;
      fib79  = g_swingHigh - range * FibEntryMax;
   }

   SSetup s;
   s.isBullish   = isBullish;
   s.fib0 = fib0; s.fib236 = fib236; s.fib382 = fib382;
   s.fib50 = fib50; s.fib618 = fib618; s.fib786 = fib786; s.fib100 = fib100;
   s.fib71 = fib71; s.fib79 = fib79;
   s.createdBar  = idx;
   s.hitBar      = -1;
   s.hitResult   = 0;
   s.objPrefix   = g_prefix + "S" + IntegerToString(g_setupCounter) + "_";
   s.orderTickets[0] = 0;
   s.orderTickets[1] = 0;
   s.orderTickets[2] = 0;
   s.traded      = false;
   g_setupCounter++;

   CreateSetupDrawings(s, total);

   int size = ArraySize(g_setups);
   ArrayResize(g_setups, size + 1);
   g_setups[size] = s;

   while(ArraySize(g_setups) > MaxActiveSetups)
   {
      for(int t = 0; t < 3; t++)
         if(g_setups[0].orderTickets[t] > 0)
            OrderCancelSafe(g_setups[0].orderTickets[t], "Max setups");
      DeleteSetupDrawings(g_setups[0]);
      for(int i = 0; i < ArraySize(g_setups) - 1; i++)
         g_setups[i] = g_setups[i + 1];
      ArrayResize(g_setups, ArraySize(g_setups) - 1);
   }

   // Log + Alert
   string dir = isBullish ? "BULLISH" : "BEARISH";
   string entryZone = isBullish ?
      DoubleToString(fib79, _Digits) + " - " + DoubleToString(fib71, _Digits) :
      DoubleToString(fib71, _Digits) + " - " + DoubleToString(fib79, _Digits);

   Print("=== ", dir, " BOS DETECTED ===");
   Print("  TP: ", DoubleToString(fib0, _Digits), " | 50%: ", DoubleToString(fib50, _Digits));
   Print("  Entry Zone: ", entryZone);
   Print("  SL: ", DoubleToString(fib100, _Digits));

   Alert("Fibo71: ", dir, " BOS on ", _Symbol,
         " | Entry: ", entryZone,
         " | TP: ", DoubleToString(fib0, _Digits),
         " | SL: ", DoubleToString(fib100, _Digits));

   string msg = "Fibo71: " + dir + " BOS on " + _Symbol +
                "\nEntry: " + entryZone +
                "\nTP: " + DoubleToString(fib0, _Digits) +
                "\nSL: " + DoubleToString(fib100, _Digits);
   SendTelegram(msg);
}

//+------------------------------------------------------------------+
//| WEEKEND & SESSION FILTERS                                         |
//+------------------------------------------------------------------+
bool IsWeekendBlocked()
{
   if(!EnableWeekendClose) return false;

   MqlDateTime dt;
   TimeCurrent(dt);
   // Friday after close time
   if(dt.day_of_week == 5)
   {
      int closeH, closeM;
      ParseTime(WeekendCloseTime, closeH, closeM);
      if(dt.hour >= closeH && (dt.hour > closeH || dt.min >= closeM))
         return true;
   }
   // Saturday
   if(dt.day_of_week == 6) return true;
   // Sunday
   if(dt.day_of_week == 0) return true;
   return false;
}

bool IsSessionActive()
{
   if(!EnableSessionFilter) return true;

   MqlDateTime dt;
   TimeCurrent(dt);
   int nowMinutes = dt.hour * 60 + dt.min;

   int startH, startM, endH, endM;
   ParseTime(SessionStart, startH, startM);
   ParseTime(SessionEnd, endH, endM);

   int startMinutes = startH * 60 + startM;
   int endMinutes   = endH * 60 + endM;

   if(startMinutes <= endMinutes)
      return (nowMinutes >= startMinutes && nowMinutes <= endMinutes);
   else // Overnight session
      return (nowMinutes >= startMinutes || nowMinutes <= endMinutes);
}

void ParseTime(string timeStr, int &hours, int &minutes)
{
   hours = (int)StringToInteger(StringSubstr(timeStr, 0, 2));
   minutes = (int)StringToInteger(StringSubstr(timeStr, 3, 2));
}

bool IsDailyCloseTime()
{
   if(!EnableDailyClose) return false;

   MqlDateTime dt;
   TimeCurrent(dt);

   int closeH, closeM;
   ParseTime(DailyCloseTime, closeH, closeM);

   return (dt.hour == closeH && dt.min == closeM);
}

void ExecuteDailyClose()
{
   if(!IsDailyCloseTime()) return;

   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult  result  = {};
            request.action  = TRADE_ACTION_DEAL;
            request.symbol  = _Symbol;
            request.volume  = PositionGetDouble(POSITION_VOLUME);
            request.type    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                              ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.deviation = Slippage;
            request.position = ticket;
            if(OrderSend(request, result))
               count++;
         }
      }
   }

   // Cancel pending orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult  result  = {};
            request.action = TRADE_ACTION_REMOVE;
            request.order  = ticket;
            OrderSend(request, result);
         }
      }
   }

   if(count > 0)
      Print("Daily Close: closed ", count, " positions at ", DailyCloseTime);
}

void ExecuteWeekendClose()
{
   if(!EnableWeekendClose) return;

   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_week != 5) return;

   int closeH, closeM;
   ParseTime(WeekendCloseTime, closeH, closeM);
   if(!(dt.hour == closeH && dt.min == closeM)) return;

   Print("=== WEEKEND CLOSE ===");

   // Close positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult  result  = {};
            request.action  = TRADE_ACTION_DEAL;
            request.symbol  = _Symbol;
            request.volume  = PositionGetDouble(POSITION_VOLUME);
            request.type    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                              ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.deviation = Slippage;
            request.position = ticket;
            OrderSend(request, result);
         }
      }
   }

   // Cancel pending orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult  result  = {};
            request.action = TRADE_ACTION_REMOVE;
            request.order  = ticket;
            OrderSend(request, result);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| HTF FILTER - Higher Timeframe EMA trend confirmation               |
//+------------------------------------------------------------------+
// Returns: 1 = bullish (price above HTF EMA), -1 = bearish, 0 = neutral
int GetHTFTrend()
{
   if(!EnableHTF) return 0;
   if(g_htfHandle == INVALID_HANDLE) return 0;

   double htfEma[];
   if(CopyBuffer(g_htfHandle, 0, 0, 2, htfEma) < 1) return 0;

   double htfClose = iClose(_Symbol, HTFTimeframe, 0);
   if(htfClose > htfEma[0]) return 1;   // Bullish
   if(htfClose < htfEma[0]) return -1;  // Bearish
   return 0;
}

//+------------------------------------------------------------------+
//| TRAILING STOP                                                      |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!EnableTrailingStop) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double trailStart = TrailingStartPips * point * 10;
   double trailDist  = TrailingStopPips  * point * 10;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid - openPrice >= trailStart)
         {
            double newSL = NormalizeDouble(bid - trailDist, _Digits);
            if(newSL > currentSL)
            {
               MqlTradeRequest request = {};
               MqlTradeResult  result  = {};
               request.action   = TRADE_ACTION_SLTP;
               request.position = ticket;
               request.symbol   = _Symbol;
               request.sl       = newSL;
               request.tp       = currentTP;
               OrderSend(request, result);
            }
         }
      }
      else // SELL
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(openPrice - ask >= trailStart)
         {
            double newSL = NormalizeDouble(ask + trailDist, _Digits);
            if(currentSL == 0 || newSL < currentSL)
            {
               MqlTradeRequest request = {};
               MqlTradeResult  result  = {};
               request.action   = TRADE_ACTION_SLTP;
               request.position = ticket;
               request.symbol   = _Symbol;
               request.sl       = newSL;
               request.tp       = currentTP;
               OrderSend(request, result);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ATR / CONSOLIDATION FILTER                                        |
//+------------------------------------------------------------------+
bool IsATRActive()
{
   if(!EnableATRFilter) return true;
   if(g_atrHandle == INVALID_HANDLE) return true;

   double atrBuf[];
   if(CopyBuffer(g_atrHandle, 0, 0, ATRSmooth + 1, atrBuf) < ATRSmooth + 1)
      return true;

   double currentATR = atrBuf[0];

   // Calculate SMA of ATR for baseline
   double baselineATR = 0;
   for(int i = 0; i < ATRSmooth; i++)
      baselineATR += atrBuf[i];
   baselineATR /= ATRSmooth;

   // Active = current ATR above baseline * threshold (expansion, not consolidation)
   return (currentATR > baselineATR * ATRThreshold);
}

//+------------------------------------------------------------------+
//| PARTIAL CLOSE                                                      |
//+------------------------------------------------------------------+
void ManagePartialClose()
{
   if(!EnablePartialClose) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      string comment   = PositionGetString(POSITION_COMMENT);

      // Only process positions that haven't been partially closed yet
      if(StringFind(comment, "_PC") >= 0) continue;

      // Calculate TP distance
      double tpDistance = MathAbs(currentTP - openPrice);
      if(tpDistance <= 0) continue;

      // Check if price reached TP1 (first target = 70% of TP distance)
      double tp1Level;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         tp1Level = openPrice + tpDistance * 0.7;
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid < tp1Level) continue;

         // Check minimum volume for partial close
         double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double closeVol = MathFloor(volume * PartialClosePercent / 100.0 / volStep) * volStep;
         if(closeVol < minVol) continue;
         if(volume - closeVol < minVol) continue;

         // Partial close
         MqlTradeRequest request = {};
         MqlTradeResult  result  = {};
         request.action   = TRADE_ACTION_DEAL;
         request.symbol   = _Symbol;
         request.volume   = NormalizeDouble(closeVol, 2);
         request.type     = ORDER_TYPE_SELL;
         request.deviation = Slippage;
         request.position = ticket;
         request.comment  = comment + "_PC";

         if(OrderSend(request, result))
         {
            Print("Partial Close BUY: ", NormalizeDouble(closeVol, 2), " lots at TP1");

            // Move SL to breakeven for remaining position
            if(PartialMoveSL)
            {
               MqlTradeRequest slReq = {};
               MqlTradeResult  slRes = {};
               slReq.action   = TRADE_ACTION_SLTP;
               slReq.position = ticket;
               slReq.symbol   = _Symbol;
               slReq.sl       = NormalizeDouble(openPrice, _Digits);
               slReq.tp       = currentTP;
               OrderSend(slReq, slRes);
            }

            SendTelegram("Fibo71: Partial Close on " + _Symbol +
               "\nClosed " + DoubleToString(closeVol, 2) + " lots (TP1)" +
               (PartialMoveSL ? "\nSL moved to breakeven" : ""));
         }
      }
      else // SELL
      {
         tp1Level = openPrice - tpDistance * 0.7;
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(ask > tp1Level) continue;

         double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double closeVol = MathFloor(volume * PartialClosePercent / 100.0 / volStep) * volStep;
         if(closeVol < minVol) continue;
         if(volume - closeVol < minVol) continue;

         MqlTradeRequest request = {};
         MqlTradeResult  result  = {};
         request.action   = TRADE_ACTION_DEAL;
         request.symbol   = _Symbol;
         request.volume   = NormalizeDouble(closeVol, 2);
         request.type     = ORDER_TYPE_BUY;
         request.deviation = Slippage;
         request.position = ticket;
         request.comment  = comment + "_PC";

         if(OrderSend(request, result))
         {
            Print("Partial Close SELL: ", NormalizeDouble(closeVol, 2), " lots at TP1");

            if(PartialMoveSL)
            {
               MqlTradeRequest slReq = {};
               MqlTradeResult  slRes = {};
               slReq.action   = TRADE_ACTION_SLTP;
               slReq.position = ticket;
               slReq.symbol   = _Symbol;
               slReq.sl       = NormalizeDouble(openPrice, _Digits);
               slReq.tp       = currentTP;
               OrderSend(slReq, slRes);
            }

            SendTelegram("Fibo71: Partial Close on " + _Symbol +
               "\nClosed " + DoubleToString(closeVol, 2) + " lots (TP1)" +
               (PartialMoveSL ? "\nSL moved to breakeven" : ""));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK ENTRY ZONE & PLACE TRADE (EP1/EP2/EP3)                      |
//+------------------------------------------------------------------+
void CheckEntryZoneAndTrade(int total)
{
   int idx = total - 1;
   double closePrice = iClose(_Symbol, PERIOD_CURRENT, idx);

   // Session filter check
   if(!IsSessionActive())
      return;

   // Weekend block
   if(IsWeekendBlocked())
      return;

   // HTF trend check
   int htfTrend = GetHTFTrend();

   // ATR consolidation check
   if(!IsATRActive())
      return;

   for(int i = 0; i < ArraySize(g_setups); i++)
   {
      SSetup &s = g_setups[i];
      if(s.hitBar >= 0) continue;
      if(s.traded) continue;

      // HTF filter: skip if setup direction opposes HTF trend
      if(EnableHTF && htfTrend != 0)
      {
         if(s.isBullish && htfTrend == -1) continue;
         if(!s.isBullish && htfTrend == 1) continue;
      }

      // Determine entry zone based on PositionMode
      if(PositionMode == 1)
      {
         // Single mode: entry at 71-79% zone
         bool inZone = false;
         if(s.isBullish)
            inZone = (closePrice <= s.fib71 && closePrice >= s.fib79);
         else
            inZone = (closePrice >= s.fib79 && closePrice <= s.fib71);

         if(!inZone) continue;

         if(!CanTrade()) continue;
         PlaceSingleOrder(s);
      }
      else if(PositionMode == 2)
      {
         // Normal mode: EP1 at 0.5, EP2 at 0.618
         PlaceEP(s, 0.5, s.fib50, s.fib618, 1, closePrice);
         PlaceEP(s, 0.618, s.fib618, s.fib786, 2, closePrice);
      }
      else if(PositionMode == 3)
      {
         // Aggressive mode: EP1 at 0.382, EP2 at 0.5, EP3 at 0.618
         PlaceEP(s, 0.382, s.fib382, s.fib50, 1, closePrice);
         PlaceEP(s, 0.5, s.fib50, s.fib618, 2, closePrice);
         PlaceEP(s, 0.618, s.fib618, s.fib786, 3, closePrice);
      }
   }
}

//+------------------------------------------------------------------+
//| Check if trading is allowed (limits)                               |
//+------------------------------------------------------------------+
bool CanTrade()
{
   if(g_dailyTrades >= MaxDailyTrades) return false;
   if(CountOpenPositions() >= MaxOpenPositions) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Place single order at 71-79% zone (Mode 1)                        |
//+------------------------------------------------------------------+
void PlaceSingleOrder(SSetup &s)
{
   // Check if order already placed
   if(s.orderTickets[0] > 0)
   {
      if(OrderSelect(s.orderTickets[0]))
         return;
      s.orderTickets[0] = 0;
   }

   double lot = CalculateLotSize(s.fib71, s.fib100);
   if(lot <= 0) return;

   bool success = false;

   if(PlacePendingOrders)
   {
      double entryPrice = s.isBullish ? s.fib79 : s.fib71;
      ENUM_ORDER_TYPE orderType = s.isBullish ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action    = TRADE_ACTION_PENDING;
      request.symbol    = _Symbol;
      request.volume    = lot;
      request.type      = orderType;
      request.price     = NormalizeDouble(entryPrice, _Digits);
      request.sl        = NormalizeDouble(s.fib100, _Digits);
      request.tp        = NormalizeDouble(s.fib0, _Digits);
      request.deviation = Slippage;
      request.magic     = MagicNumber;
      request.comment   = "F71_" + s.objPrefix;

      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
         {
            s.orderTickets[0] = result.order;
            success = true;

            Print("  LIMIT ORDER: ", s.isBullish ? "BUY" : "SELL",
                  " | Lot: ", lot,
                  " | Entry: ", DoubleToString(entryPrice, _Digits),
                  " | SL: ", DoubleToString(s.fib100, _Digits),
                  " | TP: ", DoubleToString(s.fib0, _Digits));

            if(ShowTradeLabels)
            {
               string lblName = s.objPrefix + "Trade";
               ObjectCreate(0, lblName, OBJ_TEXT, 0,
                            iTime(_Symbol, PERIOD_CURRENT, 0), entryPrice);
               ObjectSetString(0, lblName, OBJPROP_TEXT,
                  (s.isBullish ? "BUY LIMIT" : "SELL LIMIT") + StringFormat("\n%.2f lots", lot));
               ObjectSetInteger(0, lblName, OBJPROP_COLOR, s.isBullish ? clrLime : clrRed);
               ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 7);
            }

            SendTelegram("Fibo71: Order on " + _Symbol +
               "\n" + (s.isBullish ? "BUY LIMIT" : "SELL LIMIT") + " " + DoubleToString(lot, 2) +
               "\nEntry: " + DoubleToString(entryPrice, _Digits) +
               "\nSL: " + DoubleToString(s.fib100, _Digits) +
               "\nTP: " + DoubleToString(s.fib0, _Digits));
         }
      }
   }
   else
   {
      ENUM_ORDER_TYPE orderType = s.isBullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action    = TRADE_ACTION_DEAL;
      request.symbol    = _Symbol;
      request.volume    = lot;
      request.type      = orderType;
      request.sl        = NormalizeDouble(s.fib100, _Digits);
      request.tp        = NormalizeDouble(s.fib0, _Digits);
      request.deviation = Slippage;
      request.magic     = MagicNumber;
      request.comment   = "F71_" + s.objPrefix;

      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE)
         {
            s.orderTickets[0] = result.order;
            success = true;

            Print("  MARKET ORDER: ", s.isBullish ? "BUY" : "SELL",
                  " | Lot: ", lot,
                  " | Price: ", DoubleToString(result.price, _Digits));
         }
      }
   }

   if(success)
   {
      s.traded = true;
      g_dailyTrades++;
   }
}

//+------------------------------------------------------------------+
//| Place EP order at specific Fibonacci level (Mode 2/3)              |
//+------------------------------------------------------------------+
void PlaceEP(SSetup &s, double fibLevel, double entryPrice, double slPrice,
             int epIndex, double currentClose)
{
   // Check if this EP already placed
   if(epIndex < 1 || epIndex > 3) return;
   int ticketIdx = epIndex - 1;

   if(s.orderTickets[ticketIdx] > 0)
   {
      if(OrderSelect(s.orderTickets[ticketIdx]))
         return;
      s.orderTickets[ticketIdx] = 0;
   }

   // Check if price is near entry level
   double zone_width = MathAbs(s.fib100 - s.fib0) * 0.05;
   bool nearLevel = false;
   if(s.isBullish)
      nearLevel = (currentClose <= entryPrice + zone_width && currentClose >= entryPrice - zone_width);
   else
      nearLevel = (currentClose >= entryPrice - zone_width && currentClose <= entryPrice + zone_width);

   if(!nearLevel) return;
   if(!CanTrade()) return;

   // TP is the next higher Fib level (toward Fib0)
   double tpPrice;
   if(fibLevel == 0.382)
      tpPrice = s.fib236;
   else if(fibLevel == 0.5)
      tpPrice = s.fib382;
   else
      tpPrice = s.fib50;

   double lot = CalculateLotSize(entryPrice, slPrice);
   if(lot <= 0) return;

   string epLabel = "EP" + IntegerToString(epIndex);

   if(PlacePendingOrders)
   {
      ENUM_ORDER_TYPE orderType = s.isBullish ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action    = TRADE_ACTION_PENDING;
      request.symbol    = _Symbol;
      request.volume    = lot;
      request.type      = orderType;
      request.price     = NormalizeDouble(entryPrice, _Digits);
      request.sl        = NormalizeDouble(slPrice, _Digits);
      request.tp        = NormalizeDouble(tpPrice, _Digits);
      request.deviation = Slippage;
      request.magic     = MagicNumber;
      request.comment   = "F71_" + s.objPrefix + epLabel;

      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
         {
            s.orderTickets[ticketIdx] = result.order;
            s.traded = true;
            g_dailyTrades++;

            Print("  ", epLabel, " LIMIT: ", s.isBullish ? "BUY" : "SELL",
                  " | Lot: ", lot,
                  " | Entry: ", DoubleToString(entryPrice, _Digits),
                  " | SL: ", DoubleToString(slPrice, _Digits),
                  " | TP: ", DoubleToString(tpPrice, _Digits));

            SendTelegram("Fibo71: " + epLabel + " on " + _Symbol +
               "\n" + (s.isBullish ? "BUY LIMIT" : "SELL LIMIT") + " " + DoubleToString(lot, 2) +
               "\nEntry: " + DoubleToString(entryPrice, _Digits) +
               "\nSL: " + DoubleToString(slPrice, _Digits) +
               "\nTP: " + DoubleToString(tpPrice, _Digits));
         }
      }
   }
   else
   {
      ENUM_ORDER_TYPE orderType = s.isBullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action    = TRADE_ACTION_DEAL;
      request.symbol    = _Symbol;
      request.volume    = lot;
      request.type      = orderType;
      request.sl        = NormalizeDouble(slPrice, _Digits);
      request.tp        = NormalizeDouble(tpPrice, _Digits);
      request.deviation = Slippage;
      request.magic     = MagicNumber;
      request.comment   = "F71_" + s.objPrefix + epLabel;

      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE)
         {
            s.orderTickets[ticketIdx] = result.order;
            s.traded = true;
            g_dailyTrades++;

            Print("  ", epLabel, " MARKET: ", s.isBullish ? "BUY" : "SELL",
                  " | Lot: ", lot,
                  " | Price: ", DoubleToString(result.price, _Digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| TRADING HELPERS                                                   |
//+------------------------------------------------------------------+

double CalculateLotSize(double entryPrice, double slPrice)
{
   if(FixedLot > 0)
      return NormalizeDouble(FixedLot, 2);

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * RiskPercent / 100.0;
   double slDistance  = MathAbs(entryPrice - slPrice);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(slDistance <= 0 || tickSize <= 0 || tickValue <= 0)
      return 0;

   double lot = riskAmount / ((slDistance / tickSize) * tickValue);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));

   return NormalizeDouble(lot, 2);
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            count++;
      }
   }
   return count;
}

bool OrderCancelSafe(ulong ticket, string reason)
{
   if(ticket <= 0) return false;
   if(!OrderSelect(ticket)) return false;

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};
   request.action = TRADE_ACTION_REMOVE;
   request.order  = ticket;

   bool ok = OrderSend(request, result);
   if(ok && result.retcode == TRADE_RETCODE_DONE)
   {
      Print("Order canceled: ", ticket, " | ", reason);
      return true;
   }
   return false;
}

void SendTelegram(string message)
{
   if(!EnableTelegram || TelegramBotToken == "" || TelegramChatId == "")
      return;

   string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage";
   string params = "chat_id=" + TelegramChatId + "&text=" + message + "&parse_mode=HTML";

   char post[], result[];
   string reqHeaders = "Content-Type: application/x-www-form-urlencoded\r\n";
   string resHeaders = "";
   StringToCharArray(params, post, 0, StringLen(params));

   int res = WebRequest("POST", url, reqHeaders, 5000, post, result, resHeaders);
   if(res != 200)
      Print("Telegram error: HTTP ", res);
}

//+------------------------------------------------------------------+
//| DRAWING FUNCTIONS (identical to Pine Script)                      |
//+------------------------------------------------------------------+

void CreateSetupDrawings(SSetup &s, int total)
{
   datetime createTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   datetime futureTime = createTime + PeriodSeconds() * SetupExpiryBars;

   if(ShowFibLines)
   {
      CreateTrendRay(s.objPrefix + "Fib0", createTime, s.fib0, futureTime, s.fib0,
                     ColorFib0, 2, STYLE_SOLID);
      CreateTrendRay(s.objPrefix + "Fib100", createTime, s.fib100, futureTime, s.fib100,
                     ColorFib100, 2, STYLE_SOLID);
      CreateTrendRay(s.objPrefix + "Fib50", createTime, s.fib50, futureTime, s.fib50,
                     ColorFib50, 1, STYLE_SOLID);

      if(ShowEntryZone)
      {
         CreateTrendRay(s.objPrefix + "Fib71", createTime, s.fib71, futureTime, s.fib71,
                        ColorFib71_79, 1, STYLE_DOT);
         CreateTrendRay(s.objPrefix + "Fib79", createTime, s.fib79, futureTime, s.fib79,
                        ColorFib71_79, 1, STYLE_DOT);

         color zoneColor = s.isBullish ?
            ColorToARGB(ColorBullish, 25) : ColorToARGB(ColorBearish, 25);

         string boxName = s.objPrefix + "Zone";
         ObjectCreate(0, boxName, OBJ_RECTANGLE, 0,
                      createTime, s.fib71, futureTime, s.fib79);
         ObjectSetInteger(0, boxName, OBJPROP_COLOR, zoneColor);
         ObjectSetInteger(0, boxName, OBJPROP_FILL, true);
         ObjectSetInteger(0, boxName, OBJPROP_BACK, true);
      }
   }

   if(ShowLabels)
   {
      string labelName = s.objPrefix + "BOS";
      string labelText;
      color  lblColor;

      if(s.isBullish)
      {
         labelText = "BULLISH BOS\n"
            + "TP: " + DoubleToString(s.fib0, _Digits) + "\n"
            + "Entry: " + DoubleToString(s.fib79, _Digits)
            + " - " + DoubleToString(s.fib71, _Digits) + "\n"
            + "SL: " + DoubleToString(s.fib100, _Digits);
         lblColor = ColorToARGB(ColorBullish, 178);
      }
      else
      {
         labelText = "BEARISH BOS\n"
            + "TP: " + DoubleToString(s.fib0, _Digits) + "\n"
            + "Entry: " + DoubleToString(s.fib71, _Digits)
            + " - " + DoubleToString(s.fib79, _Digits) + "\n"
            + "SL: " + DoubleToString(s.fib100, _Digits);
         lblColor = ColorToARGB(ColorBearish, 178);
      }

      ObjectCreate(0, labelName, OBJ_TEXT, 0, createTime, s.fib100);
      ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, lblColor);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
   }
}

void DeleteSetupDrawings(SSetup &s)
{
   ObjectsDeleteAll(0, s.objPrefix);
}

void CreateTrendRay(string name,
                    datetime time1, double price1,
                    datetime time2, double price2,
                    color clr, int width, int style)
{
   ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

void DrawSwingPoints(int total)
{
   int idx = total - 1;
   bool isSwingHigh = true;
   bool isSwingLow  = true;

   for(int i = 1; i <= SwingLookback; i++)
   {
      if(idx - i < 0) continue;
      if(iHigh(_Symbol, PERIOD_CURRENT, idx - i) >= iHigh(_Symbol, PERIOD_CURRENT, idx))
         isSwingHigh = false;
      if(iLow(_Symbol, PERIOD_CURRENT, idx - i) <= iLow(_Symbol, PERIOD_CURRENT, idx))
         isSwingLow = false;
   }

   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, idx);

   if(isSwingHigh && idx > SwingLookback)
   {
      string name = g_prefix + "HH_" + IntegerToString(idx);
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_ARROW_DOWN, 0,
                      barTime, iHigh(_Symbol, PERIOD_CURRENT, idx));
         ObjectSetInteger(0, name, OBJPROP_COLOR, ColorToARGB(clrRed, 127));
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);

         string txtName = name + "_txt";
         ObjectCreate(0, txtName, OBJ_TEXT, 0,
                      barTime, iHigh(_Symbol, PERIOD_CURRENT, idx));
         ObjectSetString(0, txtName, OBJPROP_TEXT, "HH");
         ObjectSetInteger(0, txtName, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, txtName, OBJPROP_FONTSIZE, 6);
         ObjectSetInteger(0, txtName, OBJPROP_ANCHOR, ANCHOR_LOWER);
      }
   }

   if(isSwingLow && idx > SwingLookback)
   {
      string name = g_prefix + "LL_" + IntegerToString(idx);
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_ARROW_UP, 0,
                      barTime, iLow(_Symbol, PERIOD_CURRENT, idx));
         ObjectSetInteger(0, name, OBJPROP_COLOR, ColorToARGB(clrLime, 127));
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);

         string txtName = name + "_txt";
         ObjectCreate(0, txtName, OBJ_TEXT, 0,
                      barTime, iLow(_Symbol, PERIOD_CURRENT, idx));
         ObjectSetString(0, txtName, OBJPROP_TEXT, "LL");
         ObjectSetInteger(0, txtName, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, txtName, OBJPROP_FONTSIZE, 6);
         ObjectSetInteger(0, txtName, OBJPROP_ANCHOR, ANCHOR_UPPER);
      }
   }
}

//+------------------------------------------------------------------+
//| INFO TABLE                                                        |
//+------------------------------------------------------------------+
void UpdateInfoTable(int total)
{
   string tblPrefix = g_prefix + "TBL_";

   int activeBull = 0, activeBear = 0, lastIdx = -1;
   int idx = total - 1;

   for(int i = 0; i < ArraySize(g_setups); i++)
   {
      if(g_setups[i].hitBar < 0)
      {
         if(g_setups[i].isBullish) activeBull++; else activeBear++;
         lastIdx = i;
      }
   }

   int y = 10, x = 10;

   // Header
   DrawTableLabel(tblPrefix + "h", x, y, "CP 2.0 Bot",
                  clrWhite, ColorToARGB(clrDodgerBlue, 153), ANCHOR_LEFT_UPPER, 140, 20);

   // Status
   y += 22;
   string statusText;
   color  statusColor;
   if(activeBull > 0)
   { statusText = "BULLISH x" + IntegerToString(activeBull); statusColor = clrLime; }
   else if(activeBear > 0)
   { statusText = "BEARISH x" + IntegerToString(activeBear); statusColor = clrRed; }
   else
   { statusText = "NEUTRAL"; statusColor = clrWhite; }
   DrawTableLabel(tblPrefix + "s", x, y, statusText, statusColor,
                  ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 140, 20);

   // Daily trades
   y += 22;
   DrawTableLabel(tblPrefix + "dt_l", x, y, "Today", clrWhite,
                  ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
   DrawTableLabel(tblPrefix + "dt_v", x + 62, y,
                  IntegerToString(g_dailyTrades) + "/" + IntegerToString(MaxDailyTrades),
                  g_dailyTrades >= MaxDailyTrades ? clrOrangeRed : clrWhite,
                  ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 78, 18);

   // Open positions
   int openPos = CountOpenPositions();
   y += 20;
   DrawTableLabel(tblPrefix + "op_l", x, y, "Open", clrWhite,
                  ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
   DrawTableLabel(tblPrefix + "op_v", x + 62, y,
                  IntegerToString(openPos) + "/" + IntegerToString(MaxOpenPositions),
                  openPos >= MaxOpenPositions ? clrOrangeRed : clrWhite,
                  ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 78, 18);

   // Setup details
   if(lastIdx >= 0)
   {
      SSetup &last = g_setups[lastIdx];

      y += 22;
      DrawTableLabel(tblPrefix + "tp_l", x, y, "TP (0%)", clrLime,
                     ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
      DrawTableLabel(tblPrefix + "tp_v", x + 62, y, DoubleToString(last.fib0, _Digits),
                     clrLime, ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 78, 18);

      y += 20;
      DrawTableLabel(tblPrefix + "50_l", x, y, "50%", clrDodgerBlue,
                     ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
      DrawTableLabel(tblPrefix + "50_v", x + 62, y, DoubleToString(last.fib50, _Digits),
                     clrDodgerBlue, ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 78, 18);

      y += 20;
      string entryText = last.isBullish ?
         DoubleToString(last.fib79, _Digits) + " - " + DoubleToString(last.fib71, _Digits) :
         DoubleToString(last.fib71, _Digits) + " - " + DoubleToString(last.fib79, _Digits);
      DrawTableLabel(tblPrefix + "ez_l", x, y, "Entry", clrDodgerBlue,
                     ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
      DrawTableLabel(tblPrefix + "ez_v", x + 62, y, entryText,
                     clrDodgerBlue, ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 78, 18);

      y += 20;
      DrawTableLabel(tblPrefix + "sl_l", x, y, "SL (100%)", clrRed,
                     ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
      DrawTableLabel(tblPrefix + "sl_v", x + 62, y, DoubleToString(last.fib100, _Digits),
                     clrRed, ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 78, 18);

      y += 20;
      DrawTableLabel(tblPrefix + "ac_l", x, y, "Setups", clrWhite,
                     ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
      DrawTableLabel(tblPrefix + "ac_v", x + 62, y,
                     IntegerToString(activeBull + activeBear) + "/" + IntegerToString(MaxActiveSetups),
                     clrWhite, ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 78, 18);

      if(SetupExpiryEnabled)
      {
         y += 20;
         int barsLeft = SetupExpiryBars - (idx - last.createdBar);
         color expColor = barsLeft <= 5 ? clrOrangeRed : clrWhite;
         DrawTableLabel(tblPrefix + "ex_l", x, y, "Expires", clrWhite,
                        ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
         DrawTableLabel(tblPrefix + "ex_v", x + 62, y,
                        IntegerToString(MathMax(barsLeft, 0)) + " bars",
                        expColor, ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 78, 18);
      }
   }
}

void DrawTableLabel(string name, int x, int y, string text,
                    color txtColor, color bgColor,
                    int anchor, int width, int height)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtColor);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
}
//+------------------------------------------------------------------+
