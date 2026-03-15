#!/bin/bash
# Fibo 71 VPS - Quick Start Script
# Run this on the VPS to start the bot

set -e

# Colors
RED='\033[0m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
NC='\033[0m'

echo -e "${BLUE}========================================{NC}"
echo -e "${BLUE}  FIBO 71 - VPS DEPLOYMENT{NC}"
echo -e "${BLUE}========================================{NC}"
echo -e ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must to be run as root${NC}"
    exit 1
fi

# Configuration
BOT_DIR="/opt/fibo71/Fibo_71"
VENV_DIR="$BOT_DIR/venv"
CONFIG_FILE="$BOT_DIR/config/settings.json"
LOG_DIR="/var/log/fibo71"

# Create log directory
mkdir -p "$LOG_DIR"

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Config file not found: $CONFIG_FILE${NC}"
    echo -e "${YELLOW}Creating default config...${NC}"

    cat > "$CONFIG_FILE" << 'EOF'
{
  "trading": {
    "symbol": "AUDUSD",
    "timeframe": "H1"
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
    "bot_token": "YOUR_BOT_TOKEN_HERE",
    "chat_id": "YOUR_CHAT_ID_HERE"
  }
}
EOF

    echo -e "${YELLOW}Please edit $CONFIG_FILE with your Telegram credentials${NC}"
    exit 1
fi

# Check Python
if ! command -v python3.11 &> /dev/null; then
    echo -e "${RED}Python 3.11 not found. Installing...${NC}"
    apt update && apt install -y python3.11 python3.11-venv python3-pip
fi

# Create virtual environment if needed
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${BLUE}Creating virtual environment...${NC}"
    cd "$BOT_DIR"
    python3.11 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
fi

# Activate venv
source "$VENV_DIR/bin/activate"

# Check if bot is already running
if systemctl is-active --quiet fibo71; then
    echo -e "${YELLOW}Bot is already running. Stopping...${NC}"
    systemctl stop fibo71
    sleep 2
fi

# Start bot
echo -e "${GREEN}Starting Fibo 71 Bot...${NC}"
cd "$BOT_DIR"

# Start in background
nohup python src/main.py >> "$LOG_DIR/bot.log" 2>&1 &

echo -e "${GREEN}Bot started! Logs: $LOG_DIR/bot.log${NC}"
echo -e ""
echo -e "${BLUE}========================================{NC}"
echo -e "${BLUE}  COMMANDS:${NC}"
echo -e "${BLUE}========================================{NC}"
echo -e "  View logs:     tail -f $LOG_DIR/bot.log"
echo -e "  Stop bot:     systemctl stop fibo71"
echo -e "  Status:      systemctl status fibo71"
echo -e "  Restart:     systemctl restart fibo71"
echo -e ""
