#include <Arduino.h>
#include <ESP32Servo.h>
#include "HX711.h"
#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <PubSubClient.h>
#include <Preferences.h>

// ================= WIFI & MQTT =================
const char* ssid = "Uhuk";
const char* password = "kam1234@";
const char* deviceName = "medicinebox";
const char* mqtt_server = "34.19.178.165"; 
const int mqtt_port = 1883;

// Dynamic boxId - stored in Preferences (EEPROM)
Preferences preferences;
String boxId = ""; // Will be loaded from Preferences or generated from MAC
String medicineBoxId = ""; // MedicineBox.id from database (set by app via HTTP) 

WiFiClient espClient;
PubSubClient mqtt(espClient);

// ================= PINS =================
const int PIN_SERVO = 47;        // Servo Signal (D47, GPIO 47) - RIGHT SIDE
const int PIN_BUTTON = 4;        // Button (D4, GPIO 4) - LEFT SIDE
const int PIN_HX711_DT = 48;     // HX711 DT (D48, GPIO 48) - RIGHT SIDE
const int PIN_HX711_SCK = 38;    // HX711 SCK (D38, GPIO 38) - RIGHT SIDE
const int PIN_BUZZER = 12;       // Buzzer (keep existing or update if needed)
const int PIN_LED = 21;          // External LED (D21, GPIO 21) - RIGHT SIDE

// Pill Box LEDs (Inner layer) - LEFT SIDE
const int PIN_BOX1_LED = 18;     // LED1 (D18, GPIO 18) - LEFT SIDE
const int PIN_BOX2_LED = 16;     // LED2 (D16, GPIO 16) - LEFT SIDE
const int PIN_BOX3_LED = 7;      // LED3 (D7, GPIO 7) - LEFT SIDE
const int PIN_BOX4_LED = 6;      // LED4 (D6, GPIO 6) - LEFT SIDE
const int PIN_BOX5_LED = 5;      // LED5 (D5, GPIO 5) - LEFT SIDE
const int PIN_BOX6_LED = 17;     // LED6 (D17, GPIO 17) - LEFT SIDE
const int PIN_BOX7_LED = 14;     // LED7 (D14, GPIO 14) - RIGHT SIDE

// Array to map box number (1-7) to LED pin
const int BOX_LEDS[] = {
  0,              // Index 0 unused (boxes start at 1)
  PIN_BOX1_LED,   // Box 1
  PIN_BOX2_LED,   // Box 2
  PIN_BOX3_LED,   // Box 3
  PIN_BOX4_LED,   // Box 4
  PIN_BOX5_LED,   // Box 5
  PIN_BOX6_LED,   // Box 6
  PIN_BOX7_LED,   // Box 7
};

// ================= OBJECTS & STATE =================
WebServer server(80);
Servo myServo;
HX711 scale;

bool isBoxOpen = false;
float weightAtStart = 0.0;
float lastWeightLoss = 0.0;
bool medicineTaken = false;
bool buzzerActive = false; 

// Servo angles (will be set during initialization)
int CLOSED_ANGLE = 0;
int OPEN_ANGLE = 90; 

// Reminder Logic
bool reminderActive = false;
unsigned long reminderStartTime = 0;
unsigned long lastReminderBuzz = 0;
const unsigned long REMINDER_WINDOW = 30UL * 60UL * 1000UL;
const unsigned long REMINDER_INTERVAL = 5UL * 60UL * 1000UL;
int activeBoxLED = 0; // Track which box LED is currently active (0 = none)

// Button Debounce Logic
static bool lastButtonState = HIGH;
static unsigned long lastDebounceTime = 0;
static bool buttonPressed = false;
const unsigned long debounceDelay = 50;
static unsigned long systemStartTime = 0;
const unsigned long STARTUP_IGNORE_DELAY = 3000; // Ignore button for first 3 seconds

// Track if box is being opened via button press (to always record medicine as taken)
bool boxOpenedViaButton = false;

// Track recent box actions for medicine record marking
unsigned long lastReminderTriggeredTime = 0;
int lastReminderTriggeredBoxNumber = 0;
unsigned long lastBoxLEDTurnedOnTime = 0;
int lastBoxLEDTurnedOnBoxNumber = 0;
const unsigned long RECENT_ACTION_WINDOW = 10 * 60 * 1000; // 10 minutes in milliseconds

// ================= MQTT FUNCTIONS =================
void connectMQTT() {
  while (!mqtt.connected()) {
    Serial.print("Connecting to MQTT...");
    if (boxId.length() == 0) {
      Serial.println("ERROR: boxId not initialized!");
      delay(2000);
      continue;
    }
    if (mqtt.connect(boxId.c_str())) {
      Serial.println("connected");
      Serial.print("MQTT Client ID: ");
      Serial.println(boxId);
    } else {
      Serial.print("failed rc=");
      Serial.print(mqtt.state());
      Serial.println(" retrying...");
      delay(2000);
    }
  }
}

