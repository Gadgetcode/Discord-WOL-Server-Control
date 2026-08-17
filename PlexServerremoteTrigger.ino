#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <UniversalTelegramBot.h>
#include <WakeOnLan.h>

// --- CONFIGURATION ---
const char* ssid = "Airtel_Stranger";
const char* password = "Admin@7412";
#define BOTtoken "8721721831:AAF1xhS2XA872mmfcwR_mDhYEllDT1yruGY"
#define CHAT_ID "1421081915"
const char* targetMAC = "1c:1b:0d:fb:01:14"; // Your Plex Server MAC
const int ledPin = 2;

WiFiClientSecure client;
UniversalTelegramBot bot(BOTtoken, client);
WiFiUDP udp;
WakeOnLan WOL(udp);

void setup() {
  client.setInsecure();
  Serial.begin(115200);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.println("\nWiFi Connected!");

  // This tells the ESP32 to trust the connection without checking the specific certificate
  client.setInsecure(); 
  
  WOL.calculateBroadcastAddress(WiFi.localIP(), WiFi.subnetMask());

  // Solid light when connected!
  digitalWrite(ledPin, HIGH); 
  Serial.println("\nConnected to WiFi!");
}

void loop() {
  // Serial.println("Checking for messages..."); // Add this line //for testing meaage received or not 
  int numNewMessages = bot.getUpdates(bot.last_message_received + 1);

  for (int i = 0; i < numNewMessages; i++) {
    // --- THIS IS THE DEBUG LINE ---
    Serial.print("Message received from ID: ");
    Serial.println(bot.messages[i].chat_id);
    // ------------------------------

    if (bot.messages[i].chat_id == CHAT_ID) {
      String text = bot.messages[i].text;
      
      if (text == "/wake") {
        WOL.sendMagicPacket(targetMAC);
        bot.sendMessage(CHAT_ID, "Plex Server Waking Up... 🚀", "");
      }
      
      if (text == "/status") {
        bot.sendMessage(CHAT_ID, "ESP32 is Online. Ready to wake Plex.", "");
      }
    }
  }
  delay(2000); // Wait 2 seconds before checking again
}
