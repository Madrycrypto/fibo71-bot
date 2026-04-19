// =====================================================================
// Fibo71 CP 2.0 Bot - cTrader cBot
// Exact replica of TradingView Pine Script indicator + trading
// With full feature set: HTF, Session, ATR, Trailing, Weekend, etc.
// =====================================================================
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
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
        // PARAMETERS
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

        // Entry Positions
        [Parameter("Position Mode", Group = "Entry Positions", DefaultValue = 1)]
        public int PositionMode { get; set; }  // 1=Single, 2=Normal(EP1+EP2), 3=Aggressive(EP1+EP2+EP3)

        // Trading
        [Parameter("Risk %", Group = "Trading", DefaultValue = 1.0, MinValue = 0.1, MaxValue = 5.0, Step = 0.1)]
        public double RiskPercent { get; set; }

        [Parameter("Enable Trading", Group = "Trading", DefaultValue = false)]
        public bool EnableTrading { get; set; }

        [Parameter("Max Daily Trades", Group = "Trading", DefaultValue = 3, MinValue = 1, MaxValue = 10)]
        public int MaxDailyTrades { get; set; }

        [Parameter("Max Open Positions", Group = "Trading", DefaultValue = 6, MinValue = 1, MaxValue = 20)]
        public int MaxOpenPositions { get; set; }

        // HTF Filter
        [Parameter("Enable HTF Filter", Group = "HTF Filter", DefaultValue = false)]
        public bool EnableHTF { get; set; }

        [Parameter("HTF Timeframe", Group = "HTF Filter", DefaultValue = "Hourly")]
        public TimeFrame HTFTimeframe { get; set; }

        [Parameter("HTF EMA Period", Group = "HTF Filter", DefaultValue = 200, MinValue = 10, MaxValue = 500)]
        public int HTFEMA { get; set; }

        // Session Filter
        [Parameter("Enable Session Filter", Group = "Session Filter", DefaultValue = false)]
        public bool EnableSessionFilter { get; set; }

        [Parameter("Session Start HH:MM", Group = "Session Filter", DefaultValue = "08:00")]
        public string SessionStart { get; set; }

        [Parameter("Session End HH:MM", Group = "Session Filter", DefaultValue = "20:00")]
        public string SessionEnd { get; set; }

        // ATR / Consolidation Filter
        [Parameter("Enable ATR Filter", Group = "ATR Filter", DefaultValue = false)]
        public bool EnableATRFilter { get; set; }

        [Parameter("ATR Period", Group = "ATR Filter", DefaultValue = 14, MinValue = 5, MaxValue = 50)]
        public int ATRLength { get; set; }

        [Parameter("ATR Smoothing", Group = "ATR Filter", DefaultValue = 50, MinValue = 10, MaxValue = 200)]
        public int ATRSmooth { get; set; }

        [Parameter("ATR Threshold", Group = "ATR Filter", DefaultValue = 1.0, MinValue = 0.5, MaxValue = 3.0, Step = 0.1)]
        public double ATRThreshold { get; set; }

        // Trailing Stop
        [Parameter("Enable Trailing Stop", Group = "Trailing Stop", DefaultValue = false)]
        public bool EnableTrailingStop { get; set; }

        [Parameter("Trail Start (pips)", Group = "Trailing Stop", DefaultValue = 20.0, MinValue = 1)]
        public double TrailingStartPips { get; set; }

        [Parameter("Trail Distance (pips)", Group = "Trailing Stop", DefaultValue = 15.0, MinValue = 1)]
        public double TrailingStopPips { get; set; }

        // Daily Auto-Close
        [Parameter("Enable Daily Close", Group = "Daily Close", DefaultValue = false)]
        public bool EnableDailyClose { get; set; }

        [Parameter("Daily Close Time HH:MM", Group = "Daily Close", DefaultValue = "23:55")]
        public string DailyCloseTime { get; set; }

        // Weekend Close
        [Parameter("Enable Weekend Close", Group = "Weekend Close", DefaultValue = false)]
        public bool EnableWeekendClose { get; set; }

        [Parameter("Friday Close Time HH:MM", Group = "Weekend Close", DefaultValue = "21:00")]
        public string WeekendCloseTime { get; set; }

        // Partial Close
        [Parameter("Enable Partial Close", Group = "Partial Close", DefaultValue = false)]
        public bool EnablePartialClose { get; set; }

        [Parameter("Partial Close %", Group = "Partial Close", DefaultValue = 70.0, MinValue = 10, MaxValue = 90)]
        public double PartialClosePercent { get; set; }

        [Parameter("Move SL to BE After Partial", Group = "Partial Close", DefaultValue = true)]
        public bool PartialMoveSL { get; set; }

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
            public double Fib0, Fib236, Fib382, Fib50, Fib618, Fib786, Fib100;
            public double Fib71, Fib79;
            public int CreatedBarIndex;
            public int HitBarIndex = -1;
            public int HitResult;  // 0=active, 1=TP, 2=SL, 3=expired
            public string SetupId;
            public bool Traded;
            public string[] TradeLabels = new string[3];

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
        private AverageTrueRange _atrIndicator;
        private HashSet<string> _partiallyClosed = new HashSet<string>();

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
            _atrIndicator = Indicators.AverageTrueRange(ATRLength);

            Print("=== Fibo 71 CP 2.0 Bot Started ===");
            Print($"Symbol: {SymbolName} | TF: {TimeFrame}");
            Print($"Fib Entry: {FibEntryMin} - {FibEntryMax}");
            Print($"BOS Lookback: {BOSLookback} | Swing: {SwingLookback}");
            Print($"Imbalance: {(EnableImbalance ? "ON" : "OFF")} | LiqSweep: {(EnableLiquiditySweep ? "ON" : "OFF")}");
            Print($"Trading: {(EnableTrading ? "ON" : "OFF")} | Risk: {RiskPercent}%");
            Print($"HTF: {(EnableHTF ? "ON" : "OFF")} | Session: {(EnableSessionFilter ? "ON" : "OFF")}");
            Print($"ATR: {(EnableATRFilter ? "ON" : "OFF")} | Trailing: {(EnableTrailingStop ? "ON" : "OFF")}");
            Print($"Daily Close: {(EnableDailyClose ? "ON" : "OFF")} | Weekend: {(EnableWeekendClose ? "ON" : "OFF")}");
            Print($"Partial Close: {(EnablePartialClose ? "ON" : "OFF")} | Position Mode: {PositionMode}");
        }

        protected override void OnBar()
        {
            int count = Bars.Count;
            if (count < SwingLookback + 10) return;

            int idx = count - 1;

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

            // ---- STEP 4: Liquidity Sweep Detection ----
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
                CreateSetup(false, idx);

            if (newBullish)
                CreateSetup(true, idx);

            // ---- STEP 8: Draw swing points ----
            if (ShowSwingPoints)
                DrawSwingPoints(idx);

            // ---- STEP 9: Check entry zone & trade ----
            CheckEntryZone(idx);

            // ---- STEP 10: Manage positions ----
            ManageDailyClose();
            ManageWeekendClose();
            ManageTrailingStop();
            ManagePartialClose();

            // ---- STEP 11: Update info table ----
            UpdateInfoTable(idx);
        }

        protected override void OnStop()
        {
            foreach (var s in _activeSetups)
                DeleteSetupDrawings(s);

            RemoveTableObjects();
            _httpClient?.Dispose();
            Print("=== Fibo 71 CP 2.0 Bot Stopped ===");
        }

        // ═══════════════════════════════════════════════════════════════
        // FILTER HELPERS
        // ═══════════════════════════════════════════════════════════════

        private bool IsSessionActive()
        {
            if (!EnableSessionFilter) return true;

            var now = Server.Time;
            int nowMinutes = now.Hour * 60 + now.Minute;
            int startH, startM, endH, endM;
            ParseTime(SessionStart, out startH, out startM);
            ParseTime(SessionEnd, out endH, out endM);

            int startMinutes = startH * 60 + startM;
            int endMinutes = endH * 60 + endM;

            if (startMinutes <= endMinutes)
                return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
            else
                return nowMinutes >= startMinutes || nowMinutes <= endMinutes;
        }

        private bool IsWeekendBlocked()
        {
            if (!EnableWeekendClose) return false;

            var now = Server.Time;
            if (now.DayOfWeek == DayOfWeek.Saturday) return true;
            if (now.DayOfWeek == DayOfWeek.Sunday) return true;

            if (now.DayOfWeek == DayOfWeek.Friday)
            {
                int closeH, closeM;
                ParseTime(WeekendCloseTime, out closeH, out closeM);
                if (now.Hour > closeH || (now.Hour == closeH && now.Minute >= closeM))
                    return true;
            }
            return false;
        }

        private int GetHTFTrend()
        {
            if (!EnableHTF) return 0;

            try
            {
                var htfBars = MarketData.GetBars(HTFTimeframe, SymbolName);
                if (htfBars.Count < HTFEMA + 1) return 0;

                // Calculate EMA on HTF bars
                double k = 2.0 / (HTFEMA + 1);
                double ema = 0;
                int startIdx = Math.Max(0, htfBars.Count - HTFEMA - 10);
                ema = htfBars.ClosePrices[startIdx];

                for (int i = startIdx + 1; i < htfBars.Count; i++)
                    ema = htfBars.ClosePrices[i] * k + ema * (1 - k);

                double htfClose = htfBars.ClosePrices.LastValue;
                if (htfClose > ema) return 1;   // Bullish
                if (htfClose < ema) return -1;  // Bearish
            }
            catch { }

            return 0;
        }

        private bool IsATRActive()
        {
            if (!EnableATRFilter) return true;
            if (_atrIndicator == null) return true;

            int count = Math.Min(ATRSmooth + 1, Bars.Count);
            if (count < ATRSmooth) return true;

            double currentATR = _atrIndicator.Result.LastValue;

            // Calculate SMA baseline
            double baseline = 0;
            for (int i = 0; i < ATRSmooth && i < _atrIndicator.Result.Count; i++)
                baseline += _atrIndicator.Result[_atrIndicator.Result.Count - 1 - i];
            baseline /= Math.Min(ATRSmooth, _atrIndicator.Result.Count);

            return currentATR > baseline * ATRThreshold;
        }

        private void ParseTime(string timeStr, out int hours, out int minutes)
        {
            hours = 0;
            minutes = 0;
            var parts = timeStr.Split(':');
            if (parts.Length >= 2)
            {
                int.TryParse(parts[0], out hours);
                int.TryParse(parts[1], out minutes);
            }
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

            if (_swingLow > 0 && close < _swingLow)
            {
                int age = idx - _swingLowIdx;
                if (age >= 3 && age <= BOSLookback)
                    bearishBOS = true;
            }

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

            if (Bars.LowPrices[idx - 2] > Bars.HighPrices[idx] &&
                (Bars.LowPrices[idx - 2] - Bars.HighPrices[idx]) >= minGap)
                bearishImbalance = true;

            if (Bars.HighPrices[idx - 2] < Bars.LowPrices[idx] &&
                (Bars.LowPrices[idx] - Bars.HighPrices[idx - 2]) >= minGap)
                bullishImbalance = true;
        }

        // ═══════════════════════════════════════════════════════════════
        // LIQUIDITY SWEEP DETECTION
        // ═══════════════════════════════════════════════════════════════

        private void DetectLiquiditySweep(int idx, bool bearishBOS, bool bullishBOS,
                                          out bool bearishLiqSweep, out bool bullishLiqSweep)
        {
            bearishLiqSweep = false;
            bullishLiqSweep = false;

            int lookback = 5;

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
                if (s.HitBarIndex >= 0) continue;

                bool isExpired = SetupExpiryEnabled &&
                                 (idx - s.CreatedBarIndex >= SetupExpiryBars);

                if (isExpired)
                {
                    DeleteSetupDrawings(s);
                    s.HitBarIndex = idx;
                    s.HitResult = 3;

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
                    bool hitTP = s.IsBullish ? (low <= s.Fib0) : (high >= s.Fib0);
                    bool hitSL = s.IsBullish ? (high >= s.Fib100) : (low <= s.Fib100);

                    if (hitTP)
                    {
                        s.HitBarIndex = idx;
                        s.HitResult = 1;

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
                        s.HitResult = 2;

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
            double fib0, fib100, fib236, fib382, fib50, fib618, fib786, fib71, fib79;

            if (!isBullish)
            {
                fib0 = _swingLow; fib100 = _swingHigh;
                fib236 = _swingLow + range * 0.236;
                fib382 = _swingLow + range * 0.382;
                fib50 = _swingLow + range * 0.5;
                fib618 = _swingLow + range * 0.618;
                fib786 = _swingLow + range * 0.786;
                fib71 = _swingLow + range * FibEntryMin;
                fib79 = _swingLow + range * FibEntryMax;
            }
            else
            {
                fib0 = _swingHigh; fib100 = _swingLow;
                fib236 = _swingHigh - range * 0.236;
                fib382 = _swingHigh - range * 0.382;
                fib50 = _swingHigh - range * 0.5;
                fib618 = _swingHigh - range * 0.618;
                fib786 = _swingHigh - range * 0.786;
                fib71 = _swingHigh - range * FibEntryMin;
                fib79 = _swingHigh - range * FibEntryMax;
            }

            var s = new Setup
            {
                IsBullish = isBullish,
                Fib0 = fib0, Fib236 = fib236, Fib382 = fib382,
                Fib50 = fib50, Fib618 = fib618, Fib786 = fib786,
                Fib100 = fib100, Fib71 = fib71, Fib79 = fib79,
                CreatedBarIndex = idx,
                HitBarIndex = -1,
                HitResult = 0,
                SetupId = _setupCounter.ToString(),
                Traded = false
            };
            _setupCounter++;

            CreateSetupDrawings(s);
            _activeSetups.Add(s);

            while (_activeSetups.Count > MaxActiveSetups)
            {
                DeleteSetupDrawings(_activeSetups[0]);
                _activeSetups.RemoveAt(0);
            }

            string dir = isBullish ? "BULLISH" : "BEARISH";
            string entryZone = isBullish
                ? $"{fib79:F5} - {fib71:F5}"
                : $"{fib71:F5} - {fib79:F5}";

            Print($"=== {dir} BOS DETECTED ===");
            Print($"  TP (0%): {fib0:F5}");
            Print($"  50%: {fib50:F5}");
            Print($"  Entry Zone: {entryZone}");
            Print($"  SL (100%): {fib100:F5}");

            SendTelegram($"Fibo71: {dir} BOS on {SymbolName}\n"
                       + $"Entry: {entryZone}\n"
                       + $"TP: {fib0:F5} | SL: {fib100:F5}");
        }

        // ═══════════════════════════════════════════════════════════════
        // CHECK ENTRY ZONE
        // ═══════════════════════════════════════════════════════════════

        private void CheckEntryZone(int idx)
        {
            // Pre-filters
            if (!IsSessionActive()) return;
            if (IsWeekendBlocked()) return;
            if (!IsATRActive()) return;

            int htfTrend = GetHTFTrend();
            double close = Bars.ClosePrices[idx];

            foreach (var s in _activeSetups)
            {
                if (s.HitBarIndex >= 0) continue;
                if (s.Traded) continue;

                // HTF filter
                if (EnableHTF && htfTrend != 0)
                {
                    if (s.IsBullish && htfTrend == -1) continue;
                    if (!s.IsBullish && htfTrend == 1) continue;
                }

                if (PositionMode == 1)
                {
                    // Single: entry at 71-79% zone
                    bool inZone = s.IsBullish
                        ? (close <= s.Fib71 && close >= s.Fib79)
                        : (close >= s.Fib79 && close <= s.Fib71);

                    if (inZone && EnableTrading && _dailyTrades < MaxDailyTrades
                        && CountOpenPositions() < MaxOpenPositions)
                        TryPlaceTrade(s, s.Fib71, s.Fib100, s.Fib0, "S", 0);
                }
                else if (PositionMode == 2)
                {
                    // Normal: EP1 at 0.5, EP2 at 0.618
                    double zone_width = Math.Abs(s.Fib100 - s.Fib0) * 0.05;
                    TryPlaceEP(s, s.Fib50, s.Fib618, s.Fib382, "EP1", 0, close, zone_width);
                    TryPlaceEP(s, s.Fib618, s.Fib786, s.Fib50, "EP2", 1, close, zone_width);
                }
                else if (PositionMode == 3)
                {
                    // Aggressive: EP1 at 0.382, EP2 at 0.5, EP3 at 0.618
                    double zone_width = Math.Abs(s.Fib100 - s.Fib0) * 0.05;
                    TryPlaceEP(s, s.Fib382, s.Fib50, s.Fib236, "EP1", 0, close, zone_width);
                    TryPlaceEP(s, s.Fib50, s.Fib618, s.Fib382, "EP2", 1, close, zone_width);
                    TryPlaceEP(s, s.Fib618, s.Fib786, s.Fib50, "EP3", 2, close, zone_width);
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // TRADING
        // ═══════════════════════════════════════════════════════════════

        private void TryPlaceTrade(Setup s, double entryLevel, double slLevel, double tpLevel, string label, int ticketIdx)
        {
            var labelFull = "F71_" + s.SetupId + "_" + label;
            var existing = Positions.FirstOrDefault(p =>
                p.Label == labelFull && p.SymbolName == SymbolName);
            if (existing != null) return;

            double slDistance = Math.Abs(slLevel - entryLevel);
            if (slDistance <= 0) return;

            double riskAmount = Account.Balance * RiskPercent / 100.0;
            double lotSize = riskAmount / (slDistance / Symbol.PipSize * Symbol.PipValue);
            lotSize = Symbol.NormalizeVolumeInUnits(lotSize, RoundingMode.ToNearest);

            if (lotSize < Symbol.VolumeInUnitsMin) return;

            TradeType direction = s.IsBullish ? TradeType.Buy : TradeType.Sell;

            var result = ExecuteMarketOrder(direction, SymbolName, lotSize,
                labelFull, slLevel, tpLevel);

            if (result.IsSuccessful)
            {
                s.Traded = true;
                s.TradeLabels[ticketIdx] = labelFull;
                _dailyTrades++;

                Print($"Trade opened | {(s.IsBullish ? "BUY" : "SELL")} | "
                    + $"Lot: {lotSize} | Label: {labelFull} | "
                    + $"SL: {slLevel:F5} | TP: {tpLevel:F5}");

                SendTelegram($"Fibo71: Trade on {SymbolName}\n"
                           + $"{(s.IsBullish ? "BUY" : "SELL")} {lotSize}\n"
                           + $"SL: {slLevel:F5} | TP: {tpLevel:F5}");
            }
        }

        private void TryPlaceEP(Setup s, double entryPrice, double slPrice, double tpPrice,
                                string epLabel, int ticketIdx, double currentClose, double zoneWidth)
        {
            if (s.TradeLabels[ticketIdx] != null) return;

            // Check if price is near entry level
            bool nearLevel = Math.Abs(currentClose - entryPrice) <= zoneWidth;
            if (!nearLevel) return;
            if (!EnableTrading) return;
            if (_dailyTrades >= MaxDailyTrades) return;
            if (CountOpenPositions() >= MaxOpenPositions) return;

            TryPlaceTrade(s, entryPrice, slPrice, tpPrice, epLabel, ticketIdx);
        }

        private int CountOpenPositions()
        {
            return Positions.Count(p =>
                p.Label.StartsWith("F71_") && p.SymbolName == SymbolName);
        }

        // ═══════════════════════════════════════════════════════════════
        // DAILY AUTO-CLOSE
        // ═══════════════════════════════════════════════════════════════

        private void ManageDailyClose()
        {
            if (!EnableDailyClose) return;

            int closeH, closeM;
            ParseTime(DailyCloseTime, out closeH, out closeM);

            var now = Server.Time;
            if (now.Hour != closeH || now.Minute != closeM) return;

            CloseAllBotPositions("Daily Close");
        }

        // ═══════════════════════════════════════════════════════════════
        // WEEKEND CLOSE
        // ═══════════════════════════════════════════════════════════════

        private void ManageWeekendClose()
        {
            if (!EnableWeekendClose) return;

            var now = Server.Time;
            if (now.DayOfWeek != DayOfWeek.Friday) return;

            int closeH, closeM;
            ParseTime(WeekendCloseTime, out closeH, out closeM);

            if (now.Hour == closeH && now.Minute == closeM)
                CloseAllBotPositions("Weekend Close");
        }

        private void CloseAllBotPositions(string reason)
        {
            int count = 0;
            foreach (var pos in Positions.Where(p =>
                p.Label.StartsWith("F71_") && p.SymbolName == SymbolName).ToList())
            {
                ClosePosition(pos);
                count++;
            }

            // Cancel pending orders
            foreach (var order in PendingOrders.Where(o =>
                o.Label.StartsWith("F71_") && o.Symbol == SymbolName).ToList())
            {
                CancelPendingOrder(order);
            }

            if (count > 0)
            {
                Print($"{reason}: closed {count} positions");
                SendTelegram($"Fibo71: {reason} on {SymbolName}\nClosed {count} positions");
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // TRAILING STOP
        // ═══════════════════════════════════════════════════════════════

        private void ManageTrailingStop()
        {
            if (!EnableTrailingStop) return;

            double trailStart = TrailingStartPips * Symbol.PipSize;
            double trailDist = TrailingStopPips * Symbol.PipSize;

            foreach (var pos in Positions.Where(p =>
                p.Label.StartsWith("F71_") && p.SymbolName == SymbolName).ToList())
            {
                if (pos.TradeType == TradeType.Buy)
                {
                    double profit = Symbol.Bid - pos.EntryPrice;
                    if (profit >= trailStart)
                    {
                        double newSL = Symbol.NormalizePrice(Symbol.Bid - trailDist);
                        if (newSL > pos.StopLoss || pos.StopLoss == 0)
                            ModifyPosition(pos, newSL, pos.TakeProfit);
                    }
                }
                else
                {
                    double profit = pos.EntryPrice - Symbol.Ask;
                    if (profit >= trailStart)
                    {
                        double newSL = Symbol.NormalizePrice(Symbol.Ask + trailDist);
                        if (newSL < pos.StopLoss || pos.StopLoss == 0)
                            ModifyPosition(pos, newSL, pos.TakeProfit);
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // PARTIAL CLOSE
        // ═══════════════════════════════════════════════════════════════

        private void ManagePartialClose()
        {
            if (!EnablePartialClose) return;

            foreach (var pos in Positions.Where(p =>
                p.Label.StartsWith("F71_") && p.SymbolName == SymbolName).ToList())
            {
                if (_partiallyClosed.Contains(pos.Label)) continue;

                double tpDistance = Math.Abs(pos.TakeProfit - pos.EntryPrice);
                if (tpDistance <= 0) continue;

                // Check if price reached 70% of TP distance
                double tp1Level;
                bool reachedTP1;

                if (pos.TradeType == TradeType.Buy)
                {
                    tp1Level = pos.EntryPrice + tpDistance * 0.7;
                    reachedTP1 = Symbol.Bid >= tp1Level;
                }
                else
                {
                    tp1Level = pos.EntryPrice - tpDistance * 0.7;
                    reachedTP1 = Symbol.Ask <= tp1Level;
                }

                if (!reachedTP1) continue;

                // Calculate partial volume
                double closeVol = Math.Floor(pos.VolumeInUnits * PartialClosePercent / 100.0
                    / Symbol.VolumeInUnitsStep) * Symbol.VolumeInUnitsStep;

                if (closeVol < Symbol.VolumeInUnitsMin) continue;
                if (pos.VolumeInUnits - closeVol < Symbol.VolumeInUnitsMin) continue;

                // Partial close
                var closeVolume = Symbol.NormalizeVolumeInUnits(closeVol, RoundingMode.ToNearest);
                var result = ClosePositionPartial(pos, closeVolume);

                if (result.IsSuccessful)
                {
                    _partiallyClosed.Add(pos.Label);
                    Print($"Partial Close: {closeVol} units at TP1 | {pos.Label}");

                    // Move SL to breakeven
                    if (PartialMoveSL)
                    {
                        ModifyPosition(pos, Symbol.NormalizePrice(pos.EntryPrice), pos.TakeProfit);
                    }

                    SendTelegram($"Fibo71: Partial Close on {SymbolName}\n"
                               + $"Closed {PartialClosePercent}% at TP1"
                               + (PartialMoveSL ? "\nSL moved to breakeven" : ""));
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // DRAWING
        // ═══════════════════════════════════════════════════════════════

        private void CreateSetupDrawings(Setup s)
        {
            DateTime createTime = Bars.OpenTimes[s.CreatedBarIndex];
            DateTime futureTime = createTime.AddTicks(TimeFrame.ToTimeSpan().Ticks * SetupExpiryBars);
            string sid = s.SetupId;

            if (ShowFibLines)
            {
                s.LineFib0Id = MakeId(sid, "Fib0");
                Chart.DrawTrendLine(s.LineFib0Id,
                    createTime, s.Fib0, futureTime, s.Fib0,
                    Color.Lime, 2, LineStyle.Solid);

                s.LineFib100Id = MakeId(sid, "Fib100");
                Chart.DrawTrendLine(s.LineFib100Id,
                    createTime, s.Fib100, futureTime, s.Fib100,
                    Color.Red, 2, LineStyle.Solid);

                s.LineFib50Id = MakeId(sid, "Fib50");
                Chart.DrawTrendLine(s.LineFib50Id,
                    createTime, s.Fib50, futureTime, s.Fib50,
                    Color.DodgerBlue, 1, LineStyle.Solid);

                if (ShowEntryZone)
                {
                    s.LineFib71Id = MakeId(sid, "Fib71");
                    Chart.DrawTrendLine(s.LineFib71Id,
                        createTime, s.Fib71, futureTime, s.Fib71,
                        Color.FromArgb(127, 30, 144, 255), 1, LineStyle.Lines);

                    s.LineFib79Id = MakeId(sid, "Fib79");
                    Chart.DrawTrendLine(s.LineFib79Id,
                        createTime, s.Fib79, futureTime, s.Fib79,
                        Color.FromArgb(127, 30, 144, 255), 1, LineStyle.Lines);

                    var zoneColor = s.IsBullish
                        ? Color.FromArgb(25, 0, 128, 0)
                        : Color.FromArgb(25, 255, 0, 0);

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
                    ? Color.FromArgb(178, 0, 255, 0)
                    : Color.FromArgb(178, 255, 0, 0);

                Chart.DrawText(s.BosLabelId, labelText,
                    createTime, s.Fib100, lblColor);
            }
        }

        private void DeleteSetupDrawings(Setup s)
        {
            TryRemove(s.LineFib0Id);
            TryRemove(s.LineFib100Id);
            TryRemove(s.LineFib50Id);
            TryRemove(s.LineFib71Id);
            TryRemove(s.LineFib79Id);
            TryRemove(s.ZoneId);
            TryRemove(s.BosLabelId);
            TryRemove(s.HitLabelId);
        }

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
        // INFO TABLE
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

        private void TryRemove(string id)
        {
            if (!string.IsNullOrEmpty(id))
                Chart.RemoveObject(id);
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
