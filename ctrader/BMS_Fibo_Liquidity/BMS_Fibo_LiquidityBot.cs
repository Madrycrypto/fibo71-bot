/*
 * BMS Fibonacci Liquidity Bot for cTrader
 *
 * CORRECTED ALGORITHM:
 * 1. Detect BMS (break of swing high/low)
 * 2. Track new extremum AFTER BMS (new high/low)
 * 3. Wait for retracement back through BMS level (confirms extremum)
 * 4. Calculate Fibonacci: swing_point → confirmed extremum
 * 5. Wait for price to enter Fib zone (0.62-0.71)
 * 6. Detect liquidity sweep (wick >= 2x body)
 * 7. Wait for confirmation candle
 * 8. Check all filters → Enter trade (single or grid)
 *
 * Market: BTCUSDT | Timeframe: 15m
 *
 * Features:
 * - Auto symbol detection from chart
 * - Grid order support with configurable parameters
 * - Telegram notifications for grid orders
 */

using System;
using System.Collections.Generic;
using System.Linq;
using cAlgo;
using BMSFiboLiquidity.Helpers;

namespace BMSFiboLiquidity
{
    /// <summary>
    /// Strategy states for the state machine
    /// </summary>
    public enum StrategyState
    {
        Idle,                   // Waiting for BMS
        BmsDetected,           // BMS found, tracking new extremum
        TrackingExtremum,      // Tracking new high/low after BMS
        ExtremumConfirmed,     // Price retraced through BMS level, Fib calculated
        InFibZone,             // Price in 0.62-0.71 zone
        SweepDetected,         // Liquidity sweep found
        InTrade                // Position open
    }

    /// <summary>
    /// Trade direction
    /// </summary>
    public enum TradeDirection
    {
        Bullish,
        Bearish
    }

    [Robot(TimeZone = TimeZones.Utc, AccessRights = AccessRights.FullAccess)]
    public class BMSFiboLiquidityBot : Robot
    {
        #region Parameters

        // BMS Settings
        [Parameter("Swing Lookback", DefaultValue = 5)]
        public int SwingLookback { get; set; } = 5;

        [Parameter("Momentum Candles Required", DefaultValue = 3)]
        public int MomentumCandlesRequired { get; set; } = 3;

        [Parameter("Body % Threshold", DefaultValue = 0.60)]
        public double BodyPercentThreshold { get; set; } = 0.60;

        [Parameter("Distance ATR Threshold", DefaultValue = 0.5)]
        public double DistanceAtrThreshold { get; set; } = 0.5;

        // Fibonacci Settings
        [Parameter("Entry Zone Min", DefaultValue = 0.62)]
        public double EntryZoneMin { get; set; } = 0.62;

        [Parameter("Entry Zone Max", DefaultValue = 0.71)]
        public double EntryZoneMax { get; set; } = 0.71;

        // Liquidity Sweep Settings
        [Parameter("Min Wick/Body Ratio", DefaultValue = 2.0)]
        public double MinWickToBodyRatio { get; set; } = 2.0;

        [Parameter("Ideal Wick/Body Ratio", DefaultValue = 3.0)]
        public double IdealWickToBodyRatio { get; set; } = 3.0;

        // Confirmation Candle
        [Parameter("Confirmation Body %", DefaultValue = 0.50)]
        public double ConfirmationBodyPercent { get; set; } = 0.50;

        // SL Buffer
        [Parameter("SL Buffer %", DefaultValue = 0.1)]
        public double SlBufferPercent { get; set; } = 0.1;

        // Extremum tracking
        [Parameter("Min Extremum Candles", DefaultValue = 1)]
        public int MinExtremumCandles { get; set; } = 1;

        [Parameter("Extremum Timeout Candles", DefaultValue = 50)]
        public int ExtremumTimeoutCandles { get; set; } = 50;

        // Filter toggles
        [Parameter("Enable Trend Filter", DefaultValue = true)]
        public bool EnableTrendFilter { get; set; } = true;

