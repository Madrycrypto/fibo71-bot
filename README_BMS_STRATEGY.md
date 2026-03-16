# BMS Fibo Liquidity Strategy - Kompletna Dokumentacja

## Przegląd Strategii

**BMS (Break of Market Structure) + Fibonacci + Liquidity Sweep**

Strategia oparta na specyfikacji PDF dla **BTCUSDT** na timeframe **M15**.

---

## Poprawiony Algorytm (Krok po Kroku)

```
1. WYKRYJ BMS (Break of Market Structure)
   ├── Bullish: close > swing_high (z momentum)
   ├── Bearish: close < swing_low (z momentum)
   └── Momentum: 3 kolejne świece w kierunku, body >= 60%
   ↓
2. ŚLEDŹ NOWE EXTREMUM
   ├── Bullish: śledź najwyższy HIGH po BMS
   ├── Bearish: śledź najniższy LOW po BMS
   └── Min 1 świeca przed potwierdzeniem
   ↓
3. CZEKAJ NA POTWIERDZENIE EXTREMUM
   ├── Bullish: cena wraca PONIŻEJ poziomu BMS (swing_high)
   ├── Bearish: cena wraca POWYŻEJ poziomu BMS (swing_low)
   └── Timeout: 50 świec max
   ↓
4. OBLICZ POZIOMY FIBONACCI
   ├── Bullish: Fib od swing_low → potwierdzony szczyt
   ├── Bearish: Fib od swing_high → potwierdzony dołek
   └── Strefa wejścia: 0.62 - 0.71
   ↓
5. CZEKAJ NA WEJŚCIE DO STREFY FIB
   └── Price w zakresie entry_zone_min → entry_zone_max
   ↓
6. WYKRYJ LIQUIDITY SWEEP
   ├── Wick >= 2x body (minimum)
   ├── Idealnie: Wick >= 3x body
   └── Bullish: długi dolny knot / Bearish: długi górny knot
   ↓
7. CZEKAJ NA CONFIRMATION CANDLE
   ├── Body >= 50% zakresu świecy
   ├── Kierunek zgodny z BMS
   └── Pojawia się PO Liquidity Sweep
   ↓
8. SPRAWDŹ FILTRY
   ├── Trend Filter (EMA 50/200) - opcjonalny
   ├── Volume Filter (current > avg 20) - opcjonalny
   ├── Volatility Filter (ATR14 > avg ATR20) - opcjonalny
   └── R:R Filter (min 1:2) - wymagany
   ↓
9. WYKONAJ TRADE
   ├── Entry: close confirmation candle
   ├── SL: Fib 1.0 + buffer 0.1%
   ├── TP1: Fib 0.0 (33% pozycji)
   ├── TP2: Fib 1.27 (33% pozycji)
   └── TP3: Fib 1.62 (34% pozycji)
```

---

## Szczegółowy Opis Komponentów

### 1. Swing Detection

**Cel:** Znajdź lokalne szczyty i dołki

**Algorytm:**
```
Swing High: high[i] > high[i-1] AND high[i] > high[i+1]
Swing Low:  low[i] < low[i-1] AND low[i] < low[i+1]
Lookback: 5 świec
```

**Parametry:**
| Parametr | Domyślnie | Opis |
|----------|-----------|------|
| `swing_lookback` | 5 | Okno detekcji swing point |

---

### 2. BMS Detection

**Cel:** Wykryj przełamanie struktury rynku

**Warunki BULLISH BMS:**
1. Close > ostatni swing_high
2. Momentum: min 3 kolejne świece bullish
3. Każda świeca: body >= 60% range
4. Dystans: (close - swing_high) > 0.5 * ATR(14)

**Warunki BEARISH BMS:**
1. Close < ostatni swing_low
2. Momentum: min 3 kolejne świece bearish
3. Każda świeca: body >= 60% range
4. Dystans: (swing_low - close) > 0.5 * ATR(14)