// Get or generate boxId from MAC address
String getOrCreateBoxId() {
  preferences.begin("medicinebox", false);
  String savedBoxId = preferences.getString("boxId", "");
  preferences.end();
  
  if (savedBoxId.length() > 0) {
    Serial.print("📦 Loaded boxId from storage: ");
    Serial.println(savedBoxId);
    return savedBoxId;
  }
  
  // Generate boxId from MAC address (last 6 bytes as hex string)
  String mac = WiFi.macAddress();
  mac.replace(":", "");
  String newBoxId = mac.substring(6); // Use last 6 hex chars (12 chars total)
  
  // Save to Preferences
  preferences.begin("medicinebox", false);
  preferences.putString("boxId", newBoxId);
  preferences.end();
  
  Serial.print("📦 Generated new boxId from MAC: ");
  Serial.println(newBoxId);
  return newBoxId;
}

// Get compartment name from active box LED (1-7 -> box1-box7)
String getCompartmentName() {
  if (activeBoxLED > 0 && activeBoxLED <= 7) {
    return "box" + String(activeBoxLED);
  }
  return "box1"; // Default
}

void publishStatusMQTT(float weight, bool taken, int boxNumber = 0) {
  if (!mqtt.connected()) return;
  
  // Use medicineBoxId from database if set, otherwise use ESP32 boxId
  String mqttBoxId = medicineBoxId.length() > 0 ? medicineBoxId : boxId;
  if (mqttBoxId.length() == 0) {
    Serial.println("⚠️ No boxId available for MQTT publish");
    return;
  }
  
  // Determine compartment number
  // Priority: 1) provided boxNumber, 2) activeBoxLED, 3) default to 1
  int compartmentNumber = 1; // Default
  if (boxNumber > 0) {
    compartmentNumber = boxNumber;
  } else if (activeBoxLED > 0 && activeBoxLED <= 7) {
    compartmentNumber = activeBoxLED;
  }
  
  Serial.print("📦 Using compartment number: ");
  Serial.println(compartmentNumber);
  
  String compartment = "box" + String(compartmentNumber);
  
  String topic = "medicinebox/" + mqttBoxId + "/status";
  String payload = "{";
  payload += "\"medicineBoxId\":\"" + mqttBoxId + "\",";  // Database MedicineBox ID
  payload += "\"boxNumber\":" + String(compartmentNumber) + ",";  // Which compartment (1-7)
  payload += "\"compartment\":\"" + compartment + "\",";  // Compartment name (box1-box7)
  payload += "\"weight\":" + String(weight, 2) + ",";
  payload += "\"taken\":" + String(taken ? "true" : "false") + ",";  // Is medicine taken?
  payload += "\"timestamp\":" + String(millis());  // Timestamp for ordering
  payload += "}";
  mqtt.publish(topic.c_str(), payload.c_str());
  Serial.println("📤 MQTT published: " + payload);
}

// ================= ACTION LOGIC (Shared by App & Button) =================
void openBox() {
  if (isBoxOpen) return;
  Serial.println("--- Opening Sequence Start ---");
  myServo.write(OPEN_ANGLE);
  isBoxOpen = true;
  digitalWrite(PIN_LED, HIGH);
  delay(1000);
  
  weightAtStart = scale.get_units(15);
  Serial.print("Initial Weight Captured: ");
  Serial.println(weightAtStart);
}