        [Parameter("Enable Volume Filter", DefaultValue = true)]
        public bool EnableVolumeFilter { get; set; } = true;

        [Parameter("Enable Volatility Filter", DefaultValue = true)]
        public bool EnableVolatilityFilter { get; set; } = true;

        [Parameter("Enable R:R Filter", DefaultValue = true)]
        public bool EnableRrFilter { get; set; } = true;

        // Filter parameters
        [Parameter("EMA Fast Period", DefaultValue = 50)]
        public int EmaFastPeriod { get; set; } = 50;

        [Parameter("EMA Slow Period", DefaultValue = 200)]
        public int EmaSlowPeriod { get; set; } = 200;

        [Parameter("Volume Lookback", DefaultValue = 20)]
        public int VolumeLookback { get; set; } = 20;

        [Parameter("Min R:R Ratio", DefaultValue = 2.0)]
        public double MinRewardRatio { get; set; } = 2.0;

        // Risk Management
        [Parameter("Risk %", DefaultValue = 1.0)]
        public double RiskPercent { get; set; } = 1.0;

        [Parameter("Max Daily Trades", DefaultValue = 3)]
        public int MaxDailyTrades { get; set; } = 3;

        // Grid Order Settings
        [Parameter("Enable Grid Orders", DefaultValue = true)]
        public bool EnableGridOrders { get; set; } = true;

        [Parameter("Grid Orders Count", DefaultValue = 5)]
        public int GridOrdersCount { get; set; } = 5;

        [Parameter("Grid Spacing Mode", DefaultValue = "equal")]
        public string GridSpacingMode { get; set; } = "equal";

        [Parameter("Grid Distribution Mode", DefaultValue = "equal")]
        public string GridDistributionMode { get; set; } = "equal";

        // Telegram
        [Parameter("Enable Telegram", DefaultValue = false)]
        public bool EnableTelegram { get; set; } = false;

        [Parameter("Bot Token", DefaultValue = "")]
        public string BotToken { get; set; } = "";

        [Parameter("Chat ID", DefaultValue = "")]
        public string ChatId { get; set; } = "";

        #endregion

        #region Private Fields

        // Auto-detected from chart
        private string _tradeSymbol;

        private StrategyState _state = StrategyState.Idle;
        private TradeDirection _bmsDirection;

        // BMS tracking
        private double _bmsLevel;                    // The swing high/low that was broken
        private double _swingPointBeforeBms;         // The opposite swing point (low for bullish, high for bearish)
        private double _bestExtremumAfterBms;        // Best high/low tracked after BMS
        private double _confirmedExtremum;           // The confirmed peak/valley
        private int _candlesSinceBms;

        // Fibonacci levels
        private double _fibLevel0;
        private double _fibLevel382;
        private double _fibLevel50;
        private double _fibLevel618;
        private double _fibLevel786;
        private double _fibLevel1;
        private double _fibExt127;
        private double _fibExt162;
        private double _entryZoneLow;
        private double _entryZoneHigh;

        // Daily tracking
        private int _dailyTrades;
        private DateTime _lastTradeDate;

        // Grid order management
        private GridOrderManager _gridManager;
        private int _filledGridOrders;

        // Components
        private TelegramClient _telegram;

        #endregion

        [Output("State")]
        public string CurrentState => _state.ToString();

        [Output("Symbol")]
        public string TradeSymbolOutput => _tradeSymbol ?? SymbolName;

