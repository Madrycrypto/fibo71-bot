# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Fibo 71 Bot** - Automated trading system implementing the **CP 2.0** Fibonacci strategy with BOS (Break of Structure) detection.

**Strategy Core:**
- Detect BOS with Imbalance (IPA) and optional Liquidity Sweep
- Place limit orders at Fibonacci 71-79% retracement zones
- TP at Fib 0%, SL at Fib 100%
- 1% risk per trade (0.5% on correlated pairs)

## Project Structure

```
Fibo_71/
├── src/                      # Python implementation (MetaTrader 5)
│   ├── main.py               # Entry point with CLI
│   ├── strategies/
│   │   └── fibo71_strategy.py    # CP2Strategy - main trading logic
│   ├── indicators/
│   │   ├── bos.py            # BOSDetector - swing points & break detection
│   │   ├── fibonacci.py      # FibonacciCalculator - level calculation
│   │   └── liquidity_sweep.py    # Liquidity sweep filter
│   ├── risk/
│   │   └── manager.py        # RiskManager - 1% rule, correlation handling
│   ├── utils/
│   │   ├── mt5_utils.py      # MT5 connection, orders, positions
│   │   └── telegram.py       # TelegramNotifier - trade alerts
│   └── config/
│       └── loader.py         # JSON config loading
├── mt5/
│   └── Fibo71_CP2_Bot.mq5    # MQL5 Expert Advisor (standalone)
├── pine/
│   └── Fibo71_CP2_Strategy.pine  # TradingView indicator (v5)
└── config/
    └── settings.example.json # Configuration template
```

## Commands

```bash
# Activate virtual environment
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run demo trading (forward test)
python src/main.py --demo

# Run backtest (not yet implemented)
python src/main.py --backtest

# Run live trading (requires confirmation)
python src/main.py --live

# Use custom config
python src/main.py --demo --config config/settings.json

# Set log level
python src/main.py --demo --log-level DEBUG
```

## Key Architecture

### CP2Strategy (`src/strategies/fibo71_strategy.py`)
Main orchestrator that:
1. Calls `BOSDetector.detect_bos()` to find setups
2. Calculates Fibonacci levels via `FibonacciCalculator`
3. Checks risk with `RiskManager.can_open_trade()`
4. Creates `TradeSetup` dataclass with entry/SL/TP
5. Places limit orders via MT5 API

### BOSDetector (`src/indicators/bos.py`)
Detects Break of Structure:
- `_find_swings()` - finds swing highs/lows (2 candles on each side)
- `_check_imbalance()` - detects IPA (gap between candle 1 and 3)
- `_check_liquidity()` - detects false breakout before BOS
- Returns `BOSResult` dataclass

### RiskManager (`src/risk/manager.py`)
- 1% risk per trade, 0.5% on correlated pairs
- `CORRELATION_GROUPS` dict maps currencies to correlated pairs
- `calculate_lot_size()` based on SL distance and risk %
- Max daily trades and open positions limits

### Multi-Platform Implementations

| File | Platform | Purpose |
|------|----------|---------|
| `src/main.py` | Python/MT5 | Full bot with all features |
| `mt5/Fibo71_CP2_Bot.mq5` | MQL5 | Standalone EA (no Python needed) |
| `pine/Fibo71_CP2_Strategy.pine` | TradingView | Visual indicator + alerts |

### Configuration (`config/settings.example.json`)
- `trading.symbol` / `trading.timeframe` - symbol and H1/H4
- `risk.risk_percent` - 1.0 default
- `strategy.entry_zones` - multiple zone presets (aggressive/balanced/conservative/cp20_original)
- `filters.enable_imbalance` / `enable_liquidity_sweep`
- `telegram.bot_token` / `chat_id`

## Telegram Setup

1. Create bot via @BotFather → get `bot_token`
2. Get Chat ID from @userinfobot
3. For MT5 Python: set in config JSON
4. For MQL5 EA: set in EA inputs AND whitelist `https://api.telegram.org` in MT5 Options

## Entry Zone Recommendations (from backtesting)

| Zone | Fib Range | Best Pairs | Profit Factor |
|------|-----------|------------|---------------|
| CP 2.0 Original | 71-79% | AUDUSD, GBPUSD | 2.48 |
| Aggressive | 38-50% | USDJPY, EURUSD | 1.53 |
