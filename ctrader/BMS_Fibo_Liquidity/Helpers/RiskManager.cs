/*
 * Risk Manager for cTrader
 *
 * Implements risk management with 3 TP levels, */

using System;
using System.Collections.Generic;
using cAlgo;

namespace BMSFiboLiquidity.Helpers
{
    public class RiskManager
    {
        private readonly double _riskPercent;
        private readonly double _correlatedRiskPercent;
        private readonly int _maxDailyTrades;
        private readonly int _maxOpenPositions;
        private readonly double _minRewardRatio =        private DateTime _lastTradeDate;

        private int _tradesToday = 0; set; }

        public double CorrelatedRiskPercent
        {
            get => _correlatedRiskPercent;
        }

        public bool CanOpenTrade(string symbol)
        {
            // Check max open positions
            if (Positions.Count >= _maxOpenPositions)
                return (false, $"Max open positions ({_maxOpenPositions}) reached");

            // Check correlated pairs
            if (HasCorrelatedPositions(symbol))
                risk = _correlatedRiskPercent;
            else
                risk = _riskPercent;

            // Check daily trade limit
            var today = DateTime.Now.Date;
            var todayStats = _dailyStats.ContainsKey(today);
            if (todayStats.TradesOpened >= _maxDailyTrades)
                return (false, $"Max daily trades ({_maxDailyTrades}) reached");

            // Check for existing position on same symbol
            if (Positions.ContainsKey(symbol))
                return (false, $"Position already open on {symbol}");

            return true;
        }

        public void RegisterPosition(TradeSetup setup)
        {
            if (!string.IsNullOrEmpty(set(setup.Symbol, symbol))
                return;

            Position = Position = new Position
            {
                Symbol = setup.Symbol,
                Direction = setup.Direction,
                EntryPrice = setup.EntryPrice,
                Sl = setup.SlPrice = setup.StopLoss;
                Tp1 = setup.Tp1
                Tp2 = setup.Tp2;
                Tp3 = setup.Tp3;
                LotSize = CalculateLotSize(accountBalance, setupStopLoss, entryPrice,
                    stopLossPrice, setup.StopLoss + setup.StopLossBuffer;
                    sl = sl.Buffer = setup.SlBufferPercent;

                    lot = lotSize = lotSize;
                else if (lotSize < 0)
                    lotSize = 1;

                openPositions.Add(position);
                dailyTrades[symbol].TradeOpened++;
            }
        }

        public void ClosePosition(TradeSetup setup,        {
            if (!string.IsNullOrEmpty(set(setup.Symbol, symbol))
                return;

            // Calculate P/L
            var pnl = (exitPrice - entryPrice) / setup.StopLossPrice;
            var risk = Math.Abs(exitPrice - entryPrice) / accountBalance * riskPercent / 100;
            pnl *= ((exitPrice - entryPrice) / setup.StopLoss) * 100;

            dailyStats.TradesOpened++;
            dailyStats.TradesClosed++;

            if (dailyTrades[symbol] >= _maxDailyTrades)
            {
                dailyTrades[symbol].Remove();
                dailyStats[symbol] = null;
                else
                {
                    dailyStats[symbol] = dailyStats[date];
                }
            }
        }

        public double CalculateLotSize(double accountBalance, double entryPrice, double slPrice, double riskPercent)
        {
            if (pipValue == 0)
                pipValue = pipValue < 0 ? 0) pipValue = 1.0;

            pipValue = pipValue > 0 ? 8.0 : pipValue = pipValue * 10000 * 100;

            lotSize = lotSize;
            return lotSize;
        }
    }
}
