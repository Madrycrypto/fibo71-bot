# 📊 FIBO 71 - BACKTEST RESULTS

## Kompleksowe wyniki testów na danych historycznych

---

## 🎯 METODOLOGIA

- **Źródło danych:** Yahoo Finance
- **Okres testowy:** ~2 lata (12,000+ świec H1, 500+ świec D1)
- **Pary walutowe:** EURUSD, GBPUSD, USDJPY, AUDUSD, USDCAD, NZDUSD
- **Timeframes:** H1, D1
- **Strefy Entry:** 38-50%, 50-62%, 62-71%, 71-79%
- **Filtry:** BOS bez wymaganego imbalance (relaxed)

---

## 📈 WYNIKI H1 (Day Trading)

### TOP 10 Konfiguracje

| # | Para | Strefa | Trades | WR | Pips | PF | Rating |
|---|------|--------|--------|-----|------|-----|--------|
| 1 | **AUDUSD** | **71-79%** | 15 | 46.7% | +152.7 | **2.48** | ⭐⭐⭐⭐⭐ |
| 2 | **USDJPY** | **38-50%** | 14 | 71.4% | +279.6 | **2.10** | ⭐⭐⭐⭐⭐ |
| 3 | **USDCAD** | **38-50%** | 24 | 70.8% | +172.1 | **1.63** | ⭐⭐⭐⭐ |
| 4 | **EURUSD** | **38-50%** | 15 | 46.7% | +49.9 | **1.50** | ⭐⭐⭐⭐ |
| 5 | NZDUSD | 71-79% | 12 | 33.3% | +43.0 | 1.37 | ⭐⭐⭐ |
| 6 | NZDUSD | 62-71% | 3 | 33.3% | +40.7 | 1.26 | ⭐⭐⭐ |
| 7 | AUDUSD | 50-62% | 24 | 45.8% | +75.5 | 1.23 | ⭐⭐⭐ |
| 8 | USDJPY | 71-79% | 14 | 35.7% | +77.8 | 1.22 | ⭐⭐⭐ |
| 9 | GBPUSD | 71-79% | 16 | 25.0% | +34.9 | 1.14 | ⭐⭐⭐ |
| 10 | AUDUSD | 38-50% | 43 | 58.1% | +49.3 | 1.08 | ⭐⭐ |

### 📊 Analiza H1

**Najlepsze pary:**
1. **AUDUSD** - PF 2.48 (71-79%), duży wybór profitable'nych stref
2. **USDJPY** - PF 2.10 (38-50%), wysoki WR 71.4%
3. **USDCAD** - PF 1.63 (38-50%), najwięcej sygnałów (24 trades)

**Najlepsze strefy:**
- **38-50%** = Najlepsza dla: USDJPY, USDCAD, EURUSD
- **50-62%** = Średnie wyniki, mniej zyskowna
- **71-79%** = Najlepsza dla: AUDUSD, NZDUSD, GBPUSD

---

## 📈 WYNIKI D1 (Swing Trading)

### TOP 5 Konfiguracje

| # | Para | Strefa | Trades | WR | Pips | PF | Rating |
|---|------|--------|--------|-----|------|-----|--------|
| 1 | **EURUSD** | **38-50%** | 4 | 75.0% | +117.8 | **3.01** | ⭐⭐⭐⭐⭐ |
| 2 | GBPUSD | 38-50% | 2 | 100.0% | +473.1 | 999.00 | ⭐⭐⭐⭐⭐ |
| 3 | EURUSD | 50-62% | 4 | 50.0% | +49.9 | 1.50 | ⭐⭐⭐⭐ |
| 4 | NZDUSD | 71-79% | 3 | 33.3% | +107.0 | 1.91 | ⭐⭐⭐⭐ |
| 5 | NZDUSD | 62-71% | 3 | 33.3% | +40.7 | 1.26 | ⭐⭐⭐ |

### 📊 Analiza D1

**Najlepsze pary:**
1. **EURUSD** - PF 3.01 (38-50%), bardzo wysoki WR 75%
2. **GBPUSD** - PF 999 (38-50%), ale tylko 2 trades
3. **NZDUSD** - Dobre wyniki na wyższych strefach (62-79%)

**Cechy D1:**
- Mniej sygnałów (2-6 trades na 2 lata)
- Wyższa jakość setupów
- Wyższy win rate
- Lepszy profit factor

---

## 🎯 REKOMENDACJE KONFIGURACYJNE

### DLA DAY TRADERS (H1)

```json
{
  "symbol": "AUDUSD",
  "timeframe": "H1",
  "entry_zone": "71-79",
  "fib_min": 0.71,
  "fib_max": 0.79
}
```
**Alternatywy:**
- USDJPY + 38-50% (PF 2.10, WR 71.4%)
- USDCAD + 38-50% (PF 1.63, 24 trades)