        protected override void OnStart()
        {
            // Auto-detect symbol from chart
            _tradeSymbol = SymbolName;

            Print($"=== BMS Fibo Liquidity Bot v2.0 ===");
            Print($"Symbol: {_tradeSymbol} (auto-detected from chart)");
            Print($"Timeframe: {TimeFrame}");
            Print($"Algorithm: BMS → Track Extremum → Confirm → Fibonacci → Entry");
            Print($"Grid Orders: {(EnableGridOrders ? $"Enabled ({GridOrdersCount} orders)" : "Disabled")}");
            Print($"Entry Zone: {EntryZoneMin:F3} - {EntryZoneMax:F3}");

            _state = StrategyState.Idle;

            // Initialize grid manager
            if (EnableGridOrders)
            {
                var gridConfig = new GridConfig
                {
                    Enabled = EnableGridOrders,
                    OrdersCount = GridOrdersCount,
                    Spacing = GridSpacingMode.ToLower() == "fib" ? SpacingMode.Fibonacci :
                              GridSpacingMode.ToLower() == "custom" ? SpacingMode.Custom : SpacingMode.Equal,
                    Distribution = GridDistributionMode.ToLower() == "weighted" ? DistributionMode.Weighted : DistributionMode.Equal
                };
                _gridManager = new GridOrderManager(gridConfig);
            }

            // Initialize Telegram
            if (EnableTelegram && !string.IsNullOrEmpty(BotToken) && !string.IsNullOrEmpty(ChatId))
            {
                _telegram = new TelegramClient(BotToken, ChatId);
                Print("Telegram notifications enabled");

                // Send startup message
                _telegram.SendMessage($"🤖 <b>BMS Fibo Bot Started</b>\n\n" +
                                     $"📊 Symbol: {_tradeSymbol}\n" +
                                     $"⏰ Timeframe: {TimeFrame}\n" +
                                     $"📍 Entry Zone: {EntryZoneMin:F3} - {EntryZoneMax:F3}\n" +
                                     $"🎲 Grid: {(EnableGridOrders ? $"{GridOrdersCount} orders" : "Disabled")}\n" +
                                     $"💰 Risk: {RiskPercent}%");
            }
        }

        protected override void OnBar()
        {
            if (_state == StrategyState.InTrade)
                return;

            // Check daily trade limit
            var today = DateTime.UtcNow.Date;
            if (_lastTradeDate != today)
            {
                _dailyTrades = 0;
                _lastTradeDate = today;
            }

            if (_dailyTrades >= MaxDailyTrades)
                return;

            // State machine
            switch (_state)
            {
                case StrategyState.Idle:
                    CheckForBMS();
                    break;

                case StrategyState.BmsDetected:
                    TrackExtremum();
                    break;

                case StrategyState.TrackingExtremum:
                    CheckExtremumConfirmation();
                    break;

                case StrategyState.ExtremumConfirmed:
                    CheckFibZone();
                    break;

                case StrategyState.InFibZone:
                    CheckLiquiditySweep();
                    break;

                case StrategyState.SweepDetected:
                    CheckConfirmationCandle();
                    break;
            }

            // Check grid order fills if in trade with grid
            if (_state == StrategyState.InTrade && EnableGridOrders && _gridManager != null)
            {
                CheckGridOrderFills();
            }
        }

        #region State Machine Methods