void closeBox(int overrideBoxNumber = 0) {
  if (!isBoxOpen) return;
  Serial.println("--- Closing Sequence Start ---");
  
  // IMPORTANT: Capture activeBoxLED FIRST, before any operations that might reset it
  int capturedBoxLED = activeBoxLED;
  
  // If override is provided (from app open/close), use it
  if (overrideBoxNumber > 0) {
    capturedBoxLED = overrideBoxNumber;
    Serial.print("📦 Using override boxNumber: ");
    Serial.println(overrideBoxNumber);
  }
  
  Serial.print("📦 activeBoxLED at start of closeBox: ");
  Serial.println(activeBoxLED);
  Serial.print("📦 Captured box LED for MQTT: ");
  Serial.println(capturedBoxLED);
  
  // If activeBoxLED is 0 but reminder is active, try to recover from reminder state
  if (capturedBoxLED == 0 && reminderActive) {
    // Check which box LED is actually on
    for (int i = 1; i <= 7; i++) {
      if (digitalRead(BOX_LEDS[i]) == HIGH) {
        capturedBoxLED = i;
        activeBoxLED = i; // Restore it
        Serial.print("📦 Recovered activeBoxLED from LED state: ");
        Serial.println(capturedBoxLED);
        break;
      }
    }
  }
  
  float weightAtEnd = scale.get_units(15);
  Serial.print("Final Weight Captured: ");
  Serial.println(weightAtEnd);

  lastWeightLoss = weightAtStart - weightAtEnd;
  Serial.print("Calculated Weight Loss: ");
  Serial.println(lastWeightLoss);

  medicineTaken = (lastWeightLoss > 3.0);
  Serial.print("Medicine Taken: ");
  Serial.println(medicineTaken ? "YES" : "NO");

  myServo.write(CLOSED_ANGLE);
  isBoxOpen = false;
  
  // If medicine was taken, turn off reminder LEDs
  // BUT preserve activeBoxLED until after MQTT publish
  if (medicineTaken) {
    reminderActive = false;
    digitalWrite(PIN_LED, LOW);
    // Turn off LEDs visually but don't reset activeBoxLED yet
    for (int i = 1; i <= 7; i++) {
      digitalWrite(BOX_LEDS[i], LOW);
    }
    // Keep activeBoxLED for MQTT publish
  } else {
    digitalWrite(PIN_LED, LOW);
  }
  
  // Publish MQTT status with captured box number
  Serial.print("📦 Publishing MQTT with box number: ");
  Serial.println(capturedBoxLED);
  Serial.print("💾 Publishing status - medicineBoxId: ");
  Serial.print(medicineBoxId);
  Serial.print(" | boxNumber: ");
  Serial.print(capturedBoxLED);
  Serial.print(" | taken: ");
  Serial.println(medicineTaken ? "YES" : "NO");
  publishStatusMQTT(weightAtEnd, medicineTaken, capturedBoxLED);
  
  // Reset activeBoxLED AFTER MQTT publish
  if (medicineTaken) {
    activeBoxLED = 0;
    Serial.println("📦 activeBoxLED reset to 0 after MQTT publish");
  }
}

// ================= HTTP HANDLERS =================
void handleStatus() {
  String json = "{";
  json += "\"isBoxOpen\":" + String(isBoxOpen ? "true" : "false") + ",";
  json += "\"medicineTaken\":" + String(medicineTaken ? "true" : "false") + ",";
  json += "\"weightLoss\":" + String(lastWeightLoss) + ",";
  json += "\"boxId\":\"" + boxId + "\",";  // ESP32 boxId (from MAC)
  json += "\"medicineBoxId\":\"" + medicineBoxId + "\",";  // MedicineBox.id from database
  json += "\"activeBoxLED\":" + String(activeBoxLED);
  json += "}";
  server.send(200, "application/json", json);
}

// Handle setting medicineBox.id from app
void handleSetMedicineBoxId() {
  if (server.hasArg("id")) {
    medicineBoxId = server.arg("id");
    // Also save to Preferences for persistence
    preferences.begin("medicinebox", false);
    preferences.putString("medicineBoxId", medicineBoxId);
    preferences.end();
    Serial.print("📦 MedicineBox ID set to: ");
    Serial.println(medicineBoxId);
    server.send(200, "application/json", "{\"success\":true,\"medicineBoxId\":\"" + medicineBoxId + "\"}");
  } else {
    server.send(400, "application/json", "{\"error\":\"Missing id parameter\"}");
  }
}

void handleWiFiStatus() {
  String json = "{";
  json += "\"connected\":" + String(WiFi.status() == WL_CONNECTED ? "true" : "false") + ",";
  json += "\"ssid\":\"" + String(ssid) + "\",";
  json += "\"ipAddress\":\"" + WiFi.localIP().toString() + "\",";
  json += "\"rssi\":" + String(WiFi.RSSI()) + ",";
  json += "\"macAddress\":\"" + WiFi.macAddress() + "\"";
  json += "}";
  server.send(200, "application/json", json);
}

void handleOpenBox() {
  // Check if app specified which box is being opened
  int boxNumber = 0;
  if (server.hasArg("box")) {
    boxNumber = server.arg("box").toInt();
    if (boxNumber > 0 && boxNumber <= 7) {
      // Track this as a recent LED tap so closeBox knows which box to mark
      lastBoxLEDTurnedOnTime = millis();
      lastBoxLEDTurnedOnBoxNumber = boxNumber;
      Serial.print("📦 App opening box: ");
      Serial.print(boxNumber);
      Serial.print(" - tracked at ");
      Serial.println(lastBoxLEDTurnedOnTime);
    }
  }
  
  openBox();
  server.send(200, "application/json", "{\"success\":true,\"box\":" + String(boxNumber) + "}");
}