**Parametry:**
| Parametr | Domyślnie | Opis |
|----------|-----------|------|
| `momentum_candles` | 3 | Min liczba świec momentum |
| `body_threshold` | 0.60 | Body jako % range (60%) |
| `distance_atr` | 0.5 | Min dystans w ATR |

---

### 3. Extremum Tracking

**Cel:** Znajdź punkt końcowy Fibonacci

**Dlaczego to ważne?**
- Nie możemy narysować Fibonacci od razu po BMS
- Potrzebujemy DWA punkty: swing_point + potwierdzony_extremum
- Dopiero gdy cena cofnie się przez BMS, wiemy że mamy szczyt/dołek

**BULLISH:**
```
1. BMS detected (close > swing_high)
2. Track highest high after BMS
3. Wait for price < BMS level (swing_high)
4. Confirmed extremum = highest high tracked
5. Fibonacci: swing_low → confirmed_extremum
```

**BEARISH:**
```
1. BMS detected (close < swing_low)
2. Track lowest low after BMS
3. Wait for price > BMS level (swing_low)
4. Confirmed extremum = lowest low tracked
5. Fibonacci: swing_high → confirmed_extremum
```

**Parametry:**
| Parametr | Domyślnie | Opis |
|----------|-----------|------|
| `min_candles` | 1 | Min świec przed potwierdzeniem |
| `timeout_candles` | 50 | Max świec do potwierdzenia |

---

### 4. Fibonacci Levels

**Poziomy standardowe:**
| Level | Wzór | Zastosowanie |
|-------|------|--------------|
| 0.0 | High | TP1 |
| 0.382 | High - Range*0.382 | - |
| 0.5 | High - Range*0.5 | - |
| 0.618 | High - Range*0.618 | Entry zone start |
| 0.71 | High - Range*0.71 | Entry zone end |
| 0.786 | High - Range*0.786 | SL area |
| 1.0 | Low | SL base |

**Rozszerzenia (Extensions):**
| Level | Wzór | Zastosowanie |
|-------|------|--------------|
| 1.27 | Low - Range*0.27 | TP2 |
| 1.62 | Low - Range*0.62 | TP3 |

**Parametry:**
| Parametr | Domyślnie | Opis |
|----------|-----------|------|
| `entry_min` | 0.62 | Początek strefy wejścia |
| `entry_max` | 0.71 | Koniec strefy wejścia |

---

### 5. Liquidity Sweep

**Cel:** Wykryj "wycięcie" stop lossów przed wejściem

**Definicja:**
```
Wick Ratio = Wick Length / Body Length

BULLISH Sweep: Lower Wick >= 2x Body
BEARISH Sweep: Upper Wick >= 2x Body
```

**Przykład BULLISH:**
```
        ┌───┐
        │   │  ← Body = 10
        │   │
    ┌───┴───┴───┐
    │           │ ← Lower Wick = 25
    └───────────┘

    Wick Ratio = 25/10 = 2.5x ✓
```

**Parametry:**
| Parametr | Domyślnie | Opis |
|----------|-----------|------|
| `min_wick_ratio` | 2.0 | Min wick/body ratio |
| `ideal_wick_ratio` | 3.0 | Idealny wick/body ratio |

---

### 6. Confirmation Candle

**Cel:** Potwierdź odwrócenie po Liquidity Sweep

**Warunki:**
1. **Kierunek zgodny z BMS:**
   - BULLISH: close > open (zielona świeca)
   - BEARISH: close < open (czerwona świeca)

2. **Body >= 50% range:**
   ```
   Body = |Close - Open|
   Range = High - Low
   Body% = Body / Range >= 0.50
   ```

**Parametry:**
| Parametr | Domyślnie | Opis |
|----------|-----------|------|
| `body_percent` | 0.50 | Min body jako % range |

---

## Filtry - Szczegółowy Opis

### 1. Trend Filter (EMA 50/200)

**Co sprawdza:**
```
BULLISH: EMA50 > EMA200 (uptrend)
BEARISH: EMA50 < EMA200 (downtrend)
```

