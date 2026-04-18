//+------------------------------------------------------------------+
//|                                    Fibo71_CP2_Indicator.mq5      |
//|                         Fibo 71 CP 2.0 - BOS + Imbalance         |
//|                   Exact replica of Pine Script indicator          |
//+------------------------------------------------------------------+
#property copyright "Fibo 71 Bot - CP 2.0 Strategy"
#property link      ""
#property version   "1.00"
#property description "Fibo 71 CP 2.0 - BOS + Imbalance Indicator"
#property description "Exact replica of TradingView Pine Script"
#property indicator_chart_window
#property indicator_plots   0
#property indicator_buffers 0
#property indicator_label   "Fibo 71 CP 2.0"

//+------------------------------------------------------------------+
//| Input Parameters (matching Pine Script exactly)                   |
//+------------------------------------------------------------------+

//--- Fibonacci Settings
input group "Fibonacci"
input double FibEntryMin        = 0.71;  // Fib Entry Min (0.5-0.95)
input double FibEntryMax        = 0.79;  // Fib Entry Max (0.5-0.95)

//--- BOS Detection Settings
input group "BOS Detection"
input int    BOSLookback        = 50;    // BOS Lookback (bars)
input int    SwingLookback      = 5;     // Swing Lookback (bars on each side)
input double MinImbalancePips   = 10.0;  // Min Imbalance (pips)

//--- Filter Settings
input group "Filters"
input bool   EnableImbalance      = true;  // Require Imbalance
input bool   EnableLiquiditySweep = true;  // Require Liquidity Sweep

//--- Setup Duration
input group "Setup Duration"
input int    SetupExpiryBars    = 500;   // Setup Expiry (bars)
input bool   SetupExpiryEnabled = true;  // Enable Setup Expiry

//--- Display Settings
input group "Display"
input bool   ShowSwingPoints    = true;  // Show Swing Points
input bool   ShowFibLines       = true;  // Show Fibonacci Lines
input bool   ShowLabels         = true;  // Show Labels
input bool   ShowEntryZone      = true;  // Show Entry Zone
input int    MaxActiveSetups    = 5;     // Max Active Setups (1-10)

//--- Color Settings
input group "Colors"
input color  ColorBullish       = clrLime;                    // Bullish Color
input color  ColorBearish       = clrRed;                     // Bearish Color
input color  ColorFib0          = clrLime;                    // Fib 0% (TP)
input color  ColorFib50         = clrDodgerBlue;              // Fib 50%
input color  ColorFib100        = clrRed;                     // Fib 100% (SL)
input color  ColorFib71_79      = clrDodgerBlue;              // Fib 71%/79% (Entry)
input color  ColorEntryZone     = C'0,0,255';                 // Entry Zone Color
input color  ColorImbalance     = C'128,0,128';               // Imbalance Zone

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
   double fib100;          // SL level
   double fib71;           // Entry zone boundary
   double fib79;           // Entry zone boundary
   int    createdBar;      // Bar index when created
   int    hitBar;          // Bar when TP/SL hit (-1 = active)
   int    hitResult;       // 0=active, 1=TP, 2=SL, 3=expired
   string objPrefix;       // Object name prefix for this setup
};

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
SSetup  g_setups[];           // Array of active setups
double  g_swingHigh = 0;     // Current swing high price
double  g_swingLow  = 0;     // Current swing low price
int     g_swingHighIdx = -1; // Bar index of swing high
int     g_swingLowIdx  = -1; // Bar index of swing low
int     g_setupCounter = 0;  // Monotonic setup ID counter
datetime g_lastBarTime = 0;  // Last processed bar time
string  g_prefix = "F71_";   // Object name prefix

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate parameters
   if(FibEntryMin >= FibEntryMax)
   {
      Print("ERROR: FibEntryMin must be less than FibEntryMax");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(FibEntryMin < 0.5 || FibEntryMax > 0.95)
   {
      Print("ERROR: Fibonacci entry values must be between 0.5 and 0.95");
      return(INIT_PARAMETERS_INCORRECT);
   }

   ArrayResize(g_setups, 0);
   g_setupCounter = 0;

   Print("=== Fibo 71 CP 2.0 Indicator Started ===");
   Print("Symbol: ", _Symbol, " | Timeframe: ", EnumToString(Period()));
   Print("Fib Entry: ", FibEntryMin, " - ", FibEntryMax);
   Print("BOS Lookback: ", BOSLookback, " | Swing Lookback: ", SwingLookback);
   Print("Imbalance: ", EnableImbalance ? "ON" : "OFF",
         " | Liquidity Sweep: ", EnableLiquiditySweep ? "ON" : "OFF");
   Print("Max Active Setups: ", MaxActiveSetups);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization - clean up all objects                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);
   ChartRedraw(0);
   Print("=== Fibo 71 CP 2.0 Indicator Stopped ===");
}

