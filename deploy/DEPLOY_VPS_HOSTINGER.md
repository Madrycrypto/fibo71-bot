# 🚀 DEPLOY FIBO 71 NA VPS HOSTINGER

## Kompletny przewodnik instalacji MT5 + Telegram Bot

---

## 📋 WYMAGANIA

- **VPS:** Hostinger VPS (min. 2GB RAM, 2 vCPU)
- **System:** Windows Server 2019/2022 lub Ubuntu 20.04+
- **Broker:** MT5 z dostępem do API
- **Telegram:** Bot Token + Chat ID (grupa)

---

## 🖥️ OPCJA 1: Windows VPS (ZALECANA)

### Krok 1: Połączenie RDP

```bash
# Na Mac/Linux użyj Microsoft Remote Desktop
# Na Windows: mstsc

# Adres: Twój_VPS_IP
# User: Administrator
# Password: (z Hostinger panel)
```

### Krok 2: Instalacja MT5

1. Pobierz MT5 z broker website
2. Zainstaluj w: `C:\Program Files\MetaTrader 5\`
3. Zaloguj do konta trading
4. Włącz Auto Trading (Ctrl+E)
5. Tools → Options → Expert Advisors:
   - ✅ Allow automated trading
   - ✅ Allow DLL imports
   - ✅ Allow WebRequest (dodaj: `api.telegram.org`)

### Krok 3: Konfiguracja Telegram

#### 3.1 Stwórz Bot
1. Otwórz @BotFather na Telegram
2. Wyślij `/newbot`
3. Nazwa: `Fibo71_Signals`
4. Username: `fibo71_signals_bot`
5. **Zapisz Token:** `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`

#### 3.2 Stwórz Grupę
1. Stwórz nową grupę na Telegram
2. Dodaj bota do grupy
3. Ustaw bota jako admin
4. **Zapisz Chat ID:** (użyj @userinfobot w grupie)

#### 3.3 Pobierz Chat ID Grupy
```
1. Dodaj @RawDataBot do grupy
2. Wyślij dowolną wiadomość
3. Bot odpowie z Chat ID (np. -1001234567890)
4. Usuń @RawDataBot z grupy
```

### Krok 4: Instalacja Fibo 71 EA

```powershell
# Na VPS - PowerShell

# Stwórz folder projektu
mkdir C:\Trading\Fibo71
cd C:\Trading\Fibo71

# Pobierz pliki
# Opcja A: Git
git clone https://github.com/Madrycrypto/trading-webhook-stack.git Fibo71

# Opcja B: Download ZIP z GitHub
```

### Krok 5: Konfiguracja EA

Edytuj plik konfiguracyjny:
```json
// C:\Trading\Fibo71\config\settings.json
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
    "fib_min": 0.71,
    "fib_max": 0.79,
    "bos_lookback": 50,
    "min_range_pips": 30
  },
  "telegram": {
    "enabled": true,
    "bot_token": "123456789:ABCdefGHIjklMNOpqrsTUVwxyz",
    "chat_id": "-1001234567890"
  }
}
```

### Krok 6: Kompilacja EA

1. Otwórz MetaEditor (F4 w MT5)
2. File → Open Data Folder
3. Przejdź do: `MQL5/Experts/`
4. Skopiuj `Fibo71_CP2_Bot.mq5`
5. Kompiluj (F7) - 0 errors
6. Restart MT5

### Krok 7: Uruchomienie EA

1. W MT5 otwórz wykres AUDUSD H1
2. Przeciągnij EA na wykres
3. Włącz parametry:
   - Symbol: AUDUSD
   - Timeframe: H1
   - TelegramEnabled: true
   - BotToken: (Twój token)
   - ChatID: (Chat ID grupy)
4. OK → Auto Trading (Ctrl+E)

### Krok 8: Weryfikacja

```
✅ MT5 działa
✅ EA załadowany na wykresie
✅ Auto Trading włączony (zielony trójkąt)
✅ Telegram wiadomość: "🚀 Fibo 71 Bot Started"
```

---

## 🐧 OPCJA 2: Ubuntu VPS + Wine (Python Bot)

### Krok 1: Połączenie SSH

```bash
ssh root@TWÓJ_VPS_IP
# Password: (z Hostinger panel)
```

### Krok 2: Instalacja zależności

```bash
# Update system
apt update && apt upgrade -y

# Install Python 3.11
apt install python3.11 python3.11-venv python3-pip -y

