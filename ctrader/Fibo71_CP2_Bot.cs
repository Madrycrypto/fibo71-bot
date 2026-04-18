// =====================================================================
// Fibo71 CP 2.0 Bot - cTrader cBot
// Exact replica of TradingView Pine Script indicator + trading
// =====================================================================
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using cAlgo.API;
using cAlgo.API.Indicators;
using cAlgo.API.Internals;

namespace Fibo71CP2
{
    [Robot(TimeZone = TimeZones.Utc, AccessRights = AccessRights.FullAccess)]
    public class Fibo71CP2Bot : Robot
    {
        // ═══════════════════════════════════════════════════════════════
        // PARAMETERS (matching Pine Script exactly)
        // ═══════════════════════════════════════════════════════════════

        // Fibonacci Settings
        [Parameter("Fib Entry Min", Group = "Fibonacci", DefaultValue = 0.71, MinValue = 0.5, MaxValue = 0.95, Step = 0.01)]
        public double FibEntryMin { get; set; }

        [Parameter("Fib Entry Max", Group = "Fibonacci", DefaultValue = 0.79, MinValue = 0.5, MaxValue = 0.95, Step = 0.01)]
        public double FibEntryMax { get; set; }

        // BOS Detection
        [Parameter("BOS Lookback", Group = "BOS Detection", DefaultValue = 50, MinValue = 10, MaxValue = 200)]
        public int BOSLookback { get; set; }

        [Parameter("Swing Lookback", Group = "BOS Detection", DefaultValue = 5, MinValue = 3, MaxValue = 20)]
        public int SwingLookback { get; set; }

        [Parameter("Min Imbalance Pips", Group = "BOS Detection", DefaultValue = 10.0, MinValue = 1)]
        public double MinImbalancePips { get; set; }

        // Filters
        [Parameter("Require Imbalance", Group = "Filters", DefaultValue = true)]
        public bool EnableImbalance { get; set; }

        [Parameter("Require Liquidity Sweep", Group = "Filters", DefaultValue = true)]
        public bool EnableLiquiditySweep { get; set; }

        // Setup Duration
        [Parameter("Setup Expiry Bars", Group = "Setup Duration", DefaultValue = 500, MinValue = 5, MaxValue = 5000, Step = 5)]
        public int SetupExpiryBars { get; set; }

        [Parameter("Enable Setup Expiry", Group = "Setup Duration", DefaultValue = true)]
        public bool SetupExpiryEnabled { get; set; }

        // Display
        [Parameter("Show Swing Points", Group = "Display", DefaultValue = true)]
        public bool ShowSwingPoints { get; set; }

        [Parameter("Show Fib Lines", Group = "Display", DefaultValue = true)]
        public bool ShowFibLines { get; set; }

        [Parameter("Show Labels", Group = "Display", DefaultValue = true)]
        public bool ShowLabels { get; set; }

        [Parameter("Show Entry Zone", Group = "Display", DefaultValue = true)]
        public bool ShowEntryZone { get; set; }

        [Parameter("Max Active Setups", Group = "Display", DefaultValue = 5, MinValue = 1, MaxValue = 10)]
        public int MaxActiveSetups { get; set; }

        // Trading
        [Parameter("Risk %", Group = "Trading", DefaultValue = 1.0, MinValue = 0.1, MaxValue = 5.0, Step = 0.1)]
        public double RiskPercent { get; set; }

        [Parameter("Enable Trading", Group = "Trading", DefaultValue = false)]
        public bool EnableTrading { get; set; }

        [Parameter("Max Daily Trades", Group = "Trading", DefaultValue = 3, MinValue = 1, MaxValue = 10)]
        public int MaxDailyTrades { get; set; }

        // Telegram
        [Parameter("Enable Telegram", Group = "Telegram", DefaultValue = false)]
        public bool EnableTelegram { get; set; }

        [Parameter("Bot Token", Group = "Telegram", DefaultValue = "")]
        public string BotToken { get; set; }

        [Parameter("Chat ID", Group = "Telegram", DefaultValue = "")]
        public string ChatId { get; set; }

        // ═══════════════════════════════════════════════════════════════
        // SETUP CLASS
        // ═══════════════════════════════════════════════════════════════