//+------------------------------------------------------------------+
//| Main calculation function                                         |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // Need minimum bars
   if(rates_total < SwingLookback + 10)
      return(rates_total);

   // Process only on new bar
   static datetime lastBar = 0;
   if(time[rates_total - 1] == lastBar)
      return(rates_total);
   lastBar = time[rates_total - 1];

   int total = rates_total;

   // ---- STEP 1: Swing Point Detection ----
   DetectSwingPoints(high, low, total);

   // ---- STEP 2: BOS Detection ----
   bool bullishBOS = false;
   bool bearishBOS = false;
   DetectBOS(high, low, close, total, bullishBOS, bearishBOS);

   // ---- STEP 3: Imbalance Detection ----
   bool bearishImbalance = false;
   bool bullishImbalance = false;
   DetectImbalance(high, low, close, total, bearishImbalance, bullishImbalance);

   // ---- STEP 4: Liquidity Sweep Detection (only when BOS detected) ----
   bool bearishLiqSweep = false;
   bool bullishLiqSweep = false;
   DetectLiquiditySweep(high, low, close, total, bearishBOS, bullishBOS, bearishLiqSweep, bullishLiqSweep);

   // ---- STEP 5: Check if BOS meets criteria ----
   bool newBearishSetup = bearishBOS &&
                          (!EnableImbalance || bearishImbalance) &&
                          (!EnableLiquiditySweep || bearishLiqSweep);

   bool newBullishSetup = bullishBOS &&
                          (!EnableImbalance || bullishImbalance) &&
                          (!EnableLiquiditySweep || bullishLiqSweep);

   // ---- STEP 6: Check existing setups for TP/SL/Expiry ----
   CheckExistingSetups(high, low, total);

   // ---- STEP 7: Create new setup if BOS detected ----
   if(newBearishSetup)
      CreateSetup(false, total);  // false = bearish

   if(newBullishSetup)
      CreateSetup(true, total);   // true = bullish

   // ---- STEP 8: Draw swing points ----
   if(ShowSwingPoints)
      DrawSwingPoints(high, low, time, total);

   // ---- STEP 9: Check price in entry zone ----
   CheckEntryZone(close, total);

   // ---- STEP 10: Update info table ----
   UpdateInfoTable(close, total);

   ChartRedraw(0);
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Detect swing points                                               |
//+------------------------------------------------------------------+
void DetectSwingPoints(const double &high[],
                       const double &low[],
                       int total)
{
   // Check if bar at index (total-1) is a swing point
   // A bar is swing high if its high > high of surrounding SwingLookback bars
   int idx = total - 1;  // Current (latest) bar

   // Check past bars (bars to the left)
   bool isSwingHigh = true;
   bool isSwingLow  = true;

   for(int i = 1; i <= SwingLookback; i++)
   {
      if(idx - i < 0) continue;
      if(high[idx - i] >= high[idx])
         isSwingHigh = false;
      if(low[idx - i] <= low[idx])
         isSwingLow = false;
   }

   if(isSwingHigh)
   {
      g_swingHigh    = high[idx];
      g_swingHighIdx = idx;
   }

   if(isSwingLow)
   {
      g_swingLow    = low[idx];
      g_swingLowIdx = idx;
   }
}