void handleCloseBox() {
  // Determine which box should be marked as taken based on recent actions
  unsigned long now = millis();
  int boxNumberForRecord = 1; // Default
  
  // Check if a reminder was triggered recently (within 10 minutes)
  if (now - lastReminderTriggeredTime < RECENT_ACTION_WINDOW) {
    boxNumberForRecord = lastReminderTriggeredBoxNumber;
    Serial.print("📦 Using recent reminder box: ");
    Serial.println(boxNumberForRecord);
  }
  // Check if a light bulb was tapped recently (within 10 minutes)
  else if (now - lastBoxLEDTurnedOnTime < RECENT_ACTION_WINDOW) {
    boxNumberForRecord = lastBoxLEDTurnedOnBoxNumber;
    Serial.print("📦 Using recent LED tap box: ");
    Serial.println(boxNumberForRecord);
  }
  // Otherwise use activeBoxLED or default
  else if (activeBoxLED > 0 && activeBoxLED <= 7) {
    boxNumberForRecord = activeBoxLED;
    Serial.print("📦 Using active box LED: ");
    Serial.println(boxNumberForRecord);
  }
  
  // Pass the determined box number to closeBox so MQTT publishes the correct value
  closeBox(boxNumberForRecord);
  
  // Return the actual status from closeBox
  String json = "{";
  json += "\"success\":true,";
  json += "\"medicineTaken\":" + String(medicineTaken ? "true" : "false") + ",";
  json += "\"weightLoss\":" + String(lastWeightLoss) + ",";
  json += "\"isBoxOpen\":" + String(isBoxOpen ? "true" : "false") + ",";
  json += "\"medicineBoxId\":\"" + medicineBoxId + "\",";
  json += "\"boxNumber\":" + String(boxNumberForRecord);
  json += "}";
  
  Serial.println("🌐 HTTP Response being sent:");
  Serial.println(json);
  
  server.send(200, "application/json", json);
}

// Trigger reminder for specific box
void triggerReminderForBox(int boxNumber) {
  if (boxNumber < 1 || boxNumber > 7) {
    Serial.println("❌ Invalid box number for reminder");
    return;
  }

  Serial.print("🔔 Reminder triggered for Box ");
  Serial.println(boxNumber);

  medicineTaken = false;
  reminderActive = true;
  reminderStartTime = millis();
  lastReminderBuzz = 0; // This forces the loop() to buzz immediately

  // Track this reminder trigger for medicine record marking
  lastReminderTriggeredTime = millis();
  lastReminderTriggeredBoxNumber = boxNumber;
  Serial.print("⏰ Reminder trigger recorded at: ");
  Serial.println(lastReminderTriggeredTime);

  // Set activeBoxLED BEFORE turning off LEDs
  activeBoxLED = boxNumber;
  Serial.print("📦 activeBoxLED set to: ");
  Serial.println(activeBoxLED);

  // Turn off all box LEDs first, then turn on only the specified box LED
  // Use manual loop instead of turnOffAllBoxLEDs() to preserve activeBoxLED
  for (int i = 1; i <= 7; i++) {
    digitalWrite(BOX_LEDS[i], LOW);
  }
  // Don't reset activeBoxLED here - we just set it above
  
  digitalWrite(BOX_LEDS[boxNumber], HIGH);
  digitalWrite(PIN_LED, HIGH); // Outside LED also turns on
  
  Serial.print("📦 activeBoxLED after LED setup: ");
  Serial.println(activeBoxLED);
  Serial.print("📦 Box LED pin state: ");
  Serial.println(digitalRead(BOX_LEDS[boxNumber]));
}

void handleReminder() {
  if (!server.hasArg("box")) {
    server.send(400, "application/json", "{\"error\":\"Missing box parameter\"}");
    return;
  }

  int boxNumber = server.arg("box").toInt();
  triggerReminderForBox(boxNumber);

  server.send(200, "application/json",
    "{\"success\":true,\"box\":" + String(boxNumber) + "}");
}
void handleStartAlarm() {
  Serial.println("Find My Device Active");
  buzzerActive = true; 
  server.send(200, "application/json", "{\"success\":true}");
}

void handleStopBuzzer() {
  Serial.println("Alarms Stopped");
  buzzerActive = false;
  // Don't set reminderActive = false here - keep it active so LED stays on
  // reminderActive = false; // REMOVED - keep reminder active to maintain LED
  noTone(PIN_BUZZER);
  // Keep LEDs on - don't turn them off here
  // digitalWrite(PIN_LED, LOW); // REMOVED - keep outside LED on
  // turnOffAllBoxLEDs(); // REMOVED - keep box LED on
  // activeBoxLED = 0; // REMOVED - keep active box LED state
  server.send(200, "application/json", "{\"success\":true}");
}