# Install dependencies
apt install git curl wget -y
```

### Krok 3: Klonowanie projektu

```bash
cd /opt
git clone https://github.com/Madrycrypto/trading-webhook-stack.git fibo71
cd fibo71/Fibo_71

# Virtual environment
python3.11 -m venv venv
source venv/bin/activate

# Install requirements
pip install -r requirements.txt
```

### Krok 4: Konfiguracja

```bash
# Kopiuj przykładową konfigurację
cp config/settings.example.json config/settings.json

# Edytuj ustawienia
nano config/settings.json
```

Wpisz swoje dane Telegram:
```json
{
  "telegram": {
    "enabled": true,
    "bot_token": "123456789:ABCdefGHIjklMNOpqrsTUVwxyz",
    "chat_id": "-1001234567890"
  }
}
```

### Krok 5: Test połączenia Telegram

```bash
source venv/bin/activate
python -c "
from src.utils.telegram import TelegramNotifier
import asyncio

async def test():
    tg = TelegramNotifier('YOUR_BOT_TOKEN', 'YOUR_CHAT_ID')
    await tg.send_message('🧪 Test Fibo 71 Bot')

asyncio.run(test())
"
```

### Krok 6: Uruchomienie jako serwis

```bash
# Stwórz systemd service
cat > /etc/systemd/system/fibo71.service << 'EOF'
[Unit]
Description=Fibo 71 Trading Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/fibo71/Fibo_71
ExecStart=/opt/fibo71/Fibo_71/venv/bin/python src/main.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable i start
systemctl daemon-reload
systemctl enable fibo71
systemctl start fibo71

# Sprawdź status
systemctl status fibo71
```

### Krok 7: Logi

```bash
# Live logi
journalctl -u fibo71 -f

# Ostatnie 100 linii
journalctl -u fibo71 -n 100
```

---

## 📱 TELEGRAM KOMENDY

Po uruchomieniu bota, wyślij na grupę:

| Komenda | Opis |
|---------|------|
| `/start` | Start bota |
| `/status` | Aktualny stan |
| `/stats` | Statystyki dzisiejsze |
| `/help` | Pomoc |

---

## 🔧 MONITORING

### Health Check Script

```bash
#!/bin/bash
# /opt/fibo71/health_check.sh

if ! systemctl is-active --quiet fibo71; then
    echo "Fibo 71 is DOWN! Restarting..."
    systemctl restart fibo71
    # Send Telegram alert
    curl -s "https://api.telegram.org/botYOUR_BOT_TOKEN/sendMessage" \
         -d chat_id="YOUR_CHAT_ID" \
         -d text="⚠️ Fibo 71 restarted on VPS"
fi
```

### Cron (co 5 minut)

```bash
crontab -e
# Dodaj:
*/5 * * * * /opt/fibo71/health_check.sh
```

---

## 🛡️ BEZPIECZEŃSTWO

### Firewall (UFW)

```bash
# Ubuntu
ufw allow ssh
ufw allow 3389/tcp  # RDP (jeśli Windows VM)
ufw enable
```

### Zmiana portu SSH

```bash
nano /etc/ssh/sshd_config
# Port 22 → Port 2222

systemctl restart sshd
ufw allow 2222/tcp
```

### Backup konfiguracji

```bash
# Daily backup
0 2 * * * tar -czf /backup/fibo71_$(date +\%Y\%m\%d).tar.gz /opt/fibo71/Fibo_71/config/
```

---

## ❓ TROUBLESHOOTING

### Problem: EA nie łączy z Telegram

**Rozwiązanie:**
1. Sprawdź WebRequest URL w MT5
2. Tools → Options → Expert Advisors → WebRequest
3. Dodaj: `https://api.telegram.org`
4. Restart MT5

### Problem: Brak sygnałów

**Rozwiązanie:**
1. Sprawdź czy wykres jest otwarty (AUDUSD H1)
2. Sprawdź czy Auto Trading włączony (Ctrl+E)
3. Sprawdź logi MT5 (Journal tab)
4. Sprawdź czy EA ma "uśmiech" w prawym górnym rogu

### Problem: VPS się restartuje

**Rozwiązanie:**
1. Ustaw Auto-Login w Windows
2. Dodaj MT5 do Startup folder
3. Użyj Task Scheduler dla auto-start

---

## 📞 WSPARCIE

- **GitHub Issues:** https://github.com/Madrycrypto/trading-webhook-stack/issues
- **Dokumentacja:** `/docs/BACKTEST_RESULTS.md`

---

*Ostatnia aktualizacja: 2026-03-15*