**Kiedy włączyć:**
- Trend following strategies
- Dłuższe timeframe'y (H1, H4)
- Początkujący traderzy

**Kiedy wyłączyć:**
- Scalping na niskich timeframe'ach
- Mean reversion strategies
- Consolidation markets

**Konfiguracja:**
```json
"filters": {
  "enable_trend": true,
  "ema_fast": 50,
  "ema_slow": 200
}
```

---

### 2. Volume Filter

**Co sprawdza:**
```
Current Volume > Average Volume (20 okresów)
```

**Kiedy włączyć:**
- Breakout trading
- Rynki z dobrym wolumenem (BTC, ETH)
- Potwierdzenie momentum

**Kiedy wyłączyć:**
- Rynki o niskim wolumenie
- Weekend trading (crypto)
- Thin markets

**Konfiguracja:**
```json
"filters": {
  "enable_volume": true,
  "volume_lookback": 20
}
```

---

### 3. Volatility Filter (ATR)

**Co sprawdza:**
```
ATR(14) > Average ATR(20)
```

**Cel:** Unika handlu w okresach niskiej zmienności

**Kiedy włączyć:**
- Trend following
- Swing trading
- Unikanie choppy markets

**Kiedy wyłączyć:**
- Scalping (potrzebna stabilna zmienność)
- Range trading

**Konfiguracja:**
```json
"filters": {
  "enable_volatility": true
}
```

---

### 4. Risk:Reward Filter

**Co sprawdza:**
```
R:R = (TP - Entry) / (Entry - SL) >= min_rr_ratio
```

**Przykład:**
```
Entry: 100
SL: 98
TP: 104

Risk = 100 - 98 = 2
Reward = 104 - 100 = 4
R:R = 4/2 = 2:1 ✓
```

**Kiedy włączyć:**
- ZAWSZE zalecane!
- Long-term profitability
- Risk management

**Konfiguracja:**
```json
"filters": {
  "enable_rr": true,
  "min_rr_ratio": 2.0
}
```

---

## Risk Management

### Stop Loss

```
SL = Fib 1.0 ± Buffer

BULLISH: SL = Fib 1.0 * (1 - buffer%)
BEARISH: SL = Fib 1.0 * (1 + buffer%)

Buffer: 0.1% (domyślnie)
```

**Cel bufferu:** Uniknąć "stop hunting"

---

### Take Profit Levels

| TP | Poziom | % Pozycji | Opis |
|----|--------|-----------|------|
| TP1 | Fib 0.0 | 33% | Previous High/Low |
| TP2 | Fib 1.27 | 33% | Extension 127% |
| TP3 | Fib 1.62 | 34% | Extension 162% |

---

### Daily Limits

| Parametr | Domyślnie | Opis |
|----------|-----------|------|
| `risk_percent` | 1.0% | Ryzyko per trade |
| `max_daily_trades` | 3 | Max trades dziennie |

---

## Telegram Notifications

### Typy powiadomień:

| # | Typ | Emoji | Opis |
|---|-----|-------|------|
| 1 | BMS Detected | 🔥 | Wykryto BMS |
| 2 | Extremum Confirmed | ✅ | Potwierdzono extremum, Fib obliczony |
| 3 | Fib Zone Entered | 📍 | Cena w strefie wejścia |
| 4 | Liquidity Sweep | 💧 | Wykryto liquidity sweep |
| 5 | Trade Opened | 🚀 | Pozycja otwarta |
| 6 | Trade Closed (TP) | 💰 | Take Profit hit |
| 7 | Trade Closed (SL) | 🛑 | Stop Loss hit |
| 8 | Filter Blocked | ⛔ | Trade zablokowany przez filtr |
| 9 | Daily Summary | 📊 | Podsumowanie dnia |
| 10 | Error | ⚠️ | Błąd systemowy |

### Przykładowe wiadomości:

**BMS Detected:**
```
🔥 BMS DETECTED
Symbol: BTCUSDT
Direction: BULLISH
BMS Level: 43250.50
Swing Low: 42800.00

Tracking extremum...
```

**Extremum Confirmed:**
```
✅ EXTREMUM CONFIRMED
Symbol: BTCUSDT
Direction: BULLISH
Confirmed High: 43850.00
BMS Level: 43250.50

Fibonacci calculated:
• Entry Zone: 43320 - 43550
• SL: 42800.00
• TP1: 43850.00
```

**Trade Opened:**
```
🚀 TRADE OPENED
Symbol: BTCUSDT
Direction: BUY
Entry: 43420.50
SL: 42757.20 (-1.53%)
TP1: 43850.00 (+0.99%)
TP2: 44100.00
TP3: 44350.00

R:R: 1:2.1
Lot: 0.15
Risk: 1.0%
```

---

### Zestaw 1: Konserwatywn (Początkujący)

**Dla:** Nowi traderzy, demo testing, małe konta

**Charakterystyka:**
- Mniejsze ryzyko (0.5% per trade)
- Maksymalnie 2 trades dziennie
- Wszystkie filtry włączone
- Wyższy próg wick/body (2.5x)
- Wyższy próg confirmation candle (60%)
- Większy SL buffer (0.15%)
- **Grid ENABLED** (5 orders, equal distribution)

```json
{
  "risk": { "risk_percent": 0.5, "max_daily_trades": 2 },
  "bms": { "momentum_candles": 3, "body_threshold": 0.60 },
  "liquidity_sweep": { "min_wick_ratio": 2.5 },
  "confirmation": { "body_percent": 0.60 },
  "sl": { "buffer_percent": 0.15 },
  "filters": {
    "enable_trend": true,
    "enable_volume": true,
    "enable_volatility": true,
    "enable_rr": true,
    "min_rr_ratio": 2.5
  }
}
```

### Zestaw 2: Zbalansowany (Rekomendowany)

```json
{
  "risk": { "risk_percent": 1.0, "max_daily_trades": 3 },
  "bms": { "momentum_candles": 3, "body_threshold": 0.60 },
  "liquidity_sweep": { "min_wick_ratio": 2.0 },
  "confirmation": { "body_percent": 0.50 },
  "sl": { "buffer_percent": 0.1 },
  "filters": {
    "enable_trend": true,
    "enable_volume": true,
    "enable_volatility": true,
    "enable_rr": true,
    "min_rr_ratio": 2.0
  }
}
```

### Zestaw 3: Agresywny (Doświadczeni)

```json
{
  "risk": { "risk_percent": 1.5, "max_daily_trades": 5 },
  "bms": { "momentum_candles": 2, "body_threshold": 0.50 },
  "liquidity_sweep": { "min_wick_ratio": 1.5 },
  "confirmation": { "body_percent": 0.40 },
  "sl": { "buffer_percent": 0.05 },
  "filters": {
    "enable_trend": true,
    "enable_volume": false,
    "enable_volatility": false,
    "enable_rr": true,
    "min_rr_ratio": 1.5
  }
}
```

---

## Bezpieczeństwo

### 1. Walidacja danych

```python
# Sprawdź czy DataFrame ma wystarczająco danych
if len(df) < max(swing_lookback * 2, atr_period + 5):
    return BMSResult(detected=False, message="Insufficient data")

# Sprawdź czy ceny są dodatnie
if df['close'].iloc[-1] <= 0:
    logger.error("Invalid price data")
    return None
```

### 2. Timeout Protection

```python
# Unikaj nieskończonego czekania na potwierdzenie
MAX_EXTREMUM_CANDLES = 50
if candles_since_bms > MAX_EXTREMUM_CANDLES:
    logger.warning("Extremum tracking timeout")
    reset_state()
```

### 3. Daily Limits

```python
# Sprawdź limity przed każdym trade
if daily_trades >= MAX_DAILY_TRADES:
    logger.info(f"Daily limit reached ({MAX_DAILY_TRADES})")
    return None
```

### 4. R:R Validation

```python
# Zawsze sprawdzaj R:R przed wejściem
rr = calculate_rr(entry, sl, tp)
if rr < MIN_RR_RATIO:
    logger.warning(f"R:R too low: {rr:.2f} < {MIN_RR_RATIO}")
    return None
```

### 5. Position Size Validation

```python
# Oblicz lot na podstawie ryzyka
lot = (account_balance * risk_percent / 100) / sl_distance
lot = max(min_lot, min(max_lot, lot))  # Clamp to valid range
```

---

## CLI Commands

```bash
# Pokaż pomoc
python src/main_bms.py --help

# Backtest (ostatnie 3 miesiące)
python src/main_bms.py --backtest --days 90

# Backtest z własnym configiem
python src/main_bms.py --backtest --config config/conservative.json

# Demo mode (paper trading)
python src/main_bms.py --demo

# Live mode (OSTROŻNIE!)
python src/main_bms.py --live

# Wyłącz filtry
python src/main_bms.py --demo --no-volume-filter --no-volatility-filter

# Debug mode
python src/main_bms.py --demo --log-level DEBUG

# Określ symbol i timeframe
python src/main_bms.py --backtest --symbol ETHUSDT --timeframe H1
```

---

## Tabela Decyzyjna Filtrów

| Sytuacja | Trend | Volume | Volatility | R:R |
|----------|:-----:|:------:|:----------:|:---:|
| Początkujący | ✅ ON | ✅ ON | ✅ ON | ✅ ON (2.5) |
| Doświadczony | ✅ ON | ✅ ON | ✅ ON | ✅ ON (2.0) |
| Scalping | ❌ OFF | ✅ ON | ❌ OFF | ✅ ON (1.5) |
| Trend Following | ✅ ON | ✅ ON | ✅ ON | ✅ ON (2.5) |
| Choppy Market | ✅ ON | ❌ OFF | ✅ ON | ✅ ON (2.0) |
| High Volatility | ✅ ON | ✅ ON | ❌ OFF | ✅ ON (2.0) |

---

## Checklist Przed Uruchomieniem

### 1. Konfiguracja

- [ ] Ustaw `symbol` na właściwy instrument
- [ ] Wybierz `timeframe` (M15 zalecane)
- [ ] Ustaw `risk_percent` (0.5-1.0% dla początkujących)
- [ ] Skonfiguruj filtry według doświadczenia

### 2. Telegram (opcjonalnie)

- [ ] Utwórz bota przez @BotFather
- [ ] Pobierz Chat ID z @userinfobot
- [ ] Wypełnij `bot_token` i `chat_id`
- [ ] Ustaw `enabled: true`

### 3. Testing

- [ ] Uruchom backtest: `python src/main_bms.py --backtest`
- [ ] Sprawdź logi w `logs/` directory
- [ ] Uruchom demo: `python src/main_bms.py --demo`
- [ ] Testuj minimum 48h na demo

### 4. Going Live

- [ ] Przetestuj na demo min. 1 tydzień
- [ ] Zweryfikuj positive expectancy
- [ ] Sprawdź drawdown < 10%
- [ ] Uruchom z małym ryzykiem (0.25%)

---

## Ostrzeżenia

⚠️ **ZAWSZE testuj na demo przed live!**

⚠️ **MetaTrader5 działa tylko na Windows!**

⚠️ **Nigdy nie inwestuj więcej niż możesz stracić!**

⚠️ **Past performance does not guarantee future results!**

---

## Changelog

### v1.1 (2025-03-16)
- **POPRAWIONA LOGIKA:** Fibonacci obliczany po potwierdzeniu extremum
- Nowy stan maszyny: `TRACKING_EXTREMUM`, `EXTREMUM_CONFIRMED`
- Timeout protection dla tracking
- Pełna dokumentacja wszystkich komponentów
- Enhanced Telegram notifications

### v1.0 (2025-03-16)
- Initial implementation
- All PDF specification features
- 4 filters (Trend, Volume, Volatility, R:R)
- 3 TP levels
- Telegram integration
- Backtest and Demo modes

---

## License

MIT License - Use at your own risk!