// Control LED for specific pill box (1-7)
void setBoxLED(int boxNumber, bool state) {
  if (boxNumber < 1 || boxNumber > 7) {
    Serial.print("Invalid box number: ");
    Serial.println(boxNumber);
    return;
  }
  
  int pin = BOX_LEDS[boxNumber];
  digitalWrite(pin, state ? HIGH : LOW);
  
  if (state) {
    activeBoxLED = boxNumber;
    // Track this LED turn-on for medicine record marking
    lastBoxLEDTurnedOnTime = millis();
    lastBoxLEDTurnedOnBoxNumber = boxNumber;
    Serial.print("💡 Box ");
    Serial.print(boxNumber);
    Serial.print(" LED ON - tracked at ");
    Serial.println(lastBoxLEDTurnedOnTime);
  } else {
    if (activeBoxLED == boxNumber) {
      activeBoxLED = 0;
    }
    Serial.print("Box ");
    Serial.print(boxNumber);
    Serial.println(" LED OFF");
  }
}

// Turn off all box LEDs
// Note: This function resets activeBoxLED to 0
// Use with caution - don't call this if you need to preserve activeBoxLED for MQTT
void turnOffAllBoxLEDs() {
  for (int i = 1; i <= 7; i++) {
    digitalWrite(BOX_LEDS[i], LOW);
  }
  // Only reset activeBoxLED if not in the middle of closing box
  // (closeBox() will handle resetting it after MQTT publish)
  if (!isBoxOpen) {
    activeBoxLED = 0;
  }
}

// Handle LED control endpoint
void handleLEDControl() {
  if (server.hasArg("box") && server.hasArg("state")) {
    int boxNumber = server.arg("box").toInt();
    String state = server.arg("state");
    
    bool ledState = (state == "on" || state == "1" || state == "true");
    
    // Check if this is for the external LED (GPIO 21)
    if (boxNumber == 0 || boxNumber == 21) {
      // Control external LED (GPIO 21) directly
      digitalWrite(PIN_LED, ledState ? HIGH : LOW);
      Serial.print("💡 External LED (GPIO 21) turned ");
      Serial.println(ledState ? "ON" : "OFF");
      String response = "{\"success\":true,\"ledPin\":21,\"state\":\"" + String(ledState ? "on" : "off") + "\"}";
      server.send(200, "application/json", response);
      return;
    }
    
    // Otherwise control box LED (1-7)
    setBoxLED(boxNumber, ledState);
    
    // Also turn on outside LED when any box LED is on
    if (ledState) {
      digitalWrite(PIN_LED, HIGH);
    } else {
      // Only turn off outside LED if no box LEDs are active
      bool anyBoxLEDOn = false;
      for (int i = 1; i <= 7; i++) {
        if (digitalRead(BOX_LEDS[i]) == HIGH) {
          anyBoxLEDOn = true;
          break;
        }
      }
      if (!anyBoxLEDOn) {
        digitalWrite(PIN_LED, LOW);
      }
    }
    
    server.send(200, "application/json", "{\"success\":true,\"box\":" + String(boxNumber) + ",\"state\":\"" + (ledState ? "on" : "off") + "\"}");
  } else {
    server.send(400, "application/json", "{\"error\":\"Missing box or state parameter\"}");
  }
}

// Blink LED for specific box (non-blocking, handled in loop)
bool blinkActive = false;
int blinkBoxNumber = 0;
int blinkCount = 0;
int blinkTimes = 5;
bool blinkState = false; // false = off, true = on
unsigned long blinkLastToggle = 0;
const unsigned long BLINK_ON_DURATION = 300;  // LED on for 300ms
const unsigned long BLINK_OFF_DURATION = 300; // LED off for 300ms

void startBlink(int boxNumber, int times = 5) {
  if (boxNumber < 1 || boxNumber > 7) {
    Serial.println("❌ Invalid box number for blink");
    return;
  }
  
  Serial.print("💡 Starting blink for Box ");
  Serial.print(boxNumber);
  Serial.print(" - ");
  Serial.print(times);
  Serial.println(" times");
  
  // IMPORTANT: Set activeBoxLED when starting blink
  activeBoxLED = boxNumber;
  Serial.print("📦 activeBoxLED set to: ");
  Serial.println(activeBoxLED);
  
  blinkActive = true;
  blinkBoxNumber = boxNumber;
  blinkCount = 0;
  blinkTimes = times;
  blinkState = true; // Start with LED on
  blinkLastToggle = millis();
  
  // Start first blink - turn on LED
  digitalWrite(BOX_LEDS[boxNumber], HIGH);
  digitalWrite(PIN_LED, HIGH); // Also blink outside LED
}