        private class Setup
        {
            public bool IsBullish;
            public double Fib0, Fib236, Fib382, Fib50, Fib618, Fib100;
            public double Fib71, Fib79;
            public int CreatedBarIndex;
            public int HitBarIndex;     // -1 = active
            public int HitResult;       // 0=active, 1=TP, 2=SL, 3=expired
            public string SetupId;

            // Chart object IDs for removal
            public string LineFib0Id, LineFib100Id, LineFib50Id;
            public string LineFib71Id, LineFib79Id;
            public string ZoneId, BosLabelId, HitLabelId;
        }

        // ═══════════════════════════════════════════════════════════════
        // PRIVATE FIELDS
        // ═══════════════════════════════════════════════════════════════

        private List<Setup> _activeSetups = new List<Setup>();
        private double _swingHigh = 0;
        private double _swingLow = 0;
        private int _swingHighIdx = -1;
        private int _swingLowIdx = -1;
        private int _setupCounter = 0;
        private int _dailyTrades = 0;
        private DateTime _lastTradeDate = DateTime.MinValue;
        private string _prefix = "F71_";
        private HttpClient _httpClient;

        // ═══════════════════════════════════════════════════════════════
        // LIFECYCLE
        // ═══════════════════════════════════════════════════════════════

        protected override void OnStart()
        {
            if (FibEntryMin >= FibEntryMax)
            {
                Print("ERROR: FibEntryMin must be < FibEntryMax");
                Stop();
                return;
            }

            _httpClient = EnableTelegram ? new HttpClient() : null;

            Print("=== Fibo 71 CP 2.0 Bot Started ===");
            Print($"Symbol: {SymbolName} | TF: {TimeFrame}");
            Print($"Fib Entry: {FibEntryMin} - {FibEntryMax}");
            Print($"BOS Lookback: {BOSLookback} | Swing: {SwingLookback}");
            Print($"Imbalance: {(EnableImbalance ? "ON" : "OFF")} | LiqSweep: {(EnableLiquiditySweep ? "ON" : "OFF")}");
            Print($"Trading: {(EnableTrading ? "ON" : "OFF")} | Risk: {RiskPercent}%");
        }

        protected override void OnBar()
        {
            int count = Bars.Count;
            if (count < SwingLookback + 10) return;

            int idx = count - 1; // Current closed bar

            // Reset daily trade counter
            if (Bars.LastBar.OpenTime.Date != _lastTradeDate.Date)
            {
                _dailyTrades = 0;
                _lastTradeDate = Bars.LastBar.OpenTime.Date;
            }

            // ---- STEP 1: Swing Point Detection ----
            DetectSwingPoints(idx);

            // ---- STEP 2: BOS Detection ----
            bool bullishBOS, bearishBOS;
            DetectBOS(idx, out bullishBOS, out bearishBOS);

            // ---- STEP 3: Imbalance Detection ----
            bool bearishImbalance, bullishImbalance;
            DetectImbalance(idx, out bearishImbalance, out bullishImbalance);

            // ---- STEP 4: Liquidity Sweep Detection (only when BOS detected) ----
            bool bearishLiqSweep, bullishLiqSweep;
            DetectLiquiditySweep(idx, bearishBOS, bullishBOS, out bearishLiqSweep, out bullishLiqSweep);

            // ---- STEP 5: Check criteria ----
            bool newBearish = bearishBOS &&
                              (!EnableImbalance || bearishImbalance) &&
                              (!EnableLiquiditySweep || bearishLiqSweep);

            bool newBullish = bullishBOS &&
                              (!EnableImbalance || bullishImbalance) &&
                              (!EnableLiquiditySweep || bullishLiqSweep);

            // ---- STEP 6: Check existing setups ----
            CheckExistingSetups(idx);

            // ---- STEP 7: Create new setups ----
            if (newBearish)
                CreateSetup(false, idx); // false = bearish

            if (newBullish)
                CreateSetup(true, idx);  // true = bullish

            // ---- STEP 8: Draw swing points ----
            if (ShowSwingPoints)
                DrawSwingPoints(idx);

            // ---- STEP 9: Check entry zone ----
            CheckEntryZone(idx);

            // ---- STEP 10: Update info table ----
            UpdateInfoTable(idx);
        }