        private void CheckForBMS()
        {
            if (Bars.Count < SwingLookback * 3 + 20)
                return;

            // Find swing highs and lows
            var swingHighs = FindSwingHighs();
            var swingLows = FindSwingLows();

            if (!swingHighs.Any() && !swingLows.Any())
                return;

            var currentClose = Bars.ClosePrices.Last();

            // Check BULLISH BMS (close > last swing high)
            foreach (var swingHigh in swingHighs.OrderByDescending(x => x.Index).Take(3))
            {
                var distance = Bars.Count - 1 - swingHigh.Index;
                if (distance < 3 || distance > SwingLookback * 3)
                    continue;

                if (currentClose <= swingHigh.Price)
                    continue;

                // Check momentum
                if (!CheckMomentum(TradeDirection.Bullish))
                    continue;

                // Find swing low before this swing high
                var swingLowBefore = swingLows
                    .Where(x => x.Index < swingHigh.Index)
                    .OrderByDescending(x => x.Index)
                    .FirstOrDefault();

                if (swingLowBefore == null)
                    continue;

                // BULLISH BMS detected!
                _bmsDirection = TradeDirection.Bullish;
                _bmsLevel = swingHigh.Price;
                _swingPointBeforeBms = swingLowBefore.Price;
                _bestExtremumAfterBms = Bars.HighPrices.Last();
                _candlesSinceBms = 0;
                _state = StrategyState.BmsDetected;

                Print($"🔼 BULLISH BMS detected at {swingHigh.Price:F5}, tracking extremum...");
                return;
            }

            // Check BEARISH BMS (close < last swing low)
            foreach (var swingLow in swingLows.OrderByDescending(x => x.Index).Take(3))
            {
                var distance = Bars.Count - 1 - swingLow.Index;
                if (distance < 3 || distance > SwingLookback * 3)
                    continue;

                if (currentClose >= swingLow.Price)
                    continue;

                // Check momentum
                if (!CheckMomentum(TradeDirection.Bearish))
                    continue;

                // Find swing high before this swing low
                var swingHighBefore = swingHighs
                    .Where(x => x.Index < swingLow.Index)
                    .OrderByDescending(x => x.Index)
                    .FirstOrDefault();

                if (swingHighBefore == null)
                    continue;

                // BEARISH BMS detected!
                _bmsDirection = TradeDirection.Bearish;
                _bmsLevel = swingLow.Price;
                _swingPointBeforeBms = swingHighBefore.Price;
                _bestExtremumAfterBms = Bars.LowPrices.Last();
                _candlesSinceBms = 0;
                _state = StrategyState.BmsDetected;

                Print($"🔽 BEARISH BMS detected at {swingLow.Price:F5}, tracking extremum...");
                return;
            }
        }

        private void TrackExtremum()
        {
            _candlesSinceBms++;

            // Update best extremum
            if (_bmsDirection == TradeDirection.Bullish)
            {
                var currentHigh = Bars.HighPrices.Last();
                if (currentHigh > _bestExtremumAfterBms)
                {
                    _bestExtremumAfterBms = currentHigh;
                    Print($"New high after BMS: {currentHigh:F5}");
                }
            }
            else
            {
                var currentLow = Bars.LowPrices.Last();
                if (currentLow < _bestExtremumAfterBms)
                {
                    _bestExtremumAfterBms = currentLow;
                    Print($"New low after BMS: {currentLow:F5}");
                }
            }

            // Need at least N candles
            if (_candlesSinceBms >= MinExtremumCandles)
                _state = StrategyState.TrackingExtremum;
        }

        private void CheckExtremumConfirmation()
        {
            _candlesSinceBms++;

            // Continue tracking best extremum
            if (_bmsDirection == TradeDirection.Bullish)
            {
                var currentHigh = Bars.HighPrices.Last();
                if (currentHigh > _bestExtremumAfterBms)
                    _bestExtremumAfterBms = currentHigh;
            }
            else
            {
                var currentLow = Bars.LowPrices.Last();
                if (currentLow < _bestExtremumAfterBms)
                    _bestExtremumAfterBms = currentLow;
            }

            var currentClose = Bars.ClosePrices.Last();
            bool confirmed = false;

            // Check for confirmation: price retraces through BMS level
            if (_bmsDirection == TradeDirection.Bullish)
            {
                // Bullish BMS: wait for price to drop back below BMS level
                if (currentClose < _bmsLevel)
                {
                    confirmed = true;
                    _confirmedExtremum = _bestExtremumAfterBms;
                    Print($"✅ BULLISH extremum confirmed at {_confirmedExtremum:F5}");
                }
            }
            else
            {
                // Bearish BMS: wait for price to rise back above BMS level
                if (currentClose > _bmsLevel)
                {
                    confirmed = true;
                    _confirmedExtremum = _bestExtremumAfterBms;
                    Print($"✅ BEARISH extremum confirmed at {_confirmedExtremum:F5}");
                }
            }

            // Timeout check
            if (_candlesSinceBms > ExtremumTimeoutCandles)
            {
                Print("⏱ Extremum tracking timeout, resetting to IDLE");
                ResetState();
                return;
            }

            if (!confirmed)
                return;

            // NOW calculate Fibonacci levels
            CalculateFibonacciLevels();
            _state = StrategyState.ExtremumConfirmed;

            Print($"📐 Fibonacci levels calculated:");
            Print($"   Entry zone: {_entryZoneLow:F5} - {_entryZoneHigh:F5}");
            Print($"   Fib 0.618: {_fibLevel618:F5}");

            // Send Telegram update
            _telegram?.SendMessage($"📐 <b>Fibonacci Calculated</b>\n\n" +
                                  $"{(_bmsDirection == TradeDirection.Bullish ? "🔼" : "🔽")} Direction: {_bmsDirection}\n" +
                                  $"📍 Entry Zone: {_entryZoneLow:F5} - {_entryZoneHigh:F5}\n" +
                                  $"🎯 Extremum: {_confirmedExtremum:F5}");
        }