void stopBlink() {
  if (blinkActive) {
    Serial.println("💡 Stopping blink");
    digitalWrite(BOX_LEDS[blinkBoxNumber], LOW);
    blinkActive = false;
    blinkBoxNumber = 0;
    blinkCount = 0;
    blinkState = false;
    
    // Turn off outside LED only if no other box LEDs are on
    bool anyBoxLEDOn = false;
    for (int i = 1; i <= 7; i++) {
      if (digitalRead(BOX_LEDS[i]) == HIGH) {
        anyBoxLEDOn = true;
        break;
      }
    }
    if (!anyBoxLEDOn && !reminderActive) {
      digitalWrite(PIN_LED, LOW);
    }
  }
}

// Handle blink LED endpoint
void handleBlinkLED() {
  if (server.hasArg("box")) {
    int boxNumber = server.arg("box").toInt();
    int times = 2; // Default to 2 blinks
    if (server.hasArg("times")) {
      times = server.arg("times").toInt();
    }
    
    startBlink(boxNumber, times);
    server.send(200, "application/json", "{\"success\":true,\"box\":" + String(boxNumber) + ",\"times\":" + String(times) + "}");
  } else {
    server.send(400, "application/json", "{\"error\":\"Missing box parameter\"}");
  }
}

// ================= SETUP =================
void setup() {
  Serial.begin(115200);
  pinMode(PIN_LED, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  
  // Test button pin - read initial state
  int initialButtonState = digitalRead(PIN_BUTTON);
  Serial.print("🔘 Button pin (GPIO ");
  Serial.print(PIN_BUTTON);
  Serial.print(") initialized. Initial state: ");
  Serial.println(initialButtonState == HIGH ? "HIGH (not pressed)" : "LOW (pressed)");
  
  // Initialize all box LEDs
  pinMode(PIN_BOX1_LED, OUTPUT);
  pinMode(PIN_BOX2_LED, OUTPUT);
  pinMode(PIN_BOX3_LED, OUTPUT);
  pinMode(PIN_BOX4_LED, OUTPUT);
  pinMode(PIN_BOX5_LED, OUTPUT);
  pinMode(PIN_BOX6_LED, OUTPUT);
  pinMode(PIN_BOX7_LED, OUTPUT);
  
  // Turn off all LEDs initially
  turnOffAllBoxLEDs();
  digitalWrite(PIN_LED, LOW);

  // Initialize and load boxId (must be after WiFi is connected)
  // Will be called after WiFi connection

  // WiFi Connection with detailed status
  Serial.println("\n========================================");
  Serial.println("Starting WiFi Connection...");
  Serial.print("SSID: ");
  Serial.println(ssid);
  Serial.print("Connecting");
  
  WiFi.begin(ssid, password);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    attempts++;
    if (attempts > 40) { // 20 seconds timeout
      Serial.println("\n❌ WiFi Connection Failed!");
      Serial.println("Please check:");
      Serial.println("  1. SSID and password are correct");
      Serial.println("  2. WiFi router is powered on");
      Serial.println("  3. ESP32 is within range");
      Serial.println("Restarting in 5 seconds...");
      delay(5000);
      ESP.restart();
    }
  }
  
  Serial.println("\n✅ WiFi Connected Successfully!");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());
  Serial.print("Signal Strength (RSSI): ");
  Serial.print(WiFi.RSSI());
  Serial.println(" dBm");
  Serial.print("MAC Address: ");
  Serial.println(WiFi.macAddress());
  Serial.println("========================================\n");

  // Initialize and load boxId (after WiFi is connected)
  boxId = getOrCreateBoxId();
  Serial.print("📦 Device boxId (ESP32): ");
  Serial.println(boxId);
  
  // Load medicineBoxId from Preferences if exists
  preferences.begin("medicinebox", false);
  medicineBoxId = preferences.getString("medicineBoxId", "");
  preferences.end();
  if (medicineBoxId.length() > 0) {
    Serial.print("📦 MedicineBox ID (from database): ");
    Serial.println(medicineBoxId);
  } else {
    Serial.println("ℹ️ MedicineBox ID not set yet. App will set it via /setmedicineboxid endpoint");
  }

  MDNS.begin(deviceName);
  mqtt.setServer(mqtt_server, mqtt_port);

  server.on("/status", handleStatus);
  server.on("/wifistatus", handleWiFiStatus);
  server.on("/setmedicineboxid", handleSetMedicineBoxId);
  server.on("/open", handleOpenBox);
  server.on("/close", handleCloseBox);
  server.on("/startalarm", handleStartAlarm);
  server.on("/stopbuzzer", handleStopBuzzer);
  server.on("/led", handleLEDControl);
  server.on("/blink", handleBlinkLED);
  server.on("/reminder", handleReminder);
  server.on("/testbutton", []() {
    int buttonState = digitalRead(PIN_BUTTON);
    String json = "{";
    json += "\"buttonPin\":" + String(PIN_BUTTON) + ",";
    json += "\"state\":" + String(buttonState) + ",";
    json += "\"stateText\":\"" + String(buttonState == HIGH ? "HIGH (not pressed)" : "LOW (pressed)") + "\",";
    json += "\"buttonPressed\":" + String(buttonPressed ? "true" : "false");
    json += "}";
    server.send(200, "application/json", json);
  });

  server.begin();

  Serial.println("\n===== SERVO INITIALIZATION =====");
  myServo.attach(PIN_SERVO);
  Serial.print("📦 Servo attached to PIN: ");
  Serial.println(PIN_SERVO);
  
  delay(500);
  
  // Set servo angles directly
  CLOSED_ANGLE = 0;
  OPEN_ANGLE = 90;
  
  Serial.print("📦 CLOSED angle: ");
  Serial.println(CLOSED_ANGLE);
  Serial.print("📦 OPEN angle: ");
  Serial.println(OPEN_ANGLE);
  
  myServo.write(CLOSED_ANGLE);
  
  isBoxOpen = false;
  Serial.println("📦 isBoxOpen set to: false");
  Serial.println("===== SERVO INITIALIZATION COMPLETE =====\n");

  scale.begin(PIN_HX711_DT, PIN_HX711_SCK);
  scale.set_scale(414.0);
  scale.tare();
  Serial.println("System Ready.");
  
  // Record startup time to ignore button noise during initialization
  systemStartTime = millis();
  Serial.println("⏱️ Ignoring button input for 3 seconds to allow system stabilization...");
}

