#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <UniversalTelegramBot.h>
#include <ArduinoJson.h>
#include <WiFiUdp.h>
#include <WakeOnLan.h>

// --- Config ---
const char* ssid = "Airtel_Game Of Thrones";
const char* password = "19@Breakingbad99";
#define BOTtoken "8721721831:AAF1xhS2XA872mmfcwR_mDhYEllDT1yruGY"
#define CHAT_ID "1421081915"
#define MAC_ADDR "1c:1b:0d:fb:01:14" // Server MAC

const unsigned long REBOOT_INTERVAL = 6 * 60 * 60 * 1000; // 6 Hours

// --- Objects ---
WiFiClientSecure client;
UniversalTelegramBot bot(BOTtoken, client);
WiFiUDP udp;
WakeOnLan wol(udp);

// --- 6-Hour Reboot Task (Core 1) ---
void rebootTask(void * pvParameters) {
  unsigned long startTime = millis();
  for(;;) {
    if (millis() - startTime >= REBOOT_INTERVAL) {
      ESP.restart(); 
    }
    vTaskDelay(60000 / portTICK_PERIOD_MS); // Check once a minute
  }
}

void handleMessages(int numNewMessages) {
  for (int i = 0; i < numNewMessages; i++) {
    if (String(bot.messages[i].chat_id) != CHAT_ID) continue;

    String text = bot.messages[i].text;
    if (text == "/wake") {
      wol.sendMagicPacket(MAC_ADDR);
      bot.sendMessage(CHAT_ID, "Server wake signal sent! 🚀", "");
    }
    if (text == "/status") {
      bot.sendMessage(CHAT_ID, "ESP32 is Online. Uptime: " + String(millis()/60000) + " mins", "");
    }
  }
}

void setup() {
  Serial.begin(115200);
  WiFi.begin(ssid, password);
  WiFi.setSleep(false); // Disable WiFi sleep to prevent hangs
  client.setCACert(TELEGRAM_CERTIFICATE_ROOT);

  while (WiFi.status() != WL_CONNECTED) delay(500);
  
  wol.calculateBroadcastAddress(WiFi.localIP(), WiFi.subnetMask());
  bot.sendMessage(CHAT_ID, "System Online. Auto-reboot set for every 6hrs. ✅", "");

  // Start Reboot Timer on Core 1
  xTaskCreatePinnedToCore(rebootTask, "Reboot", 2048, NULL, 1, NULL, 1);
}

void loop() {
  int numNewMessages = bot.getUpdates(bot.last_message_received + 1);
  while (numNewMessages) {
    handleMessages(numNewMessages);
    numNewMessages = bot.getUpdates(bot.last_message_received + 1);
  }
  delay(1000);
}