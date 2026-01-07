import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/medicine_box.dart';
import '../models/medicine_record.dart';
import 'esp32_service.dart';
import '../providers/medicine_box_provider.dart';

class ReminderService {
  final ESP32Service esp32Service;
  MedicineBoxProvider?
  _medicineBoxProvider; // Mutable provider to check if already taken
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  Timer? _checkTimer;
  List<MedicineBox> _medicineBoxes = [];
  final Set<String> _triggeredReminders = {};
  final Map<String, Timer> _activeEscalations =
      {}; // Track active escalation timers
  final Map<String, int> _notificationCounts =
      {}; // Track notification count per reminder

  ReminderService({
    required this.esp32Service,
    MedicineBoxProvider? medicineBoxProvider,
  }) : _medicineBoxProvider = medicineBoxProvider;

  // Getter for medicineBoxProvider
  MedicineBoxProvider? get medicineBoxProvider => _medicineBoxProvider;

  // Set medicine box provider (called after initialization)
  void setMedicineBoxProvider(MedicineBoxProvider provider) {
    _medicineBoxProvider = provider;
  }

  // Initialize notifications
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request notification permissions for Android 13+
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - could open app to specific screen
  }

  // Update the list of medicine boxes to monitor
  void updateMedicineBoxes(List<MedicineBox> boxes) {
    _medicineBoxes = boxes;
  }

  // Check if medicine is already taken for this box and reminder
  bool _isMedicineAlreadyTaken(MedicineBox box, ReminderTime reminder) {
    if (_medicineBoxProvider == null) {
      // If provider not available, assume not taken (send reminder to be safe)
      return false;
    }

    try {
      final todayRecords = _medicineBoxProvider!.getTodayRecords();
      final matchingRecord = todayRecords.firstWhere(
        (record) =>
            record.medicineBoxId == box.id &&
            record.reminderTimeId == reminder.id,
        orElse: () => MedicineRecord(
          id: '',
          medicineBoxId: '',
          reminderTimeId: '',
          scheduledTime: DateTime.now(),
        ),
      );

      if (matchingRecord.id.isEmpty) {
        // No record found, assume not taken
        return false;
      }

      final isTaken = matchingRecord.isTaken;
      if (isTaken) {
        print('   Found record: ${matchingRecord.id}, isTaken: $isTaken');
        if (matchingRecord.takenTime != null) {
          print('   Taken at: ${matchingRecord.takenTime}');
        }
      }
      return isTaken;
    } catch (e) {
      print('⚠️ Error checking if medicine is taken: $e');
      return false; // If error, assume not taken (send reminder to be safe)
    }
  }

  // Start checking for reminders every minute
  void startMonitoring() {
    stopMonitoring();

    // Check immediately
    _checkReminders();

    // Then check every 30 seconds
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkReminders();
    });
  }

  // Stop monitoring
  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;

    // Cancel all active escalation timers
    for (var timer in _activeEscalations.values) {
      timer.cancel();
    }
    _activeEscalations.clear();
  }

  // Check if any reminder should trigger now
  void _checkReminders() {
    final now = DateTime.now();
    final currentDay = now.weekday; // 1 = Monday, 7 = Sunday

    print(
      '🔍 Checking reminders at ${now.hour}:${now.minute} (Day: $currentDay)',
    );
    print('📦 Medicine boxes count: ${_medicineBoxes.length}');

    for (final box in _medicineBoxes) {
      for (final reminder in box.reminderTimes) {
        if (!reminder.isEnabled) continue;
        if (!reminder.daysOfWeek.contains(currentDay)) continue;

        // Check if current time matches reminder time (within 1 minute window)
        if (reminder.hour == now.hour && reminder.minute == now.minute) {
          final reminderId = '${box.id}_${reminder.id}_${now.day}';

          // Only trigger if not already triggered today
          if (!_triggeredReminders.contains(reminderId)) {
            // Check if medicine is already taken before sending reminder
            if (_isMedicineAlreadyTaken(box, reminder)) {
              print(
                '✅ Medicine already taken for ${box.name} at ${reminder.hour}:${reminder.minute.toString().padLeft(2, '0')} - skipping reminder',
              );
              _triggeredReminders.add(
                reminderId,
              ); // Mark as processed so we don't check again
              continue;
            }

            print('🔔 TRIGGERING REMINDER for ${box.name}!');
            _triggeredReminders.add(reminderId);
            _startEscalationSequence(box, reminder, reminderId);
          }
        }
      }
    }

    // Clear old triggered reminders (from previous days)
    _cleanupTriggeredReminders();
  }

  // Start the 4-stage escalation notification sequence
  Future<void> _startEscalationSequence(
    MedicineBox box,
    ReminderTime reminder,
    String reminderId,
  ) async {
    print('🚀 Starting escalation sequence for ${box.name}');

    // Cancel any existing escalation for this reminder
    _activeEscalations[reminderId]?.cancel();
    _notificationCounts[reminderId] = 1;

    // Stage 1: Immediate notification
    await _sendNotification(box, 1);
    await _triggerReminderForBox(
      box,
    ); // Trigger reminder on ESP32 with box number

    // Schedule Stage 2: After 10 minutes
    Timer? escalationTimer;
    int stage = 1;

    escalationTimer = Timer.periodic(const Duration(minutes: 10), (
      timer,
    ) async {
      stage++;

      // Check if box was opened via IoT
      if (await _checkIfBoxOpened()) {
        print('✅ Box opened detected! Stopping escalation.');
        timer.cancel();
        _activeEscalations.remove(reminderId);
        _notificationCounts.remove(reminderId);
        await _turnOffBoxLED(box); // Turn off LED when medicine is taken
        return;
      }

      if (stage <= 4) {
        // Send notification stages 2, 3, 4
        print('⏰ Escalation Stage $stage for ${box.name}');
        _notificationCounts[reminderId] = stage;
        await _sendNotification(box, stage);
        await _triggerBuzzer();
        // Re-trigger reminder to ensure LED stays on
        await _triggerReminderForBox(box);
      }

      // Stop after 4 notifications (30 minutes)
      if (stage >= 4) {
        print('🛑 Maximum escalation reached (30 minutes)');
        timer.cancel();
        _activeEscalations.remove(reminderId);
        _notificationCounts.remove(reminderId);
        await _turnOffBoxLED(box); // Turn off LED after max escalation
      }
    });

    _activeEscalations[reminderId] = escalationTimer;
  }

  // Send notification based on stage
  Future<void> _sendNotification(MedicineBox box, int stage) async {
    String title;
    String body;
    int id = box.id.hashCode + stage;

    switch (stage) {
      case 1:
        title = '💊 Medicine Time!';
        body = 'Time to take ${box.name}';
        break;
      case 2:
        title = '⏰ Reminder: Medicine Missed';
        body = 'You haven\'t taken ${box.name} yet. Please take it now!';
        break;
      case 3:
        title = '⚠️ Important: Medicine Not Taken';
        body = '${box.name} still not taken. This is your 3rd reminder!';
        break;
      case 4:
        title = '🚨 Final Reminder!';
        body = 'Last reminder for ${box.name}. Please take it now!';
        break;
      default:
        title = 'Medicine Reminder';
        body = 'Please take ${box.name}';
    }

    await _showNotification(title: title, body: body, id: id);
  }

  // Show local notification
  Future<void> _showNotification({
    required String title,
    required String body,
    required int id,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'medicine_reminder',
      'Medicine Reminders',
      channelDescription: 'Notifications for medicine reminders',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: 'Medicine Reminder',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(id, title, body, details);
  }

  // Trigger buzzer on ESP32
  Future<void> _triggerBuzzer() async {
    if (esp32Service.isConnected) {
      print('📡 Triggering buzzer...');
      await esp32Service.triggerBuzzer(times: 5);
    } else {
      print('❌ ESP32 not connected - cannot trigger buzzer');
    }
  }

  // Trigger reminder on ESP32 for specific box
  Future<void> _triggerReminderForBox(MedicineBox box) async {
    print(
      '🔔 Triggering reminder on ESP32 for Box ${box.boxNumber} (${box.name})',
    );

    // Check if box number is valid
    if (box.boxNumber < 1 || box.boxNumber > 7) {
      print('❌ Invalid box number: ${box.boxNumber}. Must be between 1 and 7');
      return;
    }

    // If no IP address is set, try to use a connected device
    if (esp32Service.ipAddress == null || esp32Service.ipAddress!.isEmpty) {
      print('⚠️ No IP address set. Checking for connected devices...');
      if (esp32Service.connectedDevices.isNotEmpty) {
        final device =
            esp32Service.activeDevice ?? esp32Service.connectedDevices.first;
        print('📱 Found connected device: ${device.name} (${device.ip})');
        esp32Service.setIpAddress(device.ip, deviceName: device.name);
      } else {
        print(
          '❌ No connected devices found. Please connect to ESP32 device first.',
        );
        print('   Go to Device screen and connect to your ESP32 device.');
        return;
      }
    }

    // Try to connect if not connected
    if (!esp32Service.isConnected) {
      print('⚠️ ESP32 not connected. Attempting to connect...');
      final connected = await esp32Service.testConnection();
      if (!connected) {
        print('❌ ESP32 connection failed - cannot trigger reminder');
        print('   Error: ${esp32Service.error}');
        print('   Please check:');
        print('   1. ESP32 is powered on');
        print('   2. ESP32 is connected to WiFi');
        print('   3. Phone and ESP32 are on the same network');
        return;
      }
      print('✅ ESP32 connected successfully');
    }

    // Trigger reminder on ESP32 with box number
    print('📡 Sending reminder command for Box ${box.boxNumber}');
    final success = await esp32Service.triggerReminder(box.boxNumber);
    if (success) {
      print('✅ Reminder triggered successfully for Box ${box.boxNumber}');
      // Map box numbers to GPIO pins
      final gpioMap = {1: 10, 2: 9, 3: 6, 4: 5, 5: 17, 6: 8, 7: 15};
      final gpioPin = gpioMap[box.boxNumber] ?? 0;
      print(
        '   Expected: GPIO $gpioPin (Box ${box.boxNumber} LED) should light up',
      );
      print('   Expected: GPIO 21 (Outside LED) should also light up');
      print('   Expected: Buzzer should beep');
    } else {
      print('❌ Failed to trigger reminder for Box ${box.boxNumber}');
      print('   Error: ${esp32Service.error}');
    }
  }

  // Turn off LED for specific box
  Future<void> _turnOffBoxLED(MedicineBox box) async {
    if (esp32Service.isConnected && box.boxNumber >= 1 && box.boxNumber <= 7) {
      print('💡 Turning off LED for Box ${box.boxNumber} (${box.name})');
      await esp32Service.setBoxLED(box.boxNumber, false);
    }
  }

  // Check if box was opened via IoT device
  Future<bool> _checkIfBoxOpened() async {
    try {
      final status = await esp32Service.getStatus();
      // Box is considered "opened" if button was pressed or medicine was taken
      return status?.isBoxOpen == true || status?.medicineTaken == true;
    } catch (e) {
      print('Error checking ESP32 status: $e');
      return false;
    }
  }

  // Manual method to stop escalation when user marks as taken manually
  void stopEscalation(String boxId, String reminderId) async {
    final today = DateTime.now().day;
    final escalationId = '${boxId}_${reminderId}_$today';

    _activeEscalations[escalationId]?.cancel();
    _activeEscalations.remove(escalationId);
    _notificationCounts.remove(escalationId);

    // Find the box and turn off its LED
    final box = _medicineBoxes.firstWhere(
      (b) => b.id == boxId,
      orElse: () =>
          MedicineBox(id: '', name: '', boxNumber: 0, reminderTimes: []),
    );
    if (box.id.isNotEmpty) {
      await _turnOffBoxLED(box);
    }

    print('🛑 Stopped escalation for $escalationId (manually marked as taken)');
  }

  // Clean up old triggered reminders
  void _cleanupTriggeredReminders() {
    final today = DateTime.now().day;
    _triggeredReminders.removeWhere((id) {
      final parts = id.split('_');
      if (parts.length >= 3) {
        final day = int.tryParse(parts.last);
        return day != null && day != today;
      }
      return false;
    });
  }

  // Manual trigger for testing
  Future<void> testBuzzer() async {
    if (esp32Service.isConnected) {
      await esp32Service.triggerBuzzer(times: 3);
    }
  }

  void dispose() {
    stopMonitoring();
  }
}