// ================= LOOP =================
void loop() {
  server.handleClient();
  
  // Monitor WiFi connection status
  static unsigned long lastWiFiCheck = 0;
  if (millis() - lastWiFiCheck > 30000) { // Check every 30 seconds
    lastWiFiCheck = millis();
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("⚠️ WiFi Disconnected! Attempting to reconnect...");
      WiFi.begin(ssid, password);
      int reconnectAttempts = 0;
      while (WiFi.status() != WL_CONNECTED && reconnectAttempts < 20) {
        delay(500);
        Serial.print(".");
        reconnectAttempts++;
      }
      if (WiFi.status() == WL_CONNECTED) {
        Serial.println("\n✅ WiFi Reconnected!");
        Serial.print("New IP Address: ");
        Serial.println(WiFi.localIP());
      } else {
        Serial.println("\n❌ WiFi Reconnection Failed!");
      }
    }
  }
  
  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();

  unsigned long now = millis();

  // 0. LED BLINK PATTERN (highest priority for visibility)
  if (blinkActive) {
    if (blinkState == false) {
      // LED is off, check if we should turn it on
      if (now - blinkLastToggle >= BLINK_OFF_DURATION) {
        blinkState = true;
        blinkLastToggle = now;
        digitalWrite(BOX_LEDS[blinkBoxNumber], HIGH);
        digitalWrite(PIN_LED, HIGH);
        Serial.print("💡 Blink ");
        Serial.print(blinkCount + 1);
        Serial.print("/");
        Serial.print(blinkTimes);
        Serial.println(" - ON");
      }
    } else {
      // LED is on, check if we should turn it off
      if (now - blinkLastToggle >= BLINK_ON_DURATION) {
        blinkState = false;
        blinkLastToggle = now;
        digitalWrite(BOX_LEDS[blinkBoxNumber], LOW);
        blinkCount++;
        
        Serial.print("💡 Blink ");
        Serial.print(blinkCount);
        Serial.print("/");
        Serial.print(blinkTimes);
        Serial.println(" - OFF");
        
        // Check if we've completed all blinks
        if (blinkCount >= blinkTimes) {
          stopBlink();
          Serial.println("💡 Blink sequence complete");
        } else {
          // Turn off outside LED between blinks
          bool anyOtherLEDOn = false;
          for (int i = 1; i <= 7; i++) {
            if (i != blinkBoxNumber && digitalRead(BOX_LEDS[i]) == HIGH) {
              anyOtherLEDOn = true;
              break;
            }
          }
          if (!anyOtherLEDOn && !reminderActive) {
            digitalWrite(PIN_LED, LOW);
          }
        }
      }
    }
  }
  // 1. FIND MY DEVICE PATTERN
  else if (buzzerActive) {
    static unsigned long lastToggle = 0;
    if (now - lastToggle >= 300) { 
      lastToggle = now;
      bool state = digitalRead(PIN_LED);
      digitalWrite(PIN_LED, !state);
      if (!state) tone(PIN_BUZZER, 500); 
      else noTone(PIN_BUZZER);
    }
  } 
  // 2. MEDICINE REMINDER
  else if (reminderActive && !medicineTaken) {
    // Keep LEDs on continuously (not just during buzzer beeps)
    digitalWrite(PIN_LED, HIGH);
    if (activeBoxLED > 0 && activeBoxLED <= 7) {
      digitalWrite(BOX_LEDS[activeBoxLED], HIGH);
    }
    
    // Only beep buzzer if not stopped by button
    if (lastReminderBuzz == 0 || now - lastReminderBuzz >= REMINDER_INTERVAL) {
      lastReminderBuzz = now;
      tone(PIN_BUZZER, 300);
      delay(1000); 
      noTone(PIN_BUZZER);
      // LEDs stay on (they'll be turned off when medicine is taken)
    }
  } 
  // 3. CLEANUP - Only turn off LEDs if no reminder is active and box is closed
  else if (!isBoxOpen && !reminderActive && !buzzerActive) {
    noTone(PIN_BUZZER);
    digitalWrite(PIN_LED, LOW);
    turnOffAllBoxLEDs();
  }

  // 4. BUTTON CONTROL
  int reading = digitalRead(PIN_BUTTON);
  
  // Ignore button input for first 3 seconds after startup
  static unsigned long lastStartupMessage = 0;
  static bool startupIgnoreDone = false;
  unsigned long timeSinceStartup = millis() - systemStartTime;
  if (timeSinceStartup < STARTUP_IGNORE_DELAY) {
    // During startup period, just update button state without processing
    if (timeSinceStartup - lastStartupMessage > 1000) {
      lastStartupMessage = timeSinceStartup;
      Serial.print("⏱️ Startup ignore: ");
      Serial.print((STARTUP_IGNORE_DELAY - timeSinceStartup) / 1000);
      Serial.println(" seconds remaining...");
    }
    lastButtonState = reading;
    lastDebounceTime = millis();
  } else {
    // Startup period is over - reset button state once
    if (!startupIgnoreDone) {
      startupIgnoreDone = true;
      buttonPressed = false;  // Reset button flag
      lastButtonState = reading;  // Sync with current state
      Serial.println("✅ Startup ignore complete - button monitoring active");
      Serial.print("🔘 Initial button state: ");
      Serial.println(reading == HIGH ? "HIGH (not pressed)" : "LOW (pressed)");
    }
    
    // Process button normally
    
    // Check if button state changed
    if (reading != lastButtonState) {
      lastDebounceTime = now;
      Serial.print("🔘 Button state changed to: ");
      Serial.println(reading == HIGH ? "HIGH" : "LOW");
    }
    
    // Only process button after debounce delay
    if ((now - lastDebounceTime) > debounceDelay) {
      // Button is pressed (LOW because of INPUT_PULLUP)
      if (reading == LOW && !buttonPressed) {
        buttonPressed = true;
        Serial.println("🔘 BUTTON PRESSED! ✓");
        
        if (buzzerActive) {
          Serial.println("   → Stopping find-my-device alarm");
          handleStopBuzzer();
        } else if (reminderActive) {
          Serial.println("   → Button pressed during reminder - stopping buzzer, keeping LED on");
          Serial.print("📦 Current activeBoxLED: ");
          Serial.println(activeBoxLED);
          noTone(PIN_BUZZER);
          buzzerActive = false;
          if (!isBoxOpen) {
            Serial.println("   → Opening box via button press during reminder");
            Serial.print("📦 Preserving activeBoxLED: ");
            Serial.println(activeBoxLED);
            openBox();
          } else {
            Serial.println("   → Closing box via button press during reminder");
            Serial.print("📦 activeBoxLED before close: ");
            Serial.println(activeBoxLED);
            closeBox();
          }
        } else {
          // Normal button press - toggle box open/close
          if (!isBoxOpen) {
            Serial.println("   → Opening box");
            openBox();
          } else {
            Serial.println("   → Closing box");
            closeBox();
          }
        }
      } 
      // Button is released (HIGH)
      else if (reading == HIGH && buttonPressed) {
        buttonPressed = false;
        Serial.println("🔘 BUTTON RELEASED");
      }
    }
  }
  lastButtonState = reading;
}