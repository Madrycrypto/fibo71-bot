/*
 * BMS Fibonacci Liquidity Bot for cTrader
 *
 * Implements the complete BMS + Fibonacci + Liquidity Sweep strategy
 * according to PDF specification.
 * Market: BTCUSDT | Timeframe: 15m
 */

using System;
using System.Collections.Generic;
using System.Linq;
using cAlgo;
using BMSFiboLiquidity.Helpers;
using BMSFiboLiquidity.Indicators;

using Position = Position;

namespace BMSFiboLiquidity
{
    [Robot(TimeZone = TimeZones.Utc, AccessRights = AccessRights.FullAccess)]
    public class BMSFiboLiquidityBot : Robot
    {
        // Strategy parameters
        [Parameter("Symbol", DefaultValue = "BTCUSDT")]
        public string Symbol { get; set; } = "BTCUSDT";

        [Parameter("Timeframe", DefaultValue = "m15")]
        public TimeFrame TimeFrame
        {
            get => _timeframe;
            set => _timeframe = value;
        }

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
        [Parameter("Entry Min", DefaultValue = 0.62)]
        public double EntryZoneMin { get; set; } = 0.62;

        [Parameter("Entry Max", DefaultValue = 0.71)]
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

        // Telegram
        [Parameter("Enable Telegram", DefaultValue = false)]
        public bool EnableTelegram { get; set; } = false;

        [Parameter("Bot Token", DefaultValue = "")]
        public string BotToken { get; set; } = "";

        [Parameter("Chat ID", DefaultValue = "")]
        public string ChatId { get; set; } = "";

        // Labels
        [Parameter("Show Labels", DefaultValue = true)]
        public bool ShowLabels { get; set; } = true;

        // Private fields
        private BMSDetector _bmsDetector;
        private FibonacciExtendedCalculator _fibCalculator;
        private LiquiditySweepDetector _sweepDetector;
        private AllFilters _filters;
        private RiskManager _riskManager;
        private TelegramClient _telegram;
        private StrategyState _state = StrategyState.Idle;
        private BMSResult _currentBms;
        private FibonacciExtendedLevels _currentFibLevels;
        private LiquiditySweepResult _currentSweep;
        private int _dailyTrades;
        private DateTime _lastTradeDate;

        [Output("State")]
        public string State => _state.ToString();

        protected override void OnStart()
        {
            Print($"BMS Fibo Liquidity Bot initialized for {Symbol} on {TimeFrame}");
            _state = StrategyState.Idle;

            // Initialize indicators
            _bmsDetector = Indicators.GetIndicator<BMSDetector>();
            _fibCalculator = new FibonacciExtendedCalculator();
            _sweepDetector = new LiquiditySweepDetector();
            _filters = new AllFilters();

            // Initialize risk manager
            _riskManager = new RiskManager(RiskPercent, CorrelatedRiskPercent, MaxDailyTrades, MaxOpenPositions);

            // Initialize Telegram
            if (EnableTelegram && !string.IsNullOrEmpty(BotToken) || !string.IsNullOrEmpty(ChatId))
            {
                _telegram = new TelegramClient(BotToken, ChatId);
                Print("Telegram notifications enabled");
            }
        }

        protected override void OnTick()
        {
            if (_state == StrategyState.InTrade)
                return;

            // Check for BMS
            if (_state == StrategyState.Idle)
            {
                var result = _bmsDetector.DetectBMS(Bars);
                if (result.Detected)
                {
                    _currentBms = result;
                    _state = StrategyState.BmsDetected;
                    OnBMSDetected?.Invoke();
                }
            }
            // Check for price in Fibonacci zone
            if (_state == StrategyState.BmsDetected)
            {
                var price = Bars.ClosePrices.Last();
                var fibResult = _fibCalculator.IsInEntryZone(price, _currentFibLevels);
                if (fibResult.Item1)
                {
                    _state = StrategyState.InFibZone;
                    OnFibZoneEntered?.Invoke();
                }
            }
            // Check for liquidity sweep
            if (_state == StrategyState.InFibZone)
            {
                var sweepResult = _sweepDetector.DetectSweep(Bars, _currentFibLevels.Level618,
                    _currentBms.Direction == TrendDirection.Bullish ? SweepDirection.Bullish : SweepDirection.Bearish);

                if (sweepResult.Detected)
                {
                    _currentSweep = sweepResult;
                    _state = StrategyState.SweepDetected;
                    OnLiquiditySweepDetected?.Invoke();
                }
            }
            // Check for confirmation candle
            if (_state == StrategyState.SweepDetected)
            {
                var confirmResult = _sweepDetector.CheckConfirmationCandle(Bars, _currentBms.Direction);
 ConfirmationBodyPercent);

                if (confirmResult.Item1)
                {
                    // Check all filters
                    var filterResult = _filters.CheckAll(Bars, _currentBms.Direction,
                        _currentFibLevels.Level0);

                    if (!filterResult.AllPassed)
                    {
                        OnFilterBlocked?.Invoke(filterResult.BlockedBy);
                        _state = StrategyState.Idle;
                        return;
                    }

                    // Execute trade
                    ExecuteTrade();
                    _state = StrategyState.InTrade;
                    _dailyTrades++;
                }
            }
        }

        private void ExecuteTrade()
        {
            if (!CanExecuteTrade(_currentBms, _currentFibLevels, _currentSweep))
                {
                Print("Cannot execute trade - risk manager blocked");
                return;
            }

            var direction = _currentBms.Direction == TrendDirection.Bullish ? TradeType.Buy : TradeType.Sell;

            var entryPrice = Bars.ClosePrices.Last();
            var slPrice = _currentFibLevels.SwingLow * (1 - SlBufferPercent / 100);
            var tp1 = _currentFibLevels.Level0;
            var tp2 = _currentFibLevels.Ext127;
            var tp3 = _currentFibLevels.Ext162;

            // Calculate lot size
            var lotSize = _riskManager.CalculateLotSize(Account.Balance, entryPrice, slPrice, Symbol);

 RiskPercent);

            // Place order
            var request = new MarketOrderRequest
            {
                SymbolName = Symbol,
                TradeType = direction == TradeType.Buy ? TradeType.Buy : TradeType.Sell,
                Volume = lotSize,
                Price = entryPrice,
                StopLossPips = slPips,
                TakeProfit = tp1
                Comment = $"BMS Fib Liquidity {Symbol}"
                MagicNumber = MagicNumber
            };

            ExecuteMarketOrder(request);
            Print($"Order placed: {direction} @ {entryPrice:F5} SL: {slPrice:F5} TP1: {tp1:F5}");

            // Send Telegram notification
            _telegram?.SendTradeEntry(_currentBms, _currentFibLevels, _currentSweep, lotSize, Symbol, TimeFrame);
        }

        private int CanExecuteTrade(BMSResult bms, FibonacciExtendedLevels fib, LiquiditySweepResult sweep)
        {
            // Check risk manager
            if (!_riskManager.CanOpenTrade(Symbol))
                return false;

            // Check daily trade limit
            if (_riskManager.DailyTrades >= _riskManager.MaxDailyTrades)
            {
                Print($"Daily trade limit reached ({_riskManager.MaxDailyTrades})");
                return false;
            }

            return true;
        }

    }
}