        private void CheckFibZone()
        {
            var currentClose = Bars.ClosePrices.Last();

            if (currentClose >= _entryZoneLow && currentClose <= _entryZoneHigh)
            {
                Print($"📍 Price entered Fib zone: {currentClose:F5}");
                _state = StrategyState.InFibZone;
            }
        }

        private void CheckLiquiditySweep()
        {
            var currentClose = Bars.ClosePrices.Last();

            // Check if still in zone
            if (currentClose < _entryZoneLow || currentClose > _entryZoneHigh)
            {
                Print("Price left Fib zone, returning to EXTREMUM_CONFIRMED");
                _state = StrategyState.ExtremumConfirmed;
                return;
            }

            // Check for liquidity sweep (wick >= 2x body)
            var open = Bars.OpenPrices.Last();
            var high = Bars.HighPrices.Last();
            var low = Bars.LowPrices.Last();
            var close = Bars.ClosePrices.Last();

            var body = Math.Abs(close - open);
            var range = high - low;

            if (range == 0 || body == 0)
                return;

            double wickRatio;

            if (_bmsDirection == TradeDirection.Bullish)
            {
                // Bullish: looking for long lower wick
                var lowerWick = Math.Min(open, close) - low;
                wickRatio = lowerWick / body;
            }
            else
            {
                // Bearish: looking for long upper wick
                var upperWick = high - Math.Max(open, close);
                wickRatio = upperWick / body;
            }

            if (wickRatio >= MinWickToBodyRatio)
            {
                Print($"💧 Liquidity sweep detected! Wick ratio: {wickRatio:F2}x");
                _state = StrategyState.SweepDetected;
            }
        }

        private void CheckConfirmationCandle()
        {
            var open = Bars.OpenPrices.Last();
            var close = Bars.ClosePrices.Last();
            var high = Bars.HighPrices.Last();
            var low = Bars.LowPrices.Last();

            var body = Math.Abs(close - open);
            var range = high - low;

            if (range == 0)
                return;

            var bodyPercent = body / range;

            // Check direction matches BMS
            bool isBullishCandle = close > open;
            bool isBearishCandle = close < open;

            bool directionMatches = (_bmsDirection == TradeDirection.Bullish && isBullishCandle) ||
                                    (_bmsDirection == TradeDirection.Bearish && isBearishCandle);

            if (!directionMatches)
                return;

            if (bodyPercent < ConfirmationBodyPercent)
                return;

            Print($"✅ Confirmation candle: body {bodyPercent:P0} of range");

            // Check filters
            if (!CheckAllFilters())
            {
                ResetState();
                return;
            }

            // Execute trade (single or grid)
            ExecuteTrade();
        }

        #endregion

        #region Trade Execution

        private void ExecuteTrade()
        {
            var direction = _bmsDirection == TradeDirection.Bullish ? TradeType.Buy : TradeType.Sell;
            var entry = Bars.ClosePrices.Last();

            // Calculate SL with buffer
            double sl;
            if (_bmsDirection == TradeDirection.Bullish)
                sl = _fibLevel1 * (1 - SlBufferPercent / 100);
            else
                sl = _fibLevel1 * (1 + SlBufferPercent / 100);

            double slDistance = Math.Abs(entry - sl);

            if (EnableGridOrders && _gridManager != null)
            {
                ExecuteGridOrders(direction, sl, slDistance);
            }
            else
            {
                ExecuteSingleOrder(direction, entry, sl, slDistance);
            }

            _state = StrategyState.InTrade;
            _dailyTrades++;
        }

