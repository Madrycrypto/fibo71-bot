/*
 * Grid Order Manager for cTrader BMS Fibo Liquidity Bot
 *
 * Supports multiple entry points within the Fibonacci zone:
 * - Equal spacing: orders evenly distributed
 * - Fib spacing: orders at Fibonacci levels
 * - Custom spacing: user-defined levels
 *
 * Risk is distributed across all orders.
 */

using System;
using System.Collections.Generic;
using System.Linq;

namespace BMSFiboLiquidity.Helpers
{
    /// <summary>
    /// Spacing mode for grid orders
    /// </summary>
    public enum SpacingMode
    {
        Equal,          // Evenly spaced orders
        Fibonacci,      // At Fibonacci levels
        Custom          // User-defined
    }

    /// <summary>
    /// Distribution mode for risk allocation
    /// </summary>
    public enum DistributionMode
    {
        Equal,          // Equal risk per order
        Weighted        // More weight at better levels
    }

    /// <summary>
    /// Single grid order
    /// </summary>
    public class GridOrder
    {
        public double FibLevel { get; set; }        // Fibonacci level (0.62, 0.65, etc.)
        public double Price { get; set; }           // Actual price
        public double RiskPercent { get; set; }     // Risk % for this order
        public double LotSize { get; set; }         // Position size
        public string OrderId { get; set; }         // Order ID after placement
        public bool IsFilled { get; set; }          // Whether order was filled
        public bool IsPending { get; set; }         // Whether limit order is pending
    }

    /// <summary>
    /// Grid configuration
    /// </summary>
    public class GridConfig
    {
        public bool Enabled { get; set; } = true;
        public int OrdersCount { get; set; } = 5;
        public SpacingMode Spacing { get; set; } = SpacingMode.Equal;
        public DistributionMode Distribution { get; set; } = DistributionMode.Equal;
        public double[] CustomLevels { get; set; } = null;  // e.g., [0.62, 0.65, 0.68, 0.71]
    }

    /// <summary>
    /// Manages grid orders within Fibonacci entry zone
    /// </summary>
    public class GridOrderManager
    {
        private readonly GridConfig _config;
        private readonly List<GridOrder> _orders = new List<GridOrder>();
        private double _totalRiskPercent = 0.0;

        public IReadOnlyList<GridOrder> Orders => _orders.AsReadOnly();
        public double TotalRiskPercent => _totalRiskPercent;

        public GridOrderManager(GridConfig config)
        {
            _config = config ?? new GridConfig();
        }

        /// <summary>
        /// Calculate Fibonacci levels for grid orders
        /// </summary>
        public List<double> CalculateGridLevels(double entryZoneMin, double entryZoneMax)
        {
            var levels = new List<double>();

            if (_config.Spacing == SpacingMode.Custom && _config.CustomLevels != null)
            {
                // Filter custom levels to be within zone
                levels = _config.CustomLevels
                    .Where(l => l >= entryZoneMin && l <= entryZoneMax)
                    .ToList();
            }
            else if (_config.Spacing == SpacingMode.Fibonacci)
            {
                // Use Fibonacci levels within zone
                var fibLevels = new[] { 0.382, 0.5, 0.618, 0.65, 0.70, 0.786 };
                levels = fibLevels
                    .Where(l => l >= entryZoneMin && l <= entryZoneMax)
                    .Take(_config.OrdersCount)
                    .ToList();
            }
            else // Equal spacing
            {
                if (_config.OrdersCount == 1)
                {
                    levels.Add((entryZoneMin + entryZoneMax) / 2);
                }
                else
                {
                    double step = (entryZoneMax - entryZoneMin) / (_config.OrdersCount - 1);
                    for (int i = 0; i < _config.OrdersCount; i++)
                    {
                        levels.Add(entryZoneMin + i * step);
                    }
                }
            }

            return levels;
        }

        /// <summary>
        /// Calculate risk per order
        /// </summary>
        public List<double> CalculateRiskDistribution(double totalRisk)
        {
            int count = _orders.Count > 0 ? _orders.Count : _config.OrdersCount;
            var risks = new List<double>();

            if (_config.Distribution == DistributionMode.Weighted)
            {
                // More weight at lower prices for LONG, higher for SHORT
                var weights = new List<double>();
                for (int i = 0; i < count; i++)
                {
                    weights.Add(1.0 + (i * 0.2));
                }
                double totalWeight = weights.Sum();
                risks = weights.Select(w => totalRisk * w / totalWeight).ToList();
            }
            else // Equal
            {
                double perOrder = totalRisk / count;
                risks = Enumerable.Repeat(perOrder, count).ToList();
            }

            return risks;
        }

        /// <summary>
        /// Create grid orders within the Fibonacci zone
        /// </summary>
        public List<GridOrder> CreateGridOrders(
            double entryZoneMin,
            double entryZoneMax,
            double fibHigh,
            double fibLow,
            double totalRiskPercent,
            bool isBullish)
        {
            // Calculate levels
            var levels = CalculateGridLevels(entryZoneMin, entryZoneMax);

            // Ensure we have the requested number of orders
            while (levels.Count < _config.OrdersCount)
            {
                if (levels.Count >= 2)
                {
                    double mid = (levels[levels.Count - 1] + levels[levels.Count - 2]) / 2;
                    levels.Insert(levels.Count - 1, mid);
                }
                else
                {
                    levels.Add((entryZoneMin + entryZoneMax) / 2);
                }
            }

            levels = levels.Take(_config.OrdersCount).ToList();

            // Calculate prices from Fib levels
            double fibRange = fibHigh - fibLow;
            var prices = new List<double>();
            foreach (var level in levels)
            {
                // Fib level to price: higher level = lower price for bullish
                double price = fibHigh - (fibRange * level);
                prices.Add(price);
            }

            // Calculate risk distribution
            var risks = CalculateRiskDistribution(totalRiskPercent);

            // Create orders
            _orders.Clear();
            for (int i = 0; i < levels.Count; i++)
            {
                var order = new GridOrder
                {
                    FibLevel = levels[i],
                    Price = prices[i],
                    RiskPercent = risks[i],
                    LotSize = 0.0,
                    IsFilled = false,
                    IsPending = false
                };
                _orders.Add(order);
            }

            _totalRiskPercent = totalRiskPercent;
            return _orders;
        }

        /// <summary>
        /// Calculate lot size for each grid order
        /// </summary>
        public List<double> CalculateLotSizes(double accountBalance, double slDistance, double pipValue = 1.0)
        {
            foreach (var order in _orders)
            {
                double riskAmount = accountBalance * order.RiskPercent / 100;
                if (slDistance > 0)
                {
                    order.LotSize = riskAmount / slDistance / pipValue;
                    order.LotSize = Math.Max(0.01, Math.Round(order.LotSize, 2));
                }
                else
                {
                    order.LotSize = 0.01;
                }
            }

            return _orders.Select(o => o.LotSize).ToList();
        }

        /// <summary>
        /// Check if price has reached any grid order level
        /// </summary>
        public GridOrder GetOrderAtPrice(double currentPrice, double tolerance = 0.001)
        {
            foreach (var order in _orders)
            {
                if (order.IsFilled)
                    continue;

                double priceDiff = Math.Abs(currentPrice - order.Price) / order.Price;
                if (priceDiff <= tolerance)
                {
                    return order;
                }
            }
            return null;
        }

        /// <summary>
        /// Mark an order as filled
        /// </summary>
        public void MarkOrderFilled(GridOrder order, string orderId = null)
        {
            order.IsFilled = true;
            order.IsPending = false;
            if (!string.IsNullOrEmpty(orderId))
                order.OrderId = orderId;
        }

        /// <summary>
        /// Mark an order as pending (limit order placed)
        /// </summary>
        public void MarkOrderPending(GridOrder order, string orderId)
        {
            order.IsPending = true;
            order.OrderId = orderId;
        }

        /// <summary>
        /// Get number of filled orders
        /// </summary>
        public int GetFilledCount()
        {
            return _orders.Count(o => o.IsFilled);
        }

        /// <summary>
        /// Get unfilled orders
        /// </summary>
        public List<GridOrder> GetRemainingOrders()
        {
            return _orders.Where(o => !o.IsFilled).ToList();
        }

        /// <summary>
        /// Get total risk used by filled orders
        /// </summary>
        public double GetTotalRiskUsed()
        {
            return _orders.Where(o => o.IsFilled).Sum(o => o.RiskPercent);
        }

        /// <summary>
        /// Get weighted average entry price of filled orders
        /// </summary>
        public double GetAverageEntry()
        {
            var filled = _orders.Where(o => o.IsFilled).ToList();
            if (!filled.Any())
                return 0.0;

            double totalValue = filled.Sum(o => o.Price * o.LotSize);
            double totalLots = filled.Sum(o => o.LotSize);

            return totalLots > 0 ? totalValue / totalLots : 0.0;
        }

        /// <summary>
        /// Reset all orders
        /// </summary>
        public void Reset()
        {
            _orders.Clear();
            _totalRiskPercent = 0.0;
        }

        /// <summary>
        /// Get human-readable summary of grid orders
        /// </summary>
        public string GetGridSummary()
        {
            if (!_orders.Any())
                return "No grid orders";

            var lines = new List<string> { $"Grid Orders ({_orders.Count} total):" };
            for (int i = 0; i < _orders.Count; i++)
            {
                var order = _orders[i];
                string status = order.IsFilled ? "✅" : (order.IsPending ? "⏳" : "⬜");
                lines.Add($"  {i + 1}. Fib {order.FibLevel:F3} @ {order.Price:F5} " +
                         $"(Risk: {order.RiskPercent:F2}%, Lot: {order.LotSize:F2}) {status}");
            }

            lines.Add($"Filled: {GetFilledCount()}/{_orders.Count}");
            lines.Add($"Total Risk Used: {GetTotalRiskUsed():F2}%");

            if (GetFilledCount() > 0)
            {
                lines.Add($"Avg Entry: {GetAverageEntry():F5}");
            }

            return string.Join("\n", lines);
        }

        /// <summary>
        /// Get Telegram formatted summary
        /// </summary>
        public string GetTelegramSummary()
        {
            if (!_orders.Any())
                return "No grid orders";

            var lines = new List<string>
            {
                $"📊 <b>Grid Orders</b> ({_orders.Count} total)",
                ""
            };

            for (int i = 0; i < _orders.Count; i++)
            {
                var order = _orders[i];
                string status = order.IsFilled ? "✅" : (order.IsPending ? "⏳" : "⬜");
                lines.Add($"{status} <b>{i + 1}.</b> Fib {order.FibLevel:F3} @ {order.Price:F5}");
                lines.Add($"   Risk: {order.RiskPercent:F2}% | Lot: {order.LotSize:F2}");
            }

            lines.Add("");
            lines.Add($"📈 <b>Filled:</b> {GetFilledCount()}/{_orders.Count}");
            lines.Add($"💰 <b>Risk Used:</b> {GetTotalRiskUsed():F2}%");

            if (GetFilledCount() > 0)
            {
                lines.Add($"📍 <b>Avg Entry:</b> {GetAverageEntry():F5}");
            }

            return string.Join("\n", lines);
        }
    }
}
