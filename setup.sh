#!/bin/bash
# ============================================================
#   Plex Server Discord Bot - Full Setup Script v2.0
#   Run as: sudo bash setup.sh
# ============================================================

# ================================================================
#   EDIT THESE VALUES BEFORE RUNNING
# ================================================================
USERNAME="plex-server"                          # Linux username (run: whoami)
SCRIPT_DIR="/home/$USERNAME/discord_scripts"    # Where scripts will live
ETH_ADAPTER="enp2s0"                           # Ethernet adapter (run: ip link show)

BOT_TOKEN="YOUR_DISCORD_BOT_TOKEN"
ALLOWED_USER_ID="YOUR_DISCORD_USER_ID"
CHANNEL_ID="YOUR_DISCORD_CHANNEL_ID"
WEBHOOK_URL="YOUR_DISCORD_WEBHOOK_URL"
PLEX_TOKEN="YOUR_PLEX_TOKEN"
MAC_ADDR="YOUR_SERVER_MAC_ADDRESS"             # Format: xx:xx:xx:xx:xx:xx
# ================================================================

echo "========================================"
echo "   Plex Server Discord Bot Setup v2.0"
echo "========================================"

# Step 1: Install required packages
echo ""
echo "[1/7] Installing Python packages..."
sudo pip3 install discord.py flask requests psutil --break-system-packages
echo "      Done."

# Step 2: Install ethtool for WoL
echo ""
echo "[2/7] Installing ethtool..."
sudo apt install ethtool -y
echo "      Done."

# Step 3: Create scripts directory
echo ""
echo "[3/7] Creating scripts directory at $SCRIPT_DIR..."
mkdir -p $SCRIPT_DIR

# Step 4: Create Python scripts
echo ""
echo "[4/7] Creating Python scripts..."

# shutdown_bot.py
cat > $SCRIPT_DIR/shutdown_bot.py << PYEOF
import discord
import requests
import logging

logging.basicConfig(level=logging.INFO)

BOT_TOKEN = "$BOT_TOKEN"
ALLOWED_USER_ID = $ALLOWED_USER_ID
CHANNEL_ID = $CHANNEL_ID

intents = discord.Intents.default()
intents.message_content = True
client = discord.Client(intents=intents)

@client.event
async def on_ready():
    print(f"Bot logged in as {client.user}")

@client.event
async def on_message(message):
    if message.author == client.user:
        return
    if message.author.id != ALLOWED_USER_ID:
        return
    if message.channel.id != CHANNEL_ID:
        return
    if message.content.lower() == "!shutdown":
        await message.channel.send("Attempting to contact server...")
        try:
            response = requests.post("http://127.0.0.1:5050/shutdown", timeout=5)
            if response.status_code == 200:
                await message.channel.send("✅ Signal sent! Shutting down...")
            else:
                await message.channel.send(f"⚠️ Server returned status: {response.status_code}")
        except Exception as e:
            await message.channel.send(f"❌ Connection error: {str(e)}")

client.run(BOT_TOKEN)
PYEOF

# shutdown_server.py
cat > $SCRIPT_DIR/shutdown_server.py << PYEOF
import subprocess
import threading
from flask import Flask

app = Flask(__name__)

def do_shutdown():
    import time
    time.sleep(3)  # Delay so Discord receives reply before shutdown
    subprocess.run(['sudo', '/usr/sbin/shutdown', '-h', 'now'])

@app.route('/shutdown', methods=['GET', 'POST'])
def shutdown():
    try:
        t = threading.Thread(target=do_shutdown)
        t.daemon = True
        t.start()
        return "Server shutting down", 200
    except Exception as e:
        return str(e), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5050)
PYEOF

# plex_monitor.py
cat > $SCRIPT_DIR/plex_monitor.py << PYEOF
import requests
import psutil
import time