        private void ExecuteSingleOrder(TradeType direction, double entry, double sl, double slDistance)
        {
            // Calculate lot size based on risk
            var riskAmount = Account.Balance * RiskPercent / 100;
            var lotSize = riskAmount / slDistance / Symbol.PipValue;
            lotSize = Math.Round(lotSize, 2);
            lotSize = Math.Max(Symbol.VolumeInUnitsMin, lotSize);

            // Place order
            var request = new MarketOrderRequest
            {
                SymbolName = _tradeSymbol,
                TradeType = direction,
                VolumeInUnits = lotSize,
                StopLossInPrice = sl,
                TakeProfitInPrice = _fibLevel0,
                Label = "BMS_FIB_LIQUIDITY"
            };

            ExecuteMarketOrder(request);

            Print($"🚀 Trade executed: {direction} @ {entry:F5}, SL: {sl:F5}, TP1: {_fibLevel0:F5}");

            // Send Telegram notification
            _telegram?.SendMessage($"🚀 <b>Trade Opened</b>\n\n" +
                                  $"📊 Symbol: {_tradeSymbol}\n" +
                                  $"{(_bmsDirection == TradeDirection.Bullish ? "🔼" : "🔽")} Direction: {_bmsDirection}\n" +
                                  $"📍 Entry: {entry:F5}\n" +
                                  $"🛡 SL: {sl:F5}\n" +
                                  $"🎯 TP1: {_fibLevel0:F5}\n" +
                                  $"💎 Extremum: {_confirmedExtremum:F5}");
        }

        private void ExecuteGridOrders(TradeType direction, double sl, double slDistance)
        {
            // Create grid orders
            double fibHigh, fibLow;
            if (_bmsDirection == TradeDirection.Bullish)
            {
                fibHigh = _confirmedExtremum;
                fibLow = _swingPointBeforeBms;
            }
            else
            {
                fibHigh = _swingPointBeforeBms;
                fibLow = _confirmedExtremum;
            }

            _gridManager.CreateGridOrders(
                EntryZoneMin,
                EntryZoneMax,
                fibHigh,
                fibLow,
                RiskPercent,
                _bmsDirection == TradeDirection.Bullish
            );

            // Calculate lot sizes
            _gridManager.CalculateLotSizes(Account.Balance, slDistance, Symbol.PipValue);

            Print("📊 Grid orders created:");
            Print(_gridManager.GetGridSummary());

            // Place first order at current price (market order)
            var firstOrder = _gridManager.Orders.FirstOrDefault();
            if (firstOrder != null)
            {
                var request = new MarketOrderRequest
                {
                    SymbolName = _tradeSymbol,
                    TradeType = direction,
                    VolumeInUnits = firstOrder.LotSize,
                    StopLossInPrice = sl,
                    TakeProfitInPrice = _fibLevel0,
                    Label = "BMS_FIB_GRID"
                };

                ExecuteMarketOrder(request);
                _gridManager.MarkOrderFilled(firstOrder);
                _filledGridOrders = 1;

                Print($"🚀 Grid order 1/{_gridManager.Orders.Count} filled @ {firstOrder.Price:F5}");
            }

            // Place pending orders for remaining grid levels
            var remainingOrders = _gridManager.GetRemainingOrders();
            foreach (var gridOrder in remainingOrders)
            {
                // Place limit order at grid level
                var limitRequest = new LimitOrderRequest
                {
                    SymbolName = _tradeSymbol,
                    TradeType = direction,
                    VolumeInUnits = gridOrder.LotSize,
                    TargetPrice = gridOrder.Price,
                    StopLossInPrice = sl,
                    TakeProfitInPrice = _fibLevel0,
                    Label = "BMS_FIB_GRID"
                };

                var result = PlaceLimitOrder(limitRequest);
                if (result.IsSuccessful)
                {
                    _gridManager.MarkOrderPending(gridOrder, result.Order.Id);
                    Print($"⏳ Grid limit order placed @ {gridOrder.Price:F5} (Fib {gridOrder.FibLevel:F3})");
                }
            }

            // Send Telegram notification with grid summary
            _telegram?.SendMessage($"📊 <b>Grid Orders Placed</b>\n\n" +
                                  $"📊 Symbol: {_tradeSymbol}\n" +
                                  $"{(_bmsDirection == TradeDirection.Bullish ? "🔼" : "🔽")} Direction: {_bmsDirection}\n" +
                                  $"🎯 Grid: {_gridManager.Orders.Count} orders\n\n" +
                                  _gridManager.GetTelegramSummary());
        }

