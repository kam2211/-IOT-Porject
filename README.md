# Smart Medicine Box

A Flutter mobile application for IoT-based smart medicine box system with cloud connectivity and customizable reminder features.

## 📋 Overview

This application allows users to:
- Connect and manage smart medicine boxes
- Set customizable reminder times for medication
- Sync with IoT devices and cloud services
- Track medication schedules and adherence
- Monitor device connectivity status

## ✨ Features

- **Medicine Box Management**: Add, edit, and delete medicine boxes
- **Custom Reminders**: Set multiple reminder times for each box
- **IoT Device Integration**: Connect with physical smart medicine boxes
- **Cloud Sync**: Synchronize data across devices
- **Local Notifications**: Receive medication reminders
- **Material Design 3**: Modern and intuitive UI
- **Dark Mode Support**: Automatic theme switching

## 🏗️ Architecture

The app follows a clean architecture with:
- **Provider** for state management
- **Model-View-Provider** pattern
- Separation of concerns between UI and business logic
- Modular and scalable structure

### Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/
│   └── medicine_box.dart     # Data models
├── providers/
│   └── medicine_box_provider.dart  # State management
├── screens/
│   ├── home_screen.dart      # Main screen
│   ├── add_medicine_box_screen.dart
│   └── box_detail_screen.dart
└── widgets/
    └── medicine_box_card.dart  # Reusable components
```

## 🚀 Getting Started

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

- **provider**: State management
- **http**: HTTP client for cloud connectivity
- **shared_preferences**: Local data storage
- **intl**: Date and time formatting
- **flutter_local_notifications**: Local notification support
- **timezone**: Timezone handling for reminders

## 🔮 Future Enhancements

- [ ] Real IoT device integration (MQTT/HTTP)
- [ ] Cloud backend integration (Firebase/AWS)
- [ ] Medication tracking and history
- [ ] Medication database with drug information
- [ ] User authentication
- [ ] Multi-user support
- [ ] Analytics and reports
- [ ] Bluetooth connectivity for local device pairing
- [ ] Voice reminders
- [ ] Caregiver notifications

## 🔌 IoT Integration Guide

To connect your physical smart medicine box:

1. Set up your IoT device with appropriate firmware
2. Configure device ID in the app
3. Ensure device is connected to the same network
4. Use the sync button to establish connection

### Recommended IoT Platforms
- ESP32/ESP8266 for hardware
- MQTT broker for messaging
- Firebase/AWS IoT Core for cloud backend

## 🎨 UI Screenshots

*(Add screenshots here once app is running)*

## 🛠️ Development

### Run in debug mode:
```bash
flutter run
```

### Build for production:
```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

### Run tests:
```bash
flutter test
```

## 📝 License

This project is for educational/personal use.

## 👥 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📧 Contact

For questions or support, please reach out to the development team.

---

**Note**: This is the initial version of the Smart Medicine Box application. The IoT device integration and cloud backend need to be implemented based on your specific hardware and cloud service choices.
# -IOT-Porject
