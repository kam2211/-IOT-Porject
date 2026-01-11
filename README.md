# Smart Medicine Box

A Flutter mobile application for IoT-based smart medicine box system with cloud connectivity and customizable reminder features.

## 📋 Overview

This application allows users to:
- Connect and manage smart medicine boxes
- Set customizable reminder times for medication
- Sync with IoT devices and cloud services
- Track medication schedules and adherence


## ✨ Features

- **Smart Reminders**: Customize their medication schedule and Receive medication reminders
- **Remote Control**: Remotely open the box using the phone application
- **Data Dashboard**: Generates medication adherence reports
- **Find My Device**: Helps users locate their connected medicine box by triggering a sound from the Medicine Box

## 🏗️Setup Hardware & Configuration
**Onpow Button**
- Left Leg → Breadboard Negative Power Rail
- Right Leg → A4 Pin of the Maker Port

**SG90 Servo Motor**
- Brown cable → Breadboard Negative Power Rail
- Red cable → Breadboard Positive Power Rail 
- Orange cable → 47 Pin of the Maker Port. 

**Load Cell 1kg**
- Red cable → E+ Pin of the HX711
- Black cable → E- Pin of the HX711
- Grey cable → A-  Pin of the HX711
- Green cable → A+ Pin of the HX711

**HX711**
-GND → Breadboard Negative Power Rail 
-DT → 38 Pin of the Maker Port
-SKC → 48 Pin of the Maker Port
-VCC → 3.3 Pin of the Maker Port

**Pill Compartment LEDs (1–7)**
| LED |Anode Pin (via Resistor) |Cathode|
| ------------- | ------------- |------------- |
| LED 1  | A8 through Resistor 1 |GND |
| LED 2| A9 through Resistor 2 |GND |
| LED 3  | A5 through Resistor 3 |GND |
| LED 4  | A2 through Resistor 4 |GND |
| LED 5  | A3 through Resistor 5 |GND |
| LED 6  |A6 through Resistor 6|GND |
| LED 7  | GPIO 14 through Resistor 7|GND |
| External LED (Outside the box)| GPIO 21 through Resistor 8 |GND |

## 🚀Software Seteup 

### Prerequisites

- Flutter SDK (3.8.1 or higher)
- Dart SDK
- Android Studio / VS Code
- Android device/emulator or iOS device/simulator

### Installation

1. Clone the repository:
```bash
git clone <your-repository-url>
cd "IOT Project"
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

## 📦 Dependencies
- **Firebase** (core + Firestore) for cloud database
- **MQTT client** for real-time IoT communication with the medicine box
- **fl_chart** for displaying medicine intake charts/reports
- **provider**: State management
- **http**: HTTP client for cloud connectivity
- **shared_preferences**: Local data storage
- **flutter_local_notifications**: Local notification support
- **timezone**: Timezone handling for reminders

## 🔌 Hardware
- Cytron Maker Feather AIoT S3
- Breadboard
- Onpow button
- SG90 Servo Motor
- HX711 Load Cell Amplifier
- 1kg Load Cell
- LED
- Resistor