        private void CheckGridOrderFills()
        {
            if (_gridManager == null)
                return;

            var pendingOrders = _gridManager.Orders.Where(o => o.IsPending).ToList();
            foreach (var gridOrder in pendingOrders)
            {
                // Check if the pending order was filled
                var position = Positions.FirstOrDefault(p => p.Label == "BMS_FIB_GRID" &&
                                                             p.EntryPrice == gridOrder.Price);
                if (position != null)
                {
                    _gridManager.MarkOrderFilled(gridOrder, position.Id.ToString());
                    _filledGridOrders++;
                    Print($"✅ Grid order filled @ {gridOrder.Price:F5} ({_filledGridOrders}/{_gridManager.Orders.Count})");

                    // Send Telegram notification
                    _telegram?.SendMessage($"✅ <b>Grid Order Filled</b>\n\n" +
                                          $"📍 Entry: {gridOrder.Price:F5}\n" +
                                          $"📊 Progress: {_filledGridOrders}/{_gridManager.Orders.Count}\n" +
                                          $"💰 Risk Used: {_gridManager.GetTotalRiskUsed():F2}%");
                }
            }
        }

        #endregion

        #region Helper Methods

        private void CalculateFibonacciLevels()
        {
            double high, low;

            if (_bmsDirection == TradeDirection.Bullish)
            {
                // Fib from swing_low to confirmed high
                low = _swingPointBeforeBms;
                high = _confirmedExtremum;
            }
            else
            {
                // Fib from confirmed low to swing_high
                low = _confirmedExtremum;
                high = _swingPointBeforeBms;
            }

            var range = high - low;

            // Standard Fibonacci levels
            _fibLevel0 = high;                      // Previous high (TP1 for bullish)
            _fibLevel382 = high - range * 0.382;
            _fibLevel50 = high - range * 0.5;
            _fibLevel618 = high - range * 0.618;    // Entry zone
            _fibLevel786 = high - range * 0.786;
            _fibLevel1 = low;                       // Previous low (SL for bullish)

            // Extensions
            _fibExt127 = low - range * 0.27;        // TP2
            _fibExt162 = low - range * 0.62;        // TP3

            // Entry zone
            _entryZoneLow = high - range * EntryZoneMax;
            _entryZoneHigh = high - range * EntryZoneMin;
        }

        private List<SwingPoint> FindSwingHighs()
        {
            var swings = new List<SwingPoint>();

            for (int i = 1; i < Bars.Count - 1; i++)
            {
                if (Bars.HighPrices[i] > Bars.HighPrices[i - 1] &&
                    Bars.HighPrices[i] > Bars.HighPrices[i + 1])
                {
                    swings.Add(new SwingPoint { Index = i, Price = Bars.HighPrices[i] });
                }
            }

            return swings;
        }

        private List<SwingPoint> FindSwingLows()
        {
            var swings = new List<SwingPoint>();

            for (int i = 1; i < Bars.Count - 1; i++)
            {
                if (Bars.LowPrices[i] < Bars.LowPrices[i - 1] &&
                    Bars.LowPrices[i] < Bars.LowPrices[i + 1])
                {
                    swings.Add(new SwingPoint { Index = i, Price = Bars.LowPrices[i] });
                }
            }

            return swings;
        }