        protected override void OnStop()
        {
            // Clean up all chart objects
            foreach (var s in _activeSetups)
                DeleteSetupDrawings(s);

            // Remove info table
            RemoveTableObjects();

            Print("=== Fibo 71 CP 2.0 Bot Stopped ===");
        }

        // ═══════════════════════════════════════════════════════════════
        // SWING POINT DETECTION
        // ═══════════════════════════════════════════════════════════════

        private void DetectSwingPoints(int idx)
        {
            bool isSwingHigh = true;
            bool isSwingLow = true;

            for (int i = 1; i <= SwingLookback; i++)
            {
                if (idx - i < 0) continue;
                if (Bars.HighPrices[idx - i] >= Bars.HighPrices[idx])
                    isSwingHigh = false;
                if (Bars.LowPrices[idx - i] <= Bars.LowPrices[idx])
                    isSwingLow = false;
            }

            if (isSwingHigh)
            {
                _swingHigh = Bars.HighPrices[idx];
                _swingHighIdx = idx;
            }

            if (isSwingLow)
            {
                _swingLow = Bars.LowPrices[idx];
                _swingLowIdx = idx;
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // BOS DETECTION
        // ═══════════════════════════════════════════════════════════════

        private void DetectBOS(int idx, out bool bullishBOS, out bool bearishBOS)
        {
            bullishBOS = false;
            bearishBOS = false;

            double close = Bars.ClosePrices[idx];

            // Bearish: close < swingLow, swing 3-50 bars old
            if (_swingLow > 0 && close < _swingLow)
            {
                int age = idx - _swingLowIdx;
                if (age >= 3 && age <= BOSLookback)
                    bearishBOS = true;
            }

            // Bullish: close > swingHigh, swing 3-50 bars old
            if (_swingHigh > 0 && close > _swingHigh)
            {
                int age = idx - _swingHighIdx;
                if (age >= 3 && age <= BOSLookback)
                    bullishBOS = true;
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // IMBALANCE DETECTION
        // ═══════════════════════════════════════════════════════════════

        private void DetectImbalance(int idx, out bool bearishImbalance, out bool bullishImbalance)
        {
            bearishImbalance = false;
            bullishImbalance = false;

            if (idx < 2) return;

            double pipMult = Symbol.PipSize;
            double minGap = MinImbalancePips * pipMult;

            // Bearish: low[2] > high (gap between bar 2 and current)
            if (Bars.LowPrices[idx - 2] > Bars.HighPrices[idx] &&
                (Bars.LowPrices[idx - 2] - Bars.HighPrices[idx]) >= minGap)
                bearishImbalance = true;

            // Bullish: high[2] < low (gap between bar 2 and current)
            if (Bars.HighPrices[idx - 2] < Bars.LowPrices[idx] &&
                (Bars.LowPrices[idx] - Bars.HighPrices[idx - 2]) >= minGap)
                bullishImbalance = true;
        }

        // ═══════════════════════════════════════════════════════════════
        // LIQUIDITY SWEEP DETECTION
        // ═══════════════════════════════════════════════════════════════

        // Pine Script: liquidity sweep is ONLY checked when BOS is detected
        // if bearishBOS -> check high[i] > swingHigh && close[i] < swingHigh
        // if bullishBOS -> check low[i] < swingLow && close[i] > swingLow
        private void DetectLiquiditySweep(int idx, bool bearishBOS, bool bullishBOS,
                                          out bool bearishLiqSweep, out bool bullishLiqSweep)
        {
            bearishLiqSweep = false;
            bullishLiqSweep = false;

            int lookback = 5;

            // Only check bearish sweep when bearish BOS is detected
            if (bearishBOS && _swingHigh > 0)
            {
                for (int i = 1; i <= lookback; i++)
                {
                    if (idx - i < 0) break;
                    if (Bars.HighPrices[idx - i] > _swingHigh &&
                        Bars.ClosePrices[idx - i] < _swingHigh)
                    {
                        bearishLiqSweep = true;
                        break;
                    }
                }
            }

            // Only check bullish sweep when bullish BOS is detected
            if (bullishBOS && _swingLow > 0)
            {
                for (int i = 1; i <= lookback; i++)
                {
                    if (idx - i < 0) break;
                    if (Bars.LowPrices[idx - i] < _swingLow &&
                        Bars.ClosePrices[idx - i] > _swingLow)
                    {
                        bullishLiqSweep = true;
                        break;
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // CHECK EXISTING SETUPS FOR TP/SL/EXPIRY
        // ═══════════════════════════════════════════════════════════════

        private void CheckExistingSetups(int idx)
        {
            double high = Bars.HighPrices[idx];
            double low = Bars.LowPrices[idx];

            foreach (var s in _activeSetups)
            {
                if (s.HitBarIndex >= 0) continue; // Skip inactive

                // Check expiry
                bool isExpired = SetupExpiryEnabled &&
                                 (idx - s.CreatedBarIndex >= SetupExpiryBars);

                if (isExpired)
                {
                    DeleteSetupDrawings(s);
                    s.HitBarIndex = idx;
                    s.HitResult = 3; // expired

                    if (ShowLabels)
                    {
                        s.HitLabelId = MakeId(s.SetupId, "Expired");
                        Chart.DrawText(s.HitLabelId, "EXPIRED",
                            Bars.OpenTimes[s.CreatedBarIndex], s.Fib100,
                            Color.Gray);
                    }
                }
                else
                {
                    // TP check
                    bool hitTP = s.IsBullish ? (low <= s.Fib0) : (high >= s.Fib0);
                    // SL check
                    bool hitSL = s.IsBullish ? (high >= s.Fib100) : (low <= s.Fib100);

                    if (hitTP)
                    {
                        s.HitBarIndex = idx;
                        s.HitResult = 1; // TP

                        if (ShowLabels)
                        {
                            Chart.RemoveObject(s.BosLabelId);
                            s.HitLabelId = MakeId(s.SetupId, "TPHit");
                            Chart.DrawText(s.HitLabelId, "\u2705 TP HIT",
                                Bars.OpenTimes[idx], s.Fib0,
                                Color.Lime);
                        }

                        Print($"TP HIT | {(s.IsBullish ? "BULLISH" : "BEARISH")} | Setup {s.SetupId}");
                    }
                    else if (hitSL)
                    {
                        s.HitBarIndex = idx;
                        s.HitResult = 2; // SL

                        if (ShowLabels)
                        {
                            Chart.RemoveObject(s.BosLabelId);
                            s.HitLabelId = MakeId(s.SetupId, "SLHit");
                            Chart.DrawText(s.HitLabelId, "\u26D4 SL HIT",
                                Bars.OpenTimes[idx], s.Fib100,
                                Color.Red);
                        }

                        Print($"SL HIT | {(s.IsBullish ? "BULLISH" : "BEARISH")} | Setup {s.SetupId}");
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // CREATE NEW SETUP
        // ═══════════════════════════════════════════════════════════════

        private void CreateSetup(bool isBullish, int idx)
        {
            double range = _swingHigh - _swingLow;
            double fib0, fib100, fib236, fib382, fib50, fib618, fib71, fib79;

            if (!isBullish)
            {
                // Bearish: TP=swingLow, SL=swingHigh
                fib0 = _swingLow;
                fib100 = _swingHigh;
                fib236 = _swingLow + range * 0.236;
                fib382 = _swingLow + range * 0.382;
                fib50 = _swingLow + range * 0.5;
                fib618 = _swingLow + range * 0.618;
                fib71 = _swingLow + range * FibEntryMin;
                fib79 = _swingLow + range * FibEntryMax;
            }
            else
            {
                // Bullish: TP=swingHigh, SL=swingLow
                fib0 = _swingHigh;
                fib100 = _swingLow;
                fib236 = _swingHigh - range * 0.236;
                fib382 = _swingHigh - range * 0.382;
                fib50 = _swingHigh - range * 0.5;
                fib618 = _swingHigh - range * 0.618;
                fib71 = _swingHigh - range * FibEntryMin;
                fib79 = _swingHigh - range * FibEntryMax;
            }

            var s = new Setup
            {
                IsBullish = isBullish,
                Fib0 = fib0,
                Fib236 = fib236,
                Fib382 = fib382,
                Fib50 = fib50,
                Fib618 = fib618,
                Fib100 = fib100,
                Fib71 = fib71,
                Fib79 = fib79,
                CreatedBarIndex = idx,
                HitBarIndex = -1,
                HitResult = 0,
                SetupId = _setupCounter.ToString()
            };
            _setupCounter++;

            // Draw setup
            CreateSetupDrawings(s);

            // Add to list
            _activeSetups.Add(s);

            // Limit active setups
            while (_activeSetups.Count > MaxActiveSetups)
            {
                var old = _activeSetups[0];
                DeleteSetupDrawings(old);
                _activeSetups.RemoveAt(0);
            }

            // Alert
            string dir = isBullish ? "BULLISH" : "BEARISH";
            string entryZone = isBullish
                ? $"{fib79:F5} - {fib71:F5}"
                : $"{fib71:F5} - {fib79:F5}";

            Print($"=== {dir} BOS DETECTED ===");
            Print($"  TP (0%): {fib0:F5}");
            Print($"  50%: {fib50:F5}");
            Print($"  Entry Zone: {entryZone}");
            Print($"  SL (100%): {fib100:F5}");

            // Telegram notification
            SendTelegram($"Fibo71: {dir} BOS on {SymbolName}\n"
                       + $"Entry Zone: {entryZone}\n"
                       + $"TP: {fib0:F5} | SL: {fib100:F5}");
        }

        // ═══════════════════════════════════════════════════════════════
        // DRAWING: CREATE SETUP VISUALS
        // ═══════════════════════════════════════════════════════════════

        private void CreateSetupDrawings(Setup s)
        {
            DateTime createTime = Bars.OpenTimes[s.CreatedBarIndex];
            // Extend lines far into the future
            DateTime futureTime = createTime.AddTicks(TimeFrame.ToTimeSpan().Ticks * SetupExpiryBars);

            string sid = s.SetupId;

            if (ShowFibLines)
            {
                // Fib0 (TP) - lime, thick
                s.LineFib0Id = MakeId(sid, "Fib0");
                Chart.DrawTrendLine(s.LineFib0Id,
                    createTime, s.Fib0, futureTime, s.Fib0,
                    Color.Lime, 2, LineStyle.Solid);

                // Fib100 (SL) - red, thick
                s.LineFib100Id = MakeId(sid, "Fib100");
                Chart.DrawTrendLine(s.LineFib100Id,
                    createTime, s.Fib100, futureTime, s.Fib100,
                    Color.Red, 2, LineStyle.Solid);

                // Fib50 - blue, thin
                s.LineFib50Id = MakeId(sid, "Fib50");
                Chart.DrawTrendLine(s.LineFib50Id,
                    createTime, s.Fib50, futureTime, s.Fib50,
                    Color.DodgerBlue, 1, LineStyle.Solid);

                if (ShowEntryZone)
                {
                    // Fib71 - dotted blue
                    s.LineFib71Id = MakeId(sid, "Fib71");
                    Chart.DrawTrendLine(s.LineFib71Id,
                        createTime, s.Fib71, futureTime, s.Fib71,
                        Color.FromArgb(127, 30, 144, 255), 1, LineStyle.Lines);

                    // Fib79 - dotted blue
                    s.LineFib79Id = MakeId(sid, "Fib79");
                    Chart.DrawTrendLine(s.LineFib79Id,
                        createTime, s.Fib79, futureTime, s.Fib79,
                        Color.FromArgb(127, 30, 144, 255), 1, LineStyle.Lines);

                    // Entry zone box
                    var zoneColor = s.IsBullish
                        ? Color.FromArgb(25, 0, 128, 0)    // green 10% opacity
                        : Color.FromArgb(25, 255, 0, 0);   // red 10% opacity

                    s.ZoneId = MakeId(sid, "Zone");
                    Chart.DrawRectangle(s.ZoneId,
                        createTime, s.Fib71, futureTime, s.Fib79,
                        zoneColor, 0, zoneColor);
                }
            }

            if (ShowLabels)
            {
                s.BosLabelId = MakeId(sid, "BOS");
                string labelText = s.IsBullish
                    ? $"BULLISH BOS\nTP: {s.Fib0:F5}\nEntry: {s.Fib79:F5} - {s.Fib71:F5}\nSL: {s.Fib100:F5}"
                    : $"BEARISH BOS\nTP: {s.Fib0:F5}\nEntry: {s.Fib71:F5} - {s.Fib79:F5}\nSL: {s.Fib100:F5}";

                var lblColor = s.IsBullish
                    ? Color.FromArgb(178, 0, 255, 0)   // green 70%
                    : Color.FromArgb(178, 255, 0, 0);   // red 70%

                Chart.DrawText(s.BosLabelId, labelText,
                    createTime, s.Fib100, lblColor);
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // DRAWING: DELETE SETUP VISUALS
        // ═══════════════════════════════════════════════════════════════

        private void DeleteSetupDrawings(Setup s)
        {
            string sid = s.SetupId;

            TryRemove(s.LineFib0Id);
            TryRemove(s.LineFib100Id);
            TryRemove(s.LineFib50Id);
            TryRemove(s.LineFib71Id);
            TryRemove(s.LineFib79Id);
            TryRemove(s.ZoneId);
            TryRemove(s.BosLabelId);
            TryRemove(s.HitLabelId);
        }

        private void TryRemove(string id)
        {
            if (!string.IsNullOrEmpty(id))
                Chart.RemoveObject(id);
        }

        // ═══════════════════════════════════════════════════════════════
        // DRAWING: SWING POINTS
        // ═══════════════════════════════════════════════════════════════

        private void DrawSwingPoints(int idx)
        {
            bool isSwingHigh = true;
            bool isSwingLow = true;

            for (int i = 1; i <= SwingLookback; i++)
            {
                if (idx - i < 0) continue;
                if (Bars.HighPrices[idx - i] >= Bars.HighPrices[idx])
                    isSwingHigh = false;
                if (Bars.LowPrices[idx - i] <= Bars.LowPrices[idx])
                    isSwingLow = false;
            }

            if (isSwingHigh && idx > SwingLookback)
            {
                string name = _prefix + "HH_" + idx;
                Chart.DrawIcon(name, ChartIconType.DownArrow,
                    Bars.OpenTimes[idx], Bars.HighPrices[idx],
                    Color.FromArgb(127, 255, 0, 0));
            }

            if (isSwingLow && idx > SwingLookback)
            {
                string name = _prefix + "LL_" + idx;
                Chart.DrawIcon(name, ChartIconType.UpArrow,
                    Bars.OpenTimes[idx], Bars.LowPrices[idx],
                    Color.FromArgb(127, 0, 128, 0));
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // CHECK ENTRY ZONE
        // ═══════════════════════════════════════════════════════════════

        private void CheckEntryZone(int idx)
        {
            double close = Bars.ClosePrices[idx];

            foreach (var s in _activeSetups)
            {
                if (s.HitBarIndex >= 0) continue;

                bool inZone = s.IsBullish
                    ? (close <= s.Fib71 && close >= s.Fib79)
                    : (close >= s.Fib79 && close <= s.Fib71);

                if (inZone)
                {
                    Print($"Price in Entry Zone | {SymbolName} | Price: {close:F5}");

                    // Trading: place order when price enters zone
                    if (EnableTrading && _dailyTrades < MaxDailyTrades)
                    {
                        TryPlaceTrade(s);
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // TRADING
        // ═══════════════════════════════════════════════════════════════

        private void TryPlaceTrade(Setup s)
        {
            // Check if we already have a position for this setup
            var existing = Positions.FirstOrDefault(p =>
                p.Label == "F71_" + s.SetupId && p.SymbolName == SymbolName);
            if (existing != null) return;

            // Calculate lot size
            double slDistance = Math.Abs(s.Fib100 - s.Fib71);
            if (slDistance <= 0) return;

            double riskAmount = Account.Balance * RiskPercent / 100.0;
            double lotSize = riskAmount / (slDistance / Symbol.PipSize * Symbol.PipValue);
            lotSize = Symbol.NormalizeVolumeInUnits(lotSize, RoundingMode.ToNearest);

            if (lotSize < Symbol.VolumeInUnitsMin) return;

            TradeType direction = s.IsBullish ? TradeType.Buy : TradeType.Sell;
            double entry = s.IsBullish ? s.Fib71 : s.Fib79;

            var result = ExecuteMarketOrder(direction, SymbolName, lotSize,
                "F71_" + s.SetupId, s.Fib100, s.Fib0);

            if (result.IsSuccessful)
            {
                _dailyTrades++;
                Print($"Trade opened | {(s.IsBullish ? "BUY" : "SELL")} | "
                    + $"Lot: {lotSize} | Entry: {entry:F5} | "
                    + $"SL: {s.Fib100:F5} | TP: {s.Fib0:F5}");

                SendTelegram($"Fibo71: Trade opened on {SymbolName}\n"
                           + $"{(s.IsBullish ? "BUY" : "SELL")} {lotSize}\n"
                           + $"SL: {s.Fib100:F5} | TP: {s.Fib0:F5}");
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // INFO TABLE (top-right corner display)
        // ═══════════════════════════════════════════════════════════════

        private void UpdateInfoTable(int idx)
        {
            int activeBullish = 0;
            int activeBearish = 0;
            Setup lastActive = null;

            foreach (var s in _activeSetups)
            {
                if (s.HitBarIndex < 0)
                {
                    if (s.IsBullish) activeBullish++;
                    else activeBearish++;
                    lastActive = s;
                }
            }

            // Draw status text near top of chart
            string tblId = _prefix + "TBL";

            if (lastActive == null)
            {
                Chart.DrawText(tblId, "CP 2.0: NEUTRAL",
                    Bars.OpenTimes[idx], Bars.HighPrices[idx],
                    Color.White);
                return;
            }

            int barsLeft = SetupExpiryEnabled
                ? Math.Max(0, SetupExpiryBars - (idx - lastActive.CreatedBarIndex))
                : -1;

            string entryZone = lastActive.IsBullish
                ? $"{lastActive.Fib79:F5} - {lastActive.Fib71:F5}"
                : $"{lastActive.Fib71:F5} - {lastActive.Fib79:F5}";

            string statusEmoji = lastActive.IsBullish ? "BULLISH" : "BEARISH";
            string expiry = SetupExpiryEnabled ? $"\nExpires: {barsLeft} bars" : "";

            string tableText =
                $"=== CP 2.0: {statusEmoji} x{(activeBullish > 0 ? activeBullish : activeBearish)} ===\n"
                + $"TP (0%): {lastActive.Fib0:F5}\n"
                + $"50%: {lastActive.Fib50:F5}\n"
                + $"Entry Zone: {entryZone}\n"
                + $"SL (100%): {lastActive.Fib100:F5}\n"
                + $"Active Setups: {activeBullish + activeBearish}/{MaxActiveSetups}"
                + expiry;

            // Draw at a fixed position above the last bar
            double topPrice = lastActive.IsBullish ? lastActive.Fib0 : lastActive.Fib100;
            topPrice += (lastActive.Fib100 - lastActive.Fib0) * 0.15;

            Chart.DrawText(tblId, tableText,
                Bars.OpenTimes[idx], topPrice,
                Color.White);
        }

        private void RemoveTableObjects()
        {
            TryRemove(_prefix + "TBL");
        }

        // ═══════════════════════════════════════════════════════════════
        // TELEGRAM
        // ═══════════════════════════════════════════════════════════════

        private void SendTelegram(string message)
        {
            if (!EnableTelegram || string.IsNullOrEmpty(BotToken) || string.IsNullOrEmpty(ChatId))
                return;

            Task.Run(async () =>
            {
                try
                {
                    var url = $"https://api.telegram.org/bot{BotToken}/sendMessage";
                    var content = new FormUrlEncodedContent(new[]
                    {
                        new KeyValuePair<string, string>("chat_id", ChatId),
                        new KeyValuePair<string, string>("text", message),
                        new KeyValuePair<string, string>("parse_mode", "HTML")
                    });
                    await _httpClient.PostAsync(url, content);
                }
                catch (Exception ex)
                {
                    Print($"Telegram error: {ex.Message}");
                }
            });
        }

        // ═══════════════════════════════════════════════════════════════
        // HELPERS
        // ═══════════════════════════════════════════════════════════════

        private string MakeId(string setupId, string type)
        {
            return $"{_prefix}{setupId}_{type}";
        }
    }
}
