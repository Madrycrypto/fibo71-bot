/*
 * Risk Manager for cTrader BMS Fibo Liquidity Bot
 *
 * Implements risk management with grid order support.
 */

using System;
using System.Collections.Generic;
using cAlgo;

namespace BMSFiboLiquidity.Helpers
{
    /// <summary>
    /// Daily trading statistics
    /// </summary>
    public class DailyStats
    {
        public DateTime Date { get; set; }
        public int TradesOpened { get; set; }
        public int TradesClosed { get; set; }
        public double TotalPnL { get; set; }
        public double RiskUsed { get; set; }
    }

    /// <summary>
    /// Risk Manager for position sizing and daily limits
    /// </summary>
    public class RiskManager
    {
        private readonly double _riskPercent;
        private readonly double _correlatedRiskPercent;
        private readonly int _maxDailyTrades;
        private readonly int _maxOpenPositions;
        private readonly double _minRewardRatio;

        private DateTime _lastTradeDate;
        private int _tradesToday;
        private readonly Dictionary<DateTime, DailyStats> _dailyStats;

        public double RiskPercent => _riskPercent;
        public double CorrelatedRiskPercent => _correlatedRiskPercent;

        public RiskManager(double riskPercent, double correlatedRiskPercent = 0.5,
                          int maxDailyTrades = 3, int maxOpenPositions = 5, double minRewardRatio = 2.0)
        {
            _riskPercent = riskPercent;
            _correlatedRiskPercent = correlatedRiskPercent;
            _maxDailyTrades = maxDailyTrades;
            _maxOpenPositions = maxOpenPositions;
            _minRewardRatio = minRewardRatio;
            _dailyStats = new Dictionary<DateTime, DailyStats>();
        }

        /// <summary>
        /// Check if we can open a new trade
        /// </summary>
        public (bool CanTrade, string Reason) CanOpenTrade(string symbol, int currentPositionCount)
        {
            // Check max open positions
            if (currentPositionCount >= _maxOpenPositions)
                return (false, $"Max open positions ({_maxOpenPositions}) reached");

            // Check daily trade limit
            var today = DateTime.UtcNow.Date;
            if (_lastTradeDate != today)
            {
                _tradesToday = 0;
                _lastTradeDate = today;
            }

            if (_tradesToday >= _maxDailyTrades)
                return (false, $"Max daily trades ({_maxDailyTrades}) reached");

            return (true, "OK");
        }

        /// <summary>
        /// Register a trade was opened
        /// </summary>
        public void RegisterTrade(string symbol, double riskPercent)
        {
            var today = DateTime.UtcNow.Date;
            _lastTradeDate = today;
            _tradesToday++;

            if (!_dailyStats.ContainsKey(today))
            {
                _dailyStats[today] = new DailyStats { Date = today };
            }

            _dailyStats[today].TradesOpened++;
            _dailyStats[today].RiskUsed += riskPercent;
        }

        /// <summary>
        /// Register a trade was closed
        /// </summary>
        public void RegisterClose(string symbol, double pnl)
        {
            var today = DateTime.UtcNow.Date;

            if (_dailyStats.ContainsKey(today))
            {
                _dailyStats[today].TradesClosed++;
                _dailyStats[today].TotalPnL += pnl;
            }
        }

        /// <summary>
        /// Calculate lot size based on risk
        /// </summary>
        public double CalculateLotSize(double accountBalance, double entryPrice,
                                       double slPrice, double riskPercent, double pipValue)
        {
            if (pipValue <= 0)
                pipValue = 1.0;

            double riskAmount = accountBalance * riskPercent / 100;
            double slDistance = Math.Abs(entryPrice - slPrice);

            if (slDistance <= 0)
                return 0.01;

            double lotSize = riskAmount / slDistance / pipValue;
            lotSize = Math.Round(lotSize, 2);
            lotSize = Math.Max(0.01, lotSize);

            return lotSize;
        }

        /// <summary>
        /// Check if R:R ratio is acceptable
        /// </summary>
        public bool CheckRiskReward(double entryPrice, double slPrice, double tpPrice)
        {
            double risk = Math.Abs(entryPrice - slPrice);
            double reward = Math.Abs(tpPrice - entryPrice);

            if (risk <= 0)
                return false;

            double rr = reward / risk;
            return rr >= _minRewardRatio;
        }

        /// <summary>
        /// Get today's statistics
        /// </summary>
        public DailyStats GetTodayStats()
        {
            var today = DateTime.UtcNow.Date;
            if (_dailyStats.ContainsKey(today))
                return _dailyStats[today];

            return new DailyStats { Date = today };
        }

        /// <summary>
        /// Get statistics for a date range
        /// </summary>
        public List<DailyStats> GetStats(DateTime from, DateTime to)
        {
            var result = new List<DailyStats>();
            foreach (var kvp in _dailyStats)
            {
                if (kvp.Key >= from && kvp.Key <= to)
                    result.Add(kvp.Value);
            }
            return result;
        }
    }
}