        private bool CheckMomentum(TradeDirection direction)
        {
            int count = 0;

            for (int i = Bars.Count - 1; i >= Math.Max(0, Bars.Count - 10); i--)
            {
                var open = Bars.OpenPrices[i];
                var close = Bars.ClosePrices[i];
                var high = Bars.HighPrices[i];
                var low = Bars.LowPrices[i];

                var body = Math.Abs(close - open);
                var range = high - low;

                // Check direction
                if (direction == TradeDirection.Bullish)
                {
                    if (close <= open) break;
                }
                else
                {
                    if (close >= open) break;
                }

                // Check body size
                if (range > 0 && body / range < BodyPercentThreshold)
                    break;

                count++;
            }

            return count >= MomentumCandlesRequired;
        }

        private bool CheckAllFilters()
        {
            // R:R filter
            if (EnableRrFilter)
            {
                var entry = Bars.ClosePrices.Last();
                double sl, tp;

                if (_bmsDirection == TradeDirection.Bullish)
                {
                    sl = _fibLevel1 * (1 - SlBufferPercent / 100);
                    tp = _fibLevel0;
                }
                else
                {
                    sl = _fibLevel1 * (1 + SlBufferPercent / 100);
                    tp = _fibLevel0;
                }

                var risk = Math.Abs(entry - sl);
                var reward = Math.Abs(tp - entry);
                var rr = reward / risk;

                if (rr < MinRewardRatio)
                {
                    Print($"⚠️ R:R filter blocked: {rr:F2} < {MinRewardRatio}");
                    return false;
                }
            }

            // Add more filter checks here (Trend, Volume, Volatility)

            return true;
        }

        private void ResetState()
        {
            _state = StrategyState.Idle;
            _bmsLevel = 0;
            _swingPointBeforeBms = 0;
            _bestExtremumAfterBms = 0;
            _confirmedExtremum = 0;
            _candlesSinceBms = 0;
            _filledGridOrders = 0;

            // Reset grid manager
            if (_gridManager != null)
            {
                _gridManager.Reset();
            }
        }

        protected override void OnPositionsClosed(PositionClosedEventArgs args)
        {
            if (args.Position.Label == "BMS_FIB_LIQUIDITY" || args.Position.Label == "BMS_FIB_GRID")
            {
                var profit = args.Position.NetProfit;
                var result = profit >= 0 ? "🎯 TP Hit" : "🛡 SL Hit";

                Print($"{result}: Position closed with P/L: {profit:F2}");

                // Check if all grid positions are closed
                var remainingPositions = Positions.Where(p => p.Label == "BMS_FIB_GRID").Count();

                if (remainingPositions == 0)
                {
                    // Send summary
                    if (_gridManager != null && _gridManager.Orders.Any())
                    {
                        var avgEntry = _gridManager.GetAverageEntry();
                        _telegram?.SendMessage($"🏁 <b>All Grid Positions Closed</b>\n\n" +
                                              $"📊 Symbol: {_tradeSymbol}\n" +
                                              $"{(_bmsDirection == TradeDirection.Bullish ? "🔼" : "🔽")} Direction: {_bmsDirection}\n" +
                                              $"📍 Avg Entry: {avgEntry:F5}\n" +
                                              $"💰 Net P/L: {profit:F2}");
                    }

                    ResetState();
                }
                else
                {
                    // Single position closed in grid
                    _telegram?.SendMessage($"{result}\n\n" +
                                          $"📍 Entry: {args.Position.EntryPrice:F5}\n" +
                                          $"💰 P/L: {profit:F2}\n" +
                                          $"📊 Remaining: {remainingPositions}");
                }
            }
        }

        #endregion

        private class SwingPoint
        {
            public int Index { get; set; }
            public double Price { get; set; }
        }
    }
}
