#include <WiFi.h>
#include <WebServer.h>
#include <PubSubClient.h>
#include "HX711.h"
#include <ESP32Servo.h>
#include <Preferences.h>
#include <ESPmDNS.h>

// ================= WIFI & MQTT =================
const char* ssid = "Uhuk";
const char* password = "kam1234@";
const char* deviceName = "medicinebox";
const char* mqtt_server = "34.19.178.165";
const int mqtt_port = 1883;

// Dynamic boxId - stored in Preferences (EEPROM)
Preferences preferences;
String boxId = "";
String medicineBoxId = "";

WiFiClient espClient;
PubSubClient mqtt(espClient);

// ================= PINS =================
const int PIN_SERVO = 47;
const int PIN_BUTTON = 4;
const int PIN_HX711_DT = 48;
const int PIN_HX711_SCK = 38;
const int PIN_BUZZER = 12;
const int PIN_LED = 21;

// Pill Box LEDs
const int PIN_BOX1_LED = 18;
const int PIN_BOX2_LED = 16;
const int PIN_BOX3_LED = 7;
const int PIN_BOX4_LED = 6;
const int PIN_BOX5_LED = 5;
const int PIN_BOX6_LED = 17;
const int PIN_BOX7_LED = 14;

const int BOX_LEDS[] = {
  0,
  PIN_BOX1_LED,
  PIN_BOX2_LED,
  PIN_BOX3_LED,
  PIN_BOX4_LED,
  PIN_BOX5_LED,
  PIN_BOX6_LED,
  PIN_BOX7_LED,
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

// NEW: Weight correction multiplier (will be set automatically)
float weightMultiplier = 1.0;

int CLOSED_ANGLE = 0;
int OPEN_ANGLE = 90;

bool reminderActive = false;
unsigned long reminderStartTime = 0;
unsigned long lastReminderBuzz = 0;
const unsigned long REMINDER_WINDOW = 30UL * 60UL * 1000UL;
const unsigned long REMINDER_INTERVAL = 5UL * 60UL * 1000UL;
int activeBoxLED = 0;

// Button Debounce
static bool lastButtonState = HIGH;
static unsigned long lastDebounceTime = 0;
static bool buttonPressed = false;
const unsigned long debounceDelay = 50;
static unsigned long systemStartTime = 0;
const unsigned long STARTUP_IGNORE_DELAY = 3000;

bool boxOpenedViaButton = false;
unsigned long lastReminderTriggeredTime = 0;
int lastReminderTriggeredBoxNumber = 0;
unsigned long lastBoxLEDTurnedOnTime = 0;
int lastBoxLEDTurnedOnBoxNumber = 0;
const unsigned long RECENT_ACTION_WINDOW = 10 * 60 * 1000;

// Blink variables
bool blinkActive = false;
int blinkBoxNumber = 0;
int blinkCount = 0;
int blinkTimes = 5;
bool blinkState = false;
unsigned long blinkLastToggle = 0;
const unsigned long BLINK_ON_DURATION = 300;
const unsigned long BLINK_OFF_DURATION = 300;

// ================= NEW: GET CORRECTED WEIGHT =================
float getCorrectedWeight(int samples = 10) {
  float rawWeight = scale.get_units(samples);
  float correctedWeight = rawWeight * weightMultiplier;
  
  return correctedWeight;
}

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

String getOrCreateBoxId() {
  preferences.begin("medicinebox", false);
  String savedBoxId = preferences.getString("boxId", "");
  preferences.end();

  if (savedBoxId.length() > 0) {
    Serial.print("📦 Loaded boxId from storage: ");
    Serial.println(savedBoxId);
    return savedBoxId;
  }

  String mac = WiFi.macAddress();
  mac.replace(":", "");
  String newBoxId = mac.substring(6);

  preferences.begin("medicinebox", false);
  preferences.putString("boxId", newBoxId);
  preferences.end();

  Serial.print("📦 Generated new boxId from MAC: ");
  Serial.println(newBoxId);
  return newBoxId;
}

String getCompartmentName() {
  if (activeBoxLED > 0 && activeBoxLED <= 7) {
    return "box" + String(activeBoxLED);
  }
  return "box1";
}

void publishStatusMQTT(float weight, bool taken, int boxNumber = 0) {
  if (!mqtt.connected()) return;

  String mqttBoxId = medicineBoxId.length() > 0 ? medicineBoxId : boxId;
  if (mqttBoxId.length() == 0) {
    Serial.println("⚠️ No boxId available for MQTT publish");
    return;
  }

  int compartmentNumber = 1;
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
  payload += "\"medicineBoxId\":\"" + mqttBoxId + "\",";
  payload += "\"boxNumber\":" + String(compartmentNumber) + ",";
  payload += "\"compartment\":\"" + compartment + "\",";
  payload += "\"weight\":" + String(weight, 2) + ",";
  payload += "\"taken\":" + String(taken ? "true" : "false") + ",";
  payload += "\"timestamp\":" + String(millis());
  payload += "}";

  mqtt.publish(topic.c_str(), payload.c_str());
  Serial.println("📤 MQTT published: " + payload);
}

// ================= ACTION LOGIC =================
// Slow servo movement function
void moveServoSlowly(int targetAngle) {
  int currentAngle = myServo.read();
  int step = (targetAngle > currentAngle) ? 1 : -1;
  
  Serial.print("Moving servo from ");
  Serial.print(currentAngle);
  Serial.print(" to ");
  Serial.println(targetAngle);
  
  while (currentAngle != targetAngle) {
    currentAngle += step;
    myServo.write(currentAngle);
    delay(15);  // Adjust this delay to control speed (lower = faster, higher = slower)
  }
}

void openBox() {
  if (isBoxOpen) return;
  Serial.println("--- Opening Sequence Start ---");
  moveServoSlowly(OPEN_ANGLE);
  isBoxOpen = true;
  digitalWrite(PIN_LED, HIGH);
  
  // Wait for servo vibrations to settle before measuring weight
  Serial.println("⏳ Waiting for servo to stabilize...");
  delay(2000);  // 2 second delay for stabilization
  
  weightAtStart = getCorrectedWeight(15);  // CHANGED: Use corrected weight
  Serial.print("Initial Weight Captured: ");
  Serial.println(weightAtStart);
}

void closeBox(int overrideBoxNumber = 0) {
  if (!isBoxOpen) return;
  Serial.println("--- Closing Sequence Start ---");

  int capturedBoxLED = activeBoxLED;

  if (overrideBoxNumber > 0) {
    capturedBoxLED = overrideBoxNumber;
    Serial.print("📦 Using override boxNumber: ");
    Serial.println(overrideBoxNumber);
  }

  Serial.print("📦 activeBoxLED at start of closeBox: ");
  Serial.println(activeBoxLED);
  Serial.print("📦 Captured box LED for MQTT: ");
  Serial.println(capturedBoxLED);

  if (capturedBoxLED == 0 && reminderActive) {
    for (int i = 1; i <= 7; i++) {
      if (digitalRead(BOX_LEDS[i]) == HIGH) {
        capturedBoxLED = i;
        activeBoxLED = i;
        Serial.print("📦 Recovered activeBoxLED from LED state: ");
        Serial.println(capturedBoxLED);
        break;
      }
    }
  }

  // Close servo first
  moveServoSlowly(CLOSED_ANGLE);
  
  // Wait for servo vibrations to settle before measuring weight
  Serial.println("⏳ Waiting for servo to stabilize...");
  delay(3000);  // 3 second delay for stabilization after closing
  
  float weightAtEnd = getCorrectedWeight(15);  // CHANGED: Use corrected weight
  Serial.print("Final Weight Captured: ");
  Serial.println(weightAtEnd);

  lastWeightLoss = weightAtStart - weightAtEnd;
  Serial.print("Calculated Weight Loss: ");
  Serial.println(lastWeightLoss);

  medicineTaken = (lastWeightLoss > 0.05);
  Serial.print("Medicine Taken: ");
  Serial.println(medicineTaken ? "YES" : "NO");
  isBoxOpen = false;

  if (medicineTaken) {
    reminderActive = false;
    digitalWrite(PIN_LED, LOW);
    for (int i = 1; i <= 7; i++) {
      digitalWrite(BOX_LEDS[i], LOW);
    }
  } else {
    digitalWrite(PIN_LED, LOW);
  }

  Serial.print("📦 Publishing MQTT with box number: ");
  Serial.println(capturedBoxLED);
  Serial.print("💾 Publishing status - medicineBoxId: ");
  Serial.print(medicineBoxId);
  Serial.print(" | boxNumber: ");
  Serial.print(capturedBoxLED);
  Serial.print(" | taken: ");
  Serial.println(medicineTaken ? "YES" : "NO");

  publishStatusMQTT(weightAtEnd, medicineTaken, capturedBoxLED);

  if (medicineTaken) {
    activeBoxLED = 0;
    Serial.println("📦 activeBoxLED reset to 0 after MQTT publish");
  }
}

// ================= HTTP HANDLERS =================
void handleStatus() {
  float currentWeight = getCorrectedWeight(5);  // CHANGED: Use corrected weight
  String json = "{";
  json += "\"isBoxOpen\":" + String(isBoxOpen ? "true" : "false") + ",";
  json += "\"medicineTaken\":" + String(medicineTaken ? "true" : "false") + ",";
  json += "\"weightLoss\":" + String(lastWeightLoss) + ",";
  json += "\"currentWeight\":" + String(currentWeight) + ",";
  json += "\"boxId\":\"" + boxId + "\",";
  json += "\"medicineBoxId\":\"" + medicineBoxId + "\",";
  json += "\"activeBoxLED\":" + String(activeBoxLED);
  json += "}";
  server.send(200, "application/json", json);
}

void handleSetMedicineBoxId() {
  if (server.hasArg("id")) {
    medicineBoxId = server.arg("id");
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
  int boxNumber = 0;
  if (server.hasArg("box")) {
    boxNumber = server.arg("box").toInt();
    if (boxNumber > 0 && boxNumber <= 7) {
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
  unsigned long now = millis();
  int boxNumberForRecord = 1;

  if (now - lastReminderTriggeredTime < RECENT_ACTION_WINDOW) {
    boxNumberForRecord = lastReminderTriggeredBoxNumber;
    Serial.print("📦 Using recent reminder box: ");
    Serial.println(boxNumberForRecord);
  }
  else if (now - lastBoxLEDTurnedOnTime < RECENT_ACTION_WINDOW) {
    boxNumberForRecord = lastBoxLEDTurnedOnBoxNumber;
    Serial.print("📦 Using recent LED tap box: ");
    Serial.println(boxNumberForRecord);
  }
  else if (activeBoxLED > 0 && activeBoxLED <= 7) {
    boxNumberForRecord = activeBoxLED;
    Serial.print("📦 Using active box LED: ");
    Serial.println(boxNumberForRecord);
  }

  closeBox(boxNumberForRecord);

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
  lastReminderBuzz = 0;

  lastReminderTriggeredTime = millis();
  lastReminderTriggeredBoxNumber = boxNumber;
  Serial.print("⏰ Reminder trigger recorded at: ");
  Serial.println(lastReminderTriggeredTime);

  activeBoxLED = boxNumber;
  Serial.print("📦 activeBoxLED set to: ");
  Serial.println(activeBoxLED);

  for (int i = 1; i <= 7; i++) {
    digitalWrite(BOX_LEDS[i], LOW);
  }

  digitalWrite(BOX_LEDS[boxNumber], HIGH);
  digitalWrite(PIN_LED, HIGH);

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
  server.send(200, "application/json", "{\"success\":true,\"box\":" + String(boxNumber) + "}");
}

void handleStartAlarm() {
  Serial.println("Find My Device Active");
  buzzerActive = true;
  server.send(200, "application/json", "{\"success\":true}");
}

void handleStopBuzzer() {
  Serial.println("Alarms Stopped");
  buzzerActive = false;
  noTone(PIN_BUZZER);
  server.send(200, "application/json", "{\"success\":true}");
}

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

void turnOffAllBoxLEDs() {
  for (int i = 1; i <= 7; i++) {
    digitalWrite(BOX_LEDS[i], LOW);
  }
  if (!isBoxOpen) {
    activeBoxLED = 0;
  }
}

void handleLEDControl() {
  if (server.hasArg("box") && server.hasArg("state")) {
    int boxNumber = server.arg("box").toInt();
    String state = server.arg("state");
    bool ledState = (state == "on" || state == "1" || state == "true");

    if (boxNumber == 0 || boxNumber == 21) {
      digitalWrite(PIN_LED, ledState ? HIGH : LOW);
      Serial.print("💡 External LED (GPIO 21) turned ");
      Serial.println(ledState ? "ON" : "OFF");
      String response = "{\"success\":true,\"ledPin\":21,\"state\":\"" + String(ledState ? "on" : "off") + "\"}";
      server.send(200, "application/json", response);
      return;
    }

    setBoxLED(boxNumber, ledState);

    if (ledState) {
      digitalWrite(PIN_LED, HIGH);
    } else {
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

  activeBoxLED = boxNumber;
  Serial.print("📦 activeBoxLED set to: ");
  Serial.println(activeBoxLED);

  blinkActive = true;
  blinkBoxNumber = boxNumber;
  blinkCount = 0;
  blinkTimes = times;
  blinkState = true;
  blinkLastToggle = millis();

  digitalWrite(BOX_LEDS[boxNumber], HIGH);
  digitalWrite(PIN_LED, HIGH);
}

void stopBlink() {
  if (blinkActive) {
    Serial.println("💡 Stopping blink");
    digitalWrite(BOX_LEDS[blinkBoxNumber], LOW);
    blinkActive = false;
    blinkBoxNumber = 0;
    blinkCount = 0;
    blinkState = false;

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

void handleBlinkLED() {
  if (server.hasArg("box")) {
    int boxNumber = server.arg("box").toInt();
    int times = 2;
    if (server.hasArg("times")) {
      times = server.arg("times").toInt();
    }
    startBlink(boxNumber, times);
    server.send(200, "application/json", "{\"success\":true,\"box\":" + String(boxNumber) + ",\"times\":" + String(times) + "}");
  } else {
    server.send(400, "application/json", "{\"error\":\"Missing box parameter\"}");
  }
}

// NEW: Test weight endpoint
void handleTestWeight() {
  float rawWeight = scale.get_units(10);
  float correctedWeight = getCorrectedWeight(10);
  
  String json = "{";
  json += "\"rawWeight\":" + String(rawWeight, 2) + ",";
  json += "\"correctedWeight\":" + String(correctedWeight, 2) + ",";
  json += "\"multiplier\":" + String(weightMultiplier, 2);
  json += "}";
  
  Serial.println("⚖️ Weight Test:");
  Serial.print("  Raw: ");
  Serial.println(rawWeight);
  Serial.print("  Corrected: ");
  Serial.println(correctedWeight);
  
  server.send(200, "application/json", json);
}

// ================= SETUP =================
void setup() {
  Serial.begin(115200);

  pinMode(PIN_LED, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_BUTTON, INPUT_PULLUP);

  int initialButtonState = digitalRead(PIN_BUTTON);
  Serial.print("🔘 Button pin (GPIO ");
  Serial.print(PIN_BUTTON);
  Serial.print(") initialized. Initial state: ");
  Serial.println(initialButtonState == HIGH ? "HIGH (not pressed)" : "LOW (pressed)");

  pinMode(PIN_BOX1_LED, OUTPUT);
  pinMode(PIN_BOX2_LED, OUTPUT);
  pinMode(PIN_BOX3_LED, OUTPUT);
  pinMode(PIN_BOX4_LED, OUTPUT);
  pinMode(PIN_BOX5_LED, OUTPUT);
  pinMode(PIN_BOX6_LED, OUTPUT);
  pinMode(PIN_BOX7_LED, OUTPUT);

  turnOffAllBoxLEDs();
  digitalWrite(PIN_LED, LOW);

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
    if (attempts > 40) {
      Serial.println("\n❌ WiFi Connection Failed!");
      Serial.println("Please check:");
      Serial.println(" 1. SSID and password are correct");
      Serial.println(" 2. WiFi router is powered on");
      Serial.println(" 3. ESP32 is within range");
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

  boxId = getOrCreateBoxId();
  Serial.print("📦 Device boxId (ESP32): ");
  Serial.println(boxId);

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
  server.on("/testweight", handleTestWeight);  // NEW: Test weight endpoint
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

  CLOSED_ANGLE = 0;
  OPEN_ANGLE =180;
  Serial.print("📦 CLOSED angle: ");
  Serial.println(CLOSED_ANGLE);
  Serial.print("📦 OPEN angle: ");
  Serial.println(OPEN_ANGLE);

  myServo.write(CLOSED_ANGLE);
  isBoxOpen = false;
  Serial.println("📦 isBoxOpen set to: false");
  Serial.println("===== SERVO INITIALIZATION COMPLETE =====\n");

  // ===== IMPROVED SCALE INITIALIZATION =====
  Serial.println("\n===== SCALE INITIALIZATION =====");
  scale.begin(PIN_HX711_DT, PIN_HX711_SCK);
  
  Serial.println("⚖️ Waiting for scale to stabilize...");
  delay(2000);
  
  if (scale.is_ready()) {
    Serial.println("✅ HX711 detected and ready");
  } else {
    Serial.println("❌ HX711 not found - check wiring!");
  }
  
  // Get initial reading before tare
  long rawReading = scale.read_average(10);
  Serial.print("Raw reading (before tare): ");
  Serial.println(rawReading);
  
  // Tare the scale
  Serial.println("⚖️ Taring scale (remove all weight)...");
  delay(2000);
  scale.tare();
  delay(500);
  scale.tare(); // Tare twice for accuracy
  Serial.println("✅ Scale tared (zeroed)");
  
  // Set initial calibration factor (positive)
  scale.set_scale(414.0);
  
  // Test reading to check if negative
  delay(1000);
  float testWeight = scale.get_units(10);
  Serial.print("⚖️ Test reading after tare: ");
  Serial.println(testWeight);
  
  // AUTO-CORRECT: If readings are consistently negative, flip the multiplier
  if (testWeight < -5.0) {  // If significantly negative (allowing some noise)
    Serial.println("⚠️ NEGATIVE readings detected!");
    Serial.println("⚙️ Auto-correcting: Setting weight multiplier to -1");
    weightMultiplier = -1.0;
    
    // Test again
    delay(500);
    testWeight = getCorrectedWeight(10);
    Serial.print("✅ Corrected test reading: ");
    Serial.println(testWeight);
  } else {
    Serial.println("✅ Readings are positive - no correction needed");
    weightMultiplier = 1.0;
  }
  
  Serial.println("===== SCALE READY =====\n");

  Serial.println("System Ready.");
  systemStartTime = millis();
  Serial.println("⏱️ Ignoring button input for 3 seconds to allow system stabilization...");
}

// ================= LOOP =================
void loop() {
  server.handleClient();

  static unsigned long lastWiFiCheck = 0;
  if (millis() - lastWiFiCheck > 30000) {
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

  if (blinkActive) {
    if (blinkState == false) {
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

        if (blinkCount >= blinkTimes) {
          stopBlink();
          Serial.println("💡 Blink sequence complete");
        } else {
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
  else if (reminderActive && !medicineTaken) {
    digitalWrite(PIN_LED, HIGH);
    if (activeBoxLED > 0 && activeBoxLED <= 7) {
      digitalWrite(BOX_LEDS[activeBoxLED], HIGH);
    }

    if (lastReminderBuzz == 0 || now - lastReminderBuzz >= REMINDER_INTERVAL) {
      lastReminderBuzz = now;
      tone(PIN_BUZZER, 300);
      delay(1000);
      noTone(PIN_BUZZER);
    }
  }
  else if (!isBoxOpen && !reminderActive && !buzzerActive) {
    noTone(PIN_BUZZER);
    digitalWrite(PIN_LED, LOW);
    turnOffAllBoxLEDs();
  }

  int reading = digitalRead(PIN_BUTTON);

  static unsigned long lastStartupMessage = 0;
  static bool startupIgnoreDone = false;
  unsigned long timeSinceStartup = millis() - systemStartTime;

  if (timeSinceStartup < STARTUP_IGNORE_DELAY) {
    if (timeSinceStartup - lastStartupMessage > 1000) {
      lastStartupMessage = timeSinceStartup;
      Serial.print("⏱️ Startup ignore: ");
      Serial.print((STARTUP_IGNORE_DELAY - timeSinceStartup) / 1000);
      Serial.println(" seconds remaining...");
    }
    lastButtonState = reading;
    lastDebounceTime = millis();
  } else {
    if (!startupIgnoreDone) {
      startupIgnoreDone = true;
      buttonPressed = false;
      lastButtonState = reading;
      Serial.println("✅ Startup ignore complete - button monitoring active");
      Serial.print("🔘 Initial button state: ");
      Serial.println(reading == HIGH ? "HIGH (not pressed)" : "LOW (pressed)");
    }

    if (reading != lastButtonState) {
      lastDebounceTime = now;
      Serial.print("🔘 Button state changed to: ");
      Serial.println(reading == HIGH ? "HIGH" : "LOW");
    }

    if ((now - lastDebounceTime) > debounceDelay) {
      if (reading == LOW && !buttonPressed) {
        buttonPressed = true;
        Serial.println("🔘 BUTTON PRESSED! ✓");

        if (buzzerActive) {
          Serial.println(" → Stopping find-my-device alarm");
          handleStopBuzzer();
        } else if (reminderActive) {
          Serial.println(" → Button pressed during reminder - stopping buzzer, keeping LED on");
          Serial.print("📦 Current activeBoxLED: ");
          Serial.println(activeBoxLED);
          noTone(PIN_BUZZER);
          buzzerActive = false;

          if (!isBoxOpen) {
            Serial.println(" → Opening box via button press during reminder");
            Serial.print("📦 Preserving activeBoxLED: ");
            Serial.println(activeBoxLED);
            openBox();
          } else {
            Serial.println(" → Closing box via button press during reminder");
            Serial.print("📦 activeBoxLED before close: ");
            Serial.println(activeBoxLED);
            closeBox();
          }
        } else {
          if (!isBoxOpen) {
            Serial.println(" → Opening box");
            openBox();
          } else {
            Serial.println(" → Closing box");
            closeBox();
          }
        }
      }
      else if (reading == HIGH && buttonPressed) {
        buttonPressed = false;
        Serial.println("🔘 BUTTON RELEASED");
      }
    }
  }

  lastButtonState = reading;
}