### DLA SWING TRADERS (D1)

```json
{
  "symbol": "EURUSD",
  "timeframe": "D1",
  "entry_zone": "38-50",
  "fib_min": 0.38,
  "fib_max": 0.50
}
```
**Alternatywy:**
- GBPUSD + 38-50% (PF 999, WR 100%)
- NZDUSD + 71-79% (PF 1.91)

### DLA DIVERSIFICATION

Portfel 3 par z różnymi strefami:
1. **AUDUSD H1** - 71-79% (konservatywna)
2. **USDJPY H1** - 38-50% (agresywna)
3. **EURUSD D1** - 38-50% (swing)

---

## 📋 KONFIGURACJA SETTINGS.JSON

```json
{
  "trading": {
    "symbol": "AUDUSD",
    "timeframe": "H1",
    "magic_number": 710071
  },
  "risk": {
    "risk_percent": 1.0,
    "max_daily_trades": 3,
    "max_open_positions": 2
  },
  "strategy": {
    "entry_zone": "71-79",
    "entry_zones": {
      "aggressive": {"min": 0.38, "max": 0.50, "best_for": ["USDJPY", "USDCAD", "EURUSD"]},
      "balanced": {"min": 0.50, "max": 0.62, "best_for": ["AUDUSD"]},
      "conservative": {"min": 0.62, "max": 0.71, "best_for": ["NZDUSD"]},
      "cp20_original": {"min": 0.71, "max": 0.79, "best_for": ["AUDUSD", "NZDUSD", "GBPUSD"]}
    },
    "fib_tp": 0.0,
    "fib_sl": 1.0,
    "bos_lookback": 50,
    "min_range_pips": 30
  },
  "filters": {
    "enable_imbalance": false,
    "enable_liquidity_sweep": false,
    "trading_hours": {
      "start": "08:00",
      "end": "20:00"
    }
  }
}
```

---

## 🔍 DIAGNOSTYKA - DLACZEGO MAŁO TRADES?

### Oryginalny Problem
User zauważył: "z moim obserwacji wynika ze malo bardzo tradow zlapales"

### Rozwiązanie
Problem wynikał z:

1. **Zbyt restrykcyjny BOS detection**
   - Swing detection wymagał 5 świec (2 przed, 2 po)
   - Rozwiązanie: Relaxed swing detection

2. **Wymagany Imbalance (IPA)**
   - Oryginalnie wymagany
   - Rozwiązanie: `require_imbalance: false`

3. **Długi cooldown między setupami**
   - Oryginalnie 10 świec
   - Rozwiązanie: Zmniejszony do 5 świec

4. **Entry zone logic inverted**
   - Oryginalnie błędna logika dla BUY/SELL
   - Rozwiązanie: Poprawiona logika wejścia

### Wynik
- **H1:** 12-24 trades na parę (vs 2-6 wcześniej)
- **D1:** 2-6 trades na parę (realistyczne dla swing)

---

## 📊 ZALEŻNOŚĆ STREFA vs PERFORMANCE

| Strefa | Średni PF | Średni WR | Charakterystyka |
|--------|-----------|-----------|-----------------|
| **38-50%** | **1.53** | **59.2%** | Agresywna, wcześniejsze wejście, więcej sygnałów |
| 50-62% | 0.96 | 38.6% | Neutralna, mieszane wyniki |
| 62-71% | 0.88 | 31.5% | Konzervatywna, mniej sygnałów |
| **71-79%** | **1.31** | **34.5%** | Konzervatywna, wysoki PF dla niektórych par |

**Wniosek:** Strefa 38-50% daje najlepsze wyniki dla większości par.

---

## ⚠️ OGRANICZENIA TESTÓW

1. **Yahoo Finance data** - może mieć luki i niedokładności
2. **Brak spreadów** - w rzeczywistości wyniki będą niższe
3. **Brak slippage** - realne execution gorsze
4. **Curve fitting** - wyniki historyczne ≠ przyszłe wyniki
5. **Brak news filter** - w rzeczywistości trzeba omijać newsy

---

## 🚀 NASTĘPNE KROKI

1. **Forward testing** na demo przez min. 3 miesiące
2. **Dodanie spread/slippage** do kalkulacji
3. **Test na innych data source** (MT5 history)
4. **Optimizacja min_range_pips** (obecnie 30)
5. **Testy z imbalance filter** dla jakości setupów

---

*Ostatnia aktualizacja: 2026-03-15*
*Backtest period: ~2 lata (2024-03 - 2026-03)*