//+------------------------------------------------------------------+
//| Detect Break of Structure                                         |
//+------------------------------------------------------------------+
void DetectBOS(const double &high[],
               const double &low[],
               const double &close[],
               int total,
               bool &bullishBOS,
               bool &bearishBOS)
{
   bullishBOS = false;
   bearishBOS = false;

   int idx = total - 1;  // Current bar
   int barsFromStart = total - 1;  // Approximate bar index

   // Bearish BOS: close < swingLow, swing is 3-50 bars old
   if(g_swingLow > 0 && close[idx] < g_swingLow)
   {
      int swingAge = idx - g_swingLowIdx;
      if(swingAge >= 3 && swingAge <= BOSLookback)
         bearishBOS = true;
   }

   // Bullish BOS: close > swingHigh, swing is 3-50 bars old
   if(g_swingHigh > 0 && close[idx] > g_swingHigh)
   {
      int swingAge = idx - g_swingHighIdx;
      if(swingAge >= 3 && swingAge <= BOSLookback)
         bullishBOS = true;
   }
}

//+------------------------------------------------------------------+
//| Detect Imbalance (IPA)                                            |
//+------------------------------------------------------------------+
void DetectImbalance(const double &high[],
                     const double &low[],
                     const double &close[],
                     int total,
                     bool &bearishImbalance,
                     bool &bullishImbalance)
{
   bearishImbalance = false;
   bullishImbalance = false;

   if(total < 3) return;

   int idx = total - 1;
   double pipMult = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   double minGap  = MinImbalancePips * pipMult;

   // Bearish imbalance: low[2] > high (gap between bar[2] and current bar)
   if(low[idx - 2] > high[idx] && (low[idx - 2] - high[idx]) >= minGap)
      bearishImbalance = true;

   // Bullish imbalance: high[2] < low (gap between bar[2] and current bar)
   if(high[idx - 2] < low[idx] && (low[idx] - high[idx - 2]) >= minGap)
      bullishImbalance = true;
}

