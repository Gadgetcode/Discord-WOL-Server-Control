# Plex Server Discord Bot Setup v2.0

A full remote management system for a headless Plex media server using Discord,
ESP32 (Wake-on-LAN), and Python services.

---

## How It Works

```
You type !wake in Discord
        ↓
ESP32 polls Discord REST API (every 2 seconds)
        ↓
ESP32 sends Magic Packet over LAN
        ↓
PC wakes up → all 3 services auto-start
        ↓
plex_monitor.py watches Plex + CPU every 15 mins
        ↓
When idle → Discord alert sent via webhook
        ↓
You type !shutdown → PC shuts down gracefully
```

---

## Files Overview

| File | Purpose |
|---|---|
| `setup.sh` | Run once on fresh Ubuntu install — does everything |
| `discord_scripts/shutdown_bot.py` | Discord bot listens for `!shutdown` |
| `discord_scripts/shutdown_server.py` | Flask server triggers actual OS shutdown |
| `discord_scripts/plex_monitor.py` | Monitors Plex + CPU, sends idle alert |
| `plexServerVersion3_0.ino` | ESP32 Arduino code for WoL via Discord |

---

## Fresh Install — Step by Step

### Step 1 — Get your credentials ready

| Credential | How to get it |
|---|---|
| **Bot Token** | Discord Developer Portal → Your App → Bot → Reset Token |
| **User ID** | Discord Settings → Advanced → Developer Mode ON → Right click your name → Copy User ID |
| **Channel ID** | Right click your Discord channel → Copy Channel ID |
| **Webhook URL** | Channel → Edit Channel → Integrations → Webhooks → New Webhook → Copy URL |
| **Plex Token** | Plex Web → any media → ··· → Get Info → View XML → copy `X-Plex-Token=` value from URL |
| **MAC Address** | Run `ip link show` on server → look for ethernet adapter (enp2s0) → copy `link/ether` value |
| **Ethernet Adapter** | Run `ip link show` → find adapter that shows your MAC (usually `enp2s0` or `eth0`) |

---

### Step 2 — Edit setup.sh

Open `setup.sh` and fill in the values at the top:

```bash
USERNAME="plex-server"      # Run: whoami
ETH_ADAPTER="enp2s0"        # Run: ip link show  (find your ethernet adapter name)

BOT_TOKEN=""                # From Discord Developer Portal
ALLOWED_USER_ID=""          # Your Discord User ID (numbers only)
CHANNEL_ID=""               # Your Discord Channel ID (numbers only)
WEBHOOK_URL=""              # Your Discord Webhook URL
PLEX_TOKEN=""               # From Plex XML URL
MAC_ADDR=""                 # Server MAC e.g. 1c:1b:0d:fb:01:14
```

---

### Step 3 — Run setup.sh

```bash
sudo bash setup.sh
```

This automatically:
- ✅ Installs Python packages (discord.py, flask, requests, psutil)
- ✅ Installs ethtool
- ✅ Creates `/home/$USERNAME/discord_scripts/` with all 3 scripts
- ✅ Adds passwordless sudo for shutdown and ethtool
- ✅ Enables Wake-on-LAN on ethernet adapter
- ✅ Creates WoL systemd service (persists after reboot)
- ✅ Creates and starts all 3 Discord services

---

### Step 4 — Enable Wake on LAN in BIOS

1. Reboot into BIOS (press `Del` on Gigabyte boards during boot)
2. Go to **Peripherals** tab
3. Find **Wake on LAN** → set to **Enabled**
4. Make sure **ErP** is set to **Disabled** (Power Management tab)
5. Press `F10` to save and exit

---

### Step 5 — Flash ESP32

1. Open `plexServerVersion3_0.ino` in Arduino IDE
2. Edit credentials at the top:

```cpp
const char* ssid            = "YOUR_WIFI_NAME";
const char* password        = "YOUR_WIFI_PASSWORD";
const char* BOT_TOKEN       = "YOUR_BOT_TOKEN";
const char* CHANNEL_ID      = "YOUR_CHANNEL_ID";
const char* ALLOWED_USER_ID = "YOUR_USER_ID";   // Must match actual ID from Serial Monitor
const char* WEBHOOK_URL     = "YOUR_WEBHOOK_URL";
const char* MAC_ADDR        = "YOUR_SERVER_MAC"; // e.g. 1c:1b:0d:fb:01:14
```

3. Install required libraries in Arduino IDE (Tools → Manage Libraries):
   - `ArduinoJson` by Benoit Blanchon
   - `WakeOnLan`
4. Select board: `ESP32 Dev Module`
5. Flash to ESP32
6. Open Serial Monitor at `115200` baud to verify connection

> ⚠️ **Important:** The `ALLOWED_USER_ID` in the ESP32 code must be verified from Serial Monitor output, NOT from Discord UI. Send a message and check what ID is printed — use that exact value.

---

## Discord Commands

| Command | What it does |
|---|---|
| `!wake` | ESP32 sends magic packet → PC wakes up |
| `!shutdown` | PC shuts down after 3 second delay |
| `!status` | ESP32 replies with uptime |

---

## Checking Service Status

```bash
sudo systemctl status discord-shutdown-bot
sudo systemctl status discord-shutdown-server
sudo systemctl status discord-plex-monitor
sudo systemctl status wol
```

## Restarting Services

```bash
sudo systemctl restart discord-shutdown-bot discord-shutdown-server discord-plex-monitor
```

## Viewing Logs

```bash
journalctl -u discord-shutdown-bot -n 50 --no-pager
journalctl -u discord-shutdown-server -n 50 --no-pager
journalctl -u discord-plex-monitor -n 50 --no-pager
```

## Verifying WoL is Enabled

```bash
sudo ethtool enp2s0 | grep Wake
# Should show: Wake-on: g
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Services fail with `status=2` | Run `sudo pip3 install discord.py flask requests psutil --break-system-packages` |
| Permission denied on scripts | Run `sudo chown -R $USER:$USER ~/discord_scripts` |
| `!shutdown` returns 500 | Add to sudoers: `username ALL=(ALL) NOPASSWD: /usr/sbin/shutdown` |
| `!shutdown` replies before shutdown | Already fixed — 3 second delay built into shutdown_server.py |
| `!status` not responding | ALLOWED_USER_ID is wrong — check Serial Monitor for your real ID |
| Bot not seeing messages | Enable Message Content Intent in Discord Developer Portal → Bot → Privileged Gateway Intents |
| `!wake` not working | Check BIOS WoL enabled, ErP disabled, and run `sudo ethtool enp2s0` to verify `Wake-on: g` |
| WoL resets after reboot | Check `sudo systemctl status wol` — should be active |
| ESP32 not connecting to Discord | Check Bot Token is correct and bot has View Channel + Read Message History permissions |

---

## Systemd Services Created

| Service | Script |
|---|---|
| `discord-shutdown-bot` | shutdown_bot.py |
| `discord-shutdown-server` | shutdown_server.py |
| `discord-plex-monitor` | plex_monitor.py |
| `wol` | ethtool WoL enable |

All services are enabled to auto-start on every boot.

---

## Network Layout

```
[Your Phone]
     ↓ Discord
[Discord Servers]
     ↓ REST API (polling every 2s)
[ESP32 - 24/7 on]  ←→  Same LAN  →  [Plex Server PC]
     ↓ Magic Packet via UDP broadcast
[Plex Server wakes up]
     ↓ Auto-starts services
[discord-shutdown-bot] [discord-shutdown-server] [discord-plex-monitor]
```