PLEX_URL = "http://localhost:32400/status/sessions?X-Plex-Token=$PLEX_TOKEN"
DISCORD_WEBHOOK_URL = "$WEBHOOK_URL"

def send_discord(message):
    try:
        requests.post(DISCORD_WEBHOOK_URL, json={"content": message})
    except Exception as e:
        print(f"Discord send failed: {e}")

def check_system():
    try:
        response = requests.get(PLEX_URL, timeout=5)
        is_plex_idle = 'size="0"' in response.text
        is_cpu_low = psutil.cpu_percent(interval=1) < 10
        if is_plex_idle and is_cpu_low:
            send_discord("⚠️ System is idle (No Plex activity & Low CPU). Type \`!shutdown\` to shut it down.")
    except Exception as e:
        print(f"Check failed: {e}")

print("Monitor started...")
while True:
    check_system()
    time.sleep(900)  # Check every 15 minutes
PYEOF

echo "      Scripts created."

# Step 5: Fix ownership and permissions
echo ""
echo "[5/7] Setting permissions..."
chown -R $USERNAME:$USERNAME $SCRIPT_DIR
echo "      Done."

# Step 6: Add sudoers rules
echo ""
echo "[6/7] Adding passwordless sudo rules..."
echo "$USERNAME ALL=(ALL) NOPASSWD: /usr/sbin/shutdown" >> /etc/sudoers
echo "$USERNAME ALL=(ALL) NOPASSWD: /usr/sbin/ethtool" >> /etc/sudoers
echo "      Done."

# Step 7: Enable Wake on LAN
echo ""
echo "[7/7] Setting up Wake on LAN..."

# Enable WoL now
ethtool -s $ETH_ADAPTER wol g

# Create WoL systemd service to persist after reboot
cat > /etc/systemd/system/wol.service << SVCEOF
[Unit]
Description=Enable Wake on LAN
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s $ETH_ADAPTER wol g

[Install]
WantedBy=multi-user.target
SVCEOF

# Create Discord bot service files
cat > /etc/systemd/system/discord-shutdown-bot.service << SVCEOF
[Unit]
Description=Discord Shutdown Bot
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 $SCRIPT_DIR/shutdown_bot.py
Restart=always
User=$USERNAME

[Install]
WantedBy=multi-user.target
SVCEOF

cat > /etc/systemd/system/discord-shutdown-server.service << SVCEOF
[Unit]
Description=Discord Shutdown Flask Server
After=network.target

[Service]
ExecStart=/usr/bin/python3 $SCRIPT_DIR/shutdown_server.py
Restart=always
User=$USERNAME

[Install]
WantedBy=multi-user.target
SVCEOF

cat > /etc/systemd/system/discord-plex-monitor.service << SVCEOF
[Unit]
Description=Discord Plex Idle Monitor
After=network-online.target plexmediaserver.service
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 $SCRIPT_DIR/plex_monitor.py
Restart=always
User=$USERNAME

[Install]
WantedBy=multi-user.target
SVCEOF

# Enable and start all services
systemctl daemon-reload
systemctl enable wol discord-shutdown-bot discord-shutdown-server discord-plex-monitor
systemctl start wol discord-shutdown-bot discord-shutdown-server discord-plex-monitor

echo "      Done."

echo ""
echo "========================================"
echo "   Setup Complete!"
echo "========================================"
echo ""
echo "Verifying WoL:"
ethtool $ETH_ADAPTER | grep Wake
echo ""
echo "Service status:"
systemctl is-active discord-shutdown-bot
systemctl is-active discord-shutdown-server
systemctl is-active discord-plex-monitor
echo ""
echo "Discord commands:"
echo "  !shutdown  → shuts down the server"
echo "  !wake      → (ESP32) sends WoL magic packet"
echo "  !status    → (ESP32) returns uptime"
echo ""
echo "Check logs with:"
echo "  journalctl -u discord-shutdown-bot -n 30 --no-pager"