//+------------------------------------------------------------------+
//| Detect Liquidity Sweep                                            |
//+------------------------------------------------------------------+
// Pine Script: liquidity sweep is ONLY checked when BOS is detected
// if bearishBOS -> check high[i] > swingHigh && close[i] < swingHigh
// if bullishBOS -> check low[i] < swingLow && close[i] > swingLow
void DetectLiquiditySweep(const double &high[],
                          const double &low[],
                          const double &close[],
                          int total,
                          bool bearishBOS,
                          bool bullishBOS,
                          bool &bearishLiqSweep,
                          bool &bullishLiqSweep)
{
   bearishLiqSweep = false;
   bullishLiqSweep = false;

   int lookbackSweep = 5;
   int idx = total - 1;

   // Only check bearish sweep when bearish BOS is detected
   if(bearishBOS && g_swingHigh > 0)
   {
      for(int i = 1; i <= lookbackSweep; i++)
      {
         if(idx - i < 0) break;
         if(high[idx - i] > g_swingHigh && close[idx - i] < g_swingHigh)
         {
            bearishLiqSweep = true;
            break;
         }
      }
   }

   // Only check bullish sweep when bullish BOS is detected
   if(bullishBOS && g_swingLow > 0)
   {
      for(int i = 1; i <= lookbackSweep; i++)
      {
         if(idx - i < 0) break;
         if(low[idx - i] < g_swingLow && close[idx - i] > g_swingLow)
         {
            bullishLiqSweep = true;
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check existing setups for TP/SL hit or expiry                     |
//+------------------------------------------------------------------+
void CheckExistingSetups(const double &high[],
                         const double &low[],
                         int total)
{
   int idx = total - 1;

   for(int i = 0; i < ArraySize(g_setups); i++)
   {
      SSetup &s = g_setups[i];

      // Only check active setups
      if(s.hitBar >= 0) continue;

      // Check expiry
      bool isExpired = SetupExpiryEnabled &&
                       ((idx - s.createdBar) >= SetupExpiryBars);

      if(isExpired)
      {
         DeleteSetupDrawings(s);
         s.hitBar    = idx;
         s.hitResult = 3;  // expired

         if(ShowLabels)
         {
            string name = s.objPrefix + "Expired";
            double lblPrice = s.fib100;
            ObjectCreate(0, name, OBJ_TEXT, 0,
                         iTime(_Symbol, PERIOD_CURRENT, total - 1 - idx + s.createdBar),
                         lblPrice);
            ObjectSetString(0, name, OBJPROP_TEXT, "EXPIRED");
            ObjectSetInteger(0, name, OBJPROP_COLOR, clrGray);
            ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
         }
      }
      else
      {
         // Check TP hit
         bool hitTP = s.isBullish ? (low[idx] <= s.fib0) : (high[idx] >= s.fib0);
         // Check SL hit
         bool hitSL = s.isBullish ? (high[idx] >= s.fib100) : (low[idx] <= s.fib100);

         if(hitTP)
         {
            s.hitBar    = idx;
            s.hitResult = 1;  // TP

            if(ShowLabels)
            {
               // Delete old BOS label, create TP label
               ObjectDelete(0, s.objPrefix + "BOS");
               string name = s.objPrefix + "TPHit";
               ObjectCreate(0, name, OBJ_TEXT, 0,
                            iTime(_Symbol, PERIOD_CURRENT, 0), s.fib0);
               ObjectSetString(0, name, OBJPROP_TEXT, CharToString(0x2705) + " TP HIT");
               ObjectSetInteger(0, name, OBJPROP_COLOR, clrLime);
               ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
            }

            // Widen Fib0 line
            if(ShowFibLines)
            {
               ObjectSetInteger(0, s.objPrefix + "Fib0", OBJPROP_WIDTH, 3);
            }
         }
         else if(hitSL)
         {
            s.hitBar    = idx;
            s.hitResult = 2;  // SL

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

            // Widen Fib100 line
            if(ShowFibLines)
            {
               ObjectSetInteger(0, s.objPrefix + "Fib100", OBJPROP_WIDTH, 3);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Create a new setup                                                |
//+------------------------------------------------------------------+
void CreateSetup(bool isBullish, int total)
{
   int idx = total - 1;
   double range, fib0, fib100, fib236, fib382, fib50, fib618, fib71, fib79;

   if(!isBullish)
   {
      // Bearish setup
      fib0   = g_swingLow;       // TP
      fib100 = g_swingHigh;      // SL
      range  = g_swingHigh - g_swingLow;
      fib236 = g_swingLow + range * 0.236;
      fib382 = g_swingLow + range * 0.382;
      fib50  = g_swingLow + range * 0.5;
      fib618 = g_swingLow + range * 0.618;
      fib71  = g_swingLow + range * FibEntryMin;
      fib79  = g_swingLow + range * FibEntryMax;
   }
   else
   {
      // Bullish setup
      fib0   = g_swingHigh;      // TP
      fib100 = g_swingLow;       // SL
      range  = g_swingHigh - g_swingLow;
      fib236 = g_swingHigh - range * 0.236;
      fib382 = g_swingHigh - range * 0.382;
      fib50  = g_swingHigh - range * 0.5;
      fib618 = g_swingHigh - range * 0.618;
      fib71  = g_swingHigh - range * FibEntryMin;
      fib79  = g_swingHigh - range * FibEntryMax;
   }

   // Create setup struct
   SSetup s;
   s.isBullish   = isBullish;
   s.fib0        = fib0;
   s.fib236      = fib236;
   s.fib382      = fib382;
   s.fib50       = fib50;
   s.fib618      = fib618;
   s.fib100      = fib100;
   s.fib71       = fib71;
   s.fib79       = fib79;
   s.createdBar  = idx;
   s.hitBar      = -1;  // active
   s.hitResult   = 0;   // active
   s.objPrefix   = g_prefix + "S" + IntegerToString(g_setupCounter) + "_";
   g_setupCounter++;

   // Draw setup
   CreateSetupDrawings(s, total);

   // Add to array
   int size = ArraySize(g_setups);
   ArrayResize(g_setups, size + 1);
   g_setups[size] = s;

   // Limit active setups - remove oldest
   while(ArraySize(g_setups) > MaxActiveSetups)
   {
      DeleteSetupDrawings(g_setups[0]);
      // Shift array left
      for(int i = 0; i < ArraySize(g_setups) - 1; i++)
         g_setups[i] = g_setups[i + 1];
      ArrayResize(g_setups, ArraySize(g_setups) - 1);
   }

   // Alert
   string dir = isBullish ? "BULLISH" : "BEARISH";
   string entryZone = isBullish ?
      DoubleToString(fib79, _Digits) + " - " + DoubleToString(fib71, _Digits) :
      DoubleToString(fib71, _Digits) + " - " + DoubleToString(fib79, _Digits);

   Alert("Fibo71: ", dir, " BOS on ", _Symbol,
         " | Entry Zone: ", entryZone,
         " | TP: ", DoubleToString(fib0, _Digits),
         " | SL: ", DoubleToString(fib100, _Digits));

   Print("=== ", dir, " BOS DETECTED ===");
   Print("  TP (0%): ", DoubleToString(fib0, _Digits));
   Print("  50%: ", DoubleToString(fib50, _Digits));
   Print("  Entry Zone: ", entryZone);
   Print("  SL (100%): ", DoubleToString(fib100, _Digits));
}

//+------------------------------------------------------------------+
//| Create drawing objects for a setup                                |
//+------------------------------------------------------------------+
void CreateSetupDrawings(SSetup &s, int total)
{
   datetime createTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   datetime futureTime = createTime + PeriodSeconds() * SetupExpiryBars;

   if(ShowFibLines)
   {
      // Fib0 line (TP) - lime, width 2, solid, ray right
      CreateTrendRay(s.objPrefix + "Fib0", createTime, s.fib0, futureTime, s.fib0,
                     ColorFib0, 2, STYLE_SOLID);

      // Fib100 line (SL) - red, width 2, solid, ray right
      CreateTrendRay(s.objPrefix + "Fib100", createTime, s.fib100, futureTime, s.fib100,
                     ColorFib100, 2, STYLE_SOLID);

      // Fib50 line - blue, width 1, solid, ray right
      CreateTrendRay(s.objPrefix + "Fib50", createTime, s.fib50, futureTime, s.fib50,
                     ColorFib50, 1, STYLE_SOLID);

      if(ShowEntryZone)
      {
         // Fib71 line - dotted
         CreateTrendRay(s.objPrefix + "Fib71", createTime, s.fib71, futureTime, s.fib71,
                        ColorFib71_79, 1, STYLE_DOT);

         // Fib79 line - dotted
         CreateTrendRay(s.objPrefix + "Fib79", createTime, s.fib79, futureTime, s.fib79,
                        ColorFib71_79, 1, STYLE_DOT);

         // Entry zone box
         color zoneColor = s.isBullish ?
            ColorToARGB(ColorBullish, 25) :    // 10% opacity = 90% transparent
            ColorToARGB(ColorBearish, 25);

         string boxName = s.objPrefix + "Zone";
         ObjectCreate(0, boxName, OBJ_RECTANGLE, 0,
                      createTime, s.fib71, futureTime, s.fib79);
         ObjectSetInteger(0, boxName, OBJPROP_COLOR, zoneColor);
         ObjectSetInteger(0, boxName, OBJPROP_FILL, true);
         ObjectSetInteger(0, boxName, OBJPROP_BACK, true);
         ObjectSetString(0, boxName, OBJPROP_TOOLTIP,
            s.isBullish ? "Bullish Entry Zone" : "Bearish Entry Zone");
      }
   }

   if(ShowLabels)
   {
      // BOS label at fib100 price
      string labelName = s.objPrefix + "BOS";
      string labelText;
      color  lblColor;
      int    fontSize = 8;

      if(s.isBullish)
      {
         labelText = "BULLISH BOS\n"
                   + "TP: " + DoubleToString(s.fib0, _Digits) + "\n"
                   + "Entry: " + DoubleToString(s.fib79, _Digits)
                   + " - " + DoubleToString(s.fib71, _Digits) + "\n"
                   + "SL: " + DoubleToString(s.fib100, _Digits);
         lblColor = ColorToARGB(ColorBullish, 178);  // 70% opacity
      }
      else
      {
         labelText = "BEARISH BOS\n"
                   + "TP: " + DoubleToString(s.fib0, _Digits) + "\n"
                   + "Entry: " + DoubleToString(s.fib71, _Digits)
                   + " - " + DoubleToString(s.fib79, _Digits) + "\n"
                   + "SL: " + DoubleToString(s.fib100, _Digits);
         lblColor = ColorToARGB(ColorBearish, 178);  // 70% opacity
      }

      ObjectCreate(0, labelName, OBJ_TEXT, 0, createTime, s.fib100);
      ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, lblColor);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, labelName, OBJPROP_TOOLTIP, labelText);
   }
}

//+------------------------------------------------------------------+
//| Delete all drawing objects for a setup                            |
//+------------------------------------------------------------------+
void DeleteSetupDrawings(SSetup &s)
{
   ObjectsDeleteAll(0, s.objPrefix);
}

//+------------------------------------------------------------------+
//| Create a trend line with ray right                                |
//+------------------------------------------------------------------+
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
   ObjectSetString(0, name, OBJPROP_TOOLTIP, DoubleToString(price1, _Digits));
}

//+------------------------------------------------------------------+
//| Draw swing point markers                                          |
//+------------------------------------------------------------------+
void DrawSwingPoints(const double &high[],
                     const double &low[],
                     const datetime &time[],
                     int total)
{
   int idx = total - 1;

   // Check if current bar is swing high
   bool isSwingHigh = true;
   bool isSwingLow  = true;

   for(int i = 1; i <= SwingLookback; i++)
   {
      if(idx - i < 0) continue;
      if(high[idx - i] >= high[idx])
         isSwingHigh = false;
      if(low[idx - i] <= low[idx])
         isSwingLow = false;
   }

   if(isSwingHigh && idx > SwingLookback)
   {
      string name = g_prefix + "HH_" + IntegerToString(idx);
      if(ObjectFind(0, name) < 0)  // Don't duplicate
      {
         // Arrow down above the high
         ObjectCreate(0, name, OBJ_ARROW_DOWN, 0,
                      time[idx], high[idx]);
         ObjectSetInteger(0, name, OBJPROP_COLOR, ColorToARGB(clrRed, 127));
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);

         // Text label
         string txtName = name + "_txt";
         ObjectCreate(0, txtName, OBJ_TEXT, 0, time[idx], high[idx]);
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
         // Arrow up below the low
         ObjectCreate(0, name, OBJ_ARROW_UP, 0,
                      time[idx], low[idx]);
         ObjectSetInteger(0, name, OBJPROP_COLOR, ColorToARGB(clrLime, 127));
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);

         // Text label
         string txtName = name + "_txt";
         ObjectCreate(0, txtName, OBJ_TEXT, 0, time[idx], low[idx]);
         ObjectSetString(0, txtName, OBJPROP_TEXT, "LL");
         ObjectSetInteger(0, txtName, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, txtName, OBJPROP_FONTSIZE, 6);
         ObjectSetInteger(0, txtName, OBJPROP_ANCHOR, ANCHOR_UPPER);
      }
   }
}

//+------------------------------------------------------------------+
//| Check if price is in any active entry zone                        |
//+------------------------------------------------------------------+
void CheckEntryZone(const double &close[], int total)
{
   int idx = total - 1;

   for(int i = 0; i < ArraySize(g_setups); i++)
   {
      SSetup &s = g_setups[i];
      if(s.hitBar >= 0) continue;  // Skip inactive setups

      bool inZone = false;
      if(s.isBullish)
         inZone = (close[idx] <= s.fib71 && close[idx] >= s.fib79);
      else
         inZone = (close[idx] >= s.fib79 && close[idx] <= s.fib71);

      if(inZone)
      {
         Print("Price in Entry Zone | ", _Symbol,
               " | Price: ", DoubleToString(close[idx], _Digits),
               " | Zone: ", DoubleToString(s.fib71, _Digits), " - ",
               DoubleToString(s.fib79, _Digits));
      }
   }
}

//+------------------------------------------------------------------+
//| Update info table (top-right corner)                              |
//+------------------------------------------------------------------+
void UpdateInfoTable(const double &close[], int total)
{
   string tblPrefix = g_prefix + "TBL_";

   // Count active setups
   int activeBullish = 0;
   int activeBearish = 0;
   int lastActiveIdx = -1;

   for(int i = 0; i < ArraySize(g_setups); i++)
   {
      if(g_setups[i].hitBar < 0)  // Active
      {
         if(g_setups[i].isBullish) activeBullish++;
         else activeBearish++;
         lastActiveIdx = i;
      }
   }

   // Header row
   int y = 10;
   int x = 10;
   DrawTableLabel(tblPrefix + "h", x, y, "CP 2.0 Status",
                  clrWhite, ColorToARGB(clrDodgerBlue, 153), ANCHOR_LEFT_UPPER, 120, 20);

   // Status
   y += 22;
   string statusText;
   color  statusColor;
   if(activeBullish > 0)
   {
      statusText  = "BULLISH x" + IntegerToString(activeBullish);
      statusColor = clrLime;
   }
   else if(activeBearish > 0)
   {
      statusText  = "BEARISH x" + IntegerToString(activeBearish);
      statusColor = clrRed;
   }
   else
   {
      statusText  = "NEUTRAL";
      statusColor = clrWhite;
   }
   DrawTableLabel(tblPrefix + "s", x, y, statusText, statusColor,
                  ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 120, 20);

   // Show last active setup details
   if(lastActiveIdx >= 0)
   {
      SSetup &last = g_setups[lastActiveIdx];
      int idx = total - 1;

      // TP (0%)
      y += 22;
      DrawTableLabel(tblPrefix + "tp_l", x, y, "TP (0%)", clrLime,
                     ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
      DrawTableLabel(tblPrefix + "tp_v", x + 62, y, DoubleToString(last.fib0, _Digits),
                     clrLime, ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 70, 18);

      // 50%
      y += 20;
      DrawTableLabel(tblPrefix + "50_l", x, y, "50%", clrDodgerBlue,
                     ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
      DrawTableLabel(tblPrefix + "50_v", x + 62, y, DoubleToString(last.fib50, _Digits),
                     clrDodgerBlue, ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 70, 18);

      // Entry Zone
      y += 20;
      string entryText = last.isBullish ?
         DoubleToString(last.fib79, _Digits) + " - " + DoubleToString(last.fib71, _Digits) :
         DoubleToString(last.fib71, _Digits) + " - " + DoubleToString(last.fib79, _Digits);
      DrawTableLabel(tblPrefix + "ez_l", x, y, "Entry Zone", clrDodgerBlue,
                     ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
      DrawTableLabel(tblPrefix + "ez_v", x + 62, y, entryText,
                     clrDodgerBlue, ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 70, 18);

      // SL (100%)
      y += 20;
      DrawTableLabel(tblPrefix + "sl_l", x, y, "SL (100%)", clrRed,
                     ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
      DrawTableLabel(tblPrefix + "sl_v", x + 62, y, DoubleToString(last.fib100, _Digits),
                     clrRed, ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 70, 18);

      // Active Setups count
      y += 20;
      DrawTableLabel(tblPrefix + "ac_l", x, y, "Active", clrWhite,
                     ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
      DrawTableLabel(tblPrefix + "ac_v", x + 62, y,
                     IntegerToString(activeBullish + activeBearish) + "/" + IntegerToString(MaxActiveSetups),
                     clrWhite, ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 70, 18);

      // Expiry countdown
      if(SetupExpiryEnabled)
      {
         y += 20;
         int barsLeft = SetupExpiryBars - (idx - last.createdBar);
         color expColor = barsLeft <= 5 ? clrOrangeRed : clrWhite;
         DrawTableLabel(tblPrefix + "ex_l", x, y, "Expires", clrWhite,
                        ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 60, 18);
         DrawTableLabel(tblPrefix + "ex_v", x + 62, y,
                        IntegerToString(MathMax(barsLeft, 0)) + " bars",
                        expColor, ColorToARGB(clrBlack, 200), ANCHOR_LEFT_UPPER, 70, 18);
      }
   }
}

//+------------------------------------------------------------------+
//| Draw a label for the info table                                   |
//+------------------------------------------------------------------+
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
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}
//+------------------------------------------------------------------+
