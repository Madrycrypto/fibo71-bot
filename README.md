# Fibo 71 Bot - CP 2.0 Strategy

Automated trading bot based on the **CP 2.0** Fibonacci strategy with Break of Structure (BOS) detection.

## Strategy Overview

### Core Concept
- **Timeframe**: H4 (primary), H1/M15 (optional)
- **Risk**: 1% per trade (0.5% on correlated pairs)
- **Entry**: Fibonacci 71%-79% retracement zones
- **Exit**: TP at 0%, SL at 100% Fibonacci levels

### Entry Conditions
1. **BOS (Break of Structure)** - Impulsive candle breaks previous swing
2. **Imbalance (IPA)** - Price gap between 1st and 3rd candle
3. **Liquidity Sweep** - False breakout before BOS (optional filter)

### Position Management
- **Set and Forget** - No manual adjustments
- **Premium Zone** - Entry above 50% Fib for Sell, below 50% for Buy
- **Limit Orders** - Buy/Sell Limit at 71%-79% retracement

## Project Structure

```
Fibo_71/
├── src/
│   ├── indicators/       # Custom indicators (BOS, Imbalance, Fibonacci)
│   ├── strategies/       # Main strategy logic
│   ├── risk/            # Risk management (1% per trade)
│   └── utils/           # Helper functions
├── tests/               # Unit and integration tests
├── docs/               # Documentation
├── config/             # Configuration files
└── README.md
```

## Quick Start

```bash
# Install dependencies
pip install -r requirements.txt

# Configure settings
cp config/settings.example.json config/settings.json

# Run backtest
python src/main.py --backtest

# Run live (demo first!)
python src/main.py --demo
```

## Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Timeframe | H4 | Primary trading interval |
| Risk | 1% | Risk per trade |
| Entry Zone | 71%-79% | Fibonacci retracement levels |
| TP | 0% | Take Profit at Fib 0% |
| SL | 100% | Stop Loss at Fib 100% |

## Win Rate

- **CP 2.0 (with confirmation)**: ~70%
- **CP 1.0 (Risk entry)**: ~40%

## Disclaimer

**USE AT YOUR OWN RISK.** This bot is for educational purposes. Always test on demo account first. Past performance does not guarantee future results.

## License

MIT License
