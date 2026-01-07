import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/medicine_box.dart';
import '../models/medicine_record.dart';
import '../services/esp32_service.dart';
import 'dart:async';

class MedicineBoxProvider extends ChangeNotifier {
  /// Delete today's and future untaken records for a reminder (keep past records for reporting)
  Future<void> deleteReminderAndFutureRecords(String reminderId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Find records for today and future that are not taken
    final recordsToDelete = _medicineRecords
        .where(
          (r) =>
              r.reminderTimeId == reminderId &&
              !r.isTaken &&
              !r.scheduledTime.isBefore(today),
        )
        .toList();

    for (final record in recordsToDelete) {
      await _firestore.collection('medicineRecords').doc(record.id).delete();
      _medicineRecords.removeWhere((r) => r.id == record.id);
    }

    notifyListeners();
  }

  /// Fetch today's medicine records directly from Firestore and merge with dynamic schedule
  Future<List<MedicineRecord>> fetchTodayRecordsFromDatabase() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // Fetch actual records from DB (taken/missed) - get fresh data from server
    final snapshot = await _firestore
        .collection('medicineRecords')
        .where(
          'scheduledTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where('scheduledTime', isLessThan: Timestamp.fromDate(endOfDay))
        .get();

    final dbRecords = snapshot.docs.map((doc) {
      final data = doc.data();
      // Ensure the document ID is included in the record
      data['id'] = doc.id;

      // Properly parse the record, handling both Timestamp and string formats
      final record = MedicineRecord(
        id: data['id'] ?? doc.id,
        medicineBoxId: data['medicineBoxId'] ?? '',
        reminderTimeId: data['reminderTimeId'] ?? '',
        scheduledTime: _parseFirestoreDate(data['scheduledTime']),
        takenTime: data['takenTime'] != null
            ? _parseFirestoreDate(data['takenTime'])
            : null,
        isTaken: data['isTaken'] == true || data['isTaken'] == 'true',
        isMissed: data['isMissed'] == true || data['isMissed'] == 'true',
      );
      print(
        '📥 Fetched from Firestore: id=${record.id}, isTaken=${record.isTaken}, box=${record.medicineBoxId}, reminder=${record.reminderTimeId}',
      );
      return record;
    }).toList();

    print('📦 Total DB records fetched: ${dbRecords.length}');

    // Generate today's schedule from reminders
    final todaySchedule = _generateTodayScheduleFromReminders();

    // Merge: DB records override schedule, schedule fills gaps
    final Map<String, MedicineRecord> mergedRecords = {};

    // Add all scheduled doses (from reminders)
    for (var schedule in todaySchedule) {
      final key = '${schedule.medicineBoxId}_${schedule.reminderTimeId}';
      mergedRecords[key] = schedule;
    }

    // Override with actual records from DB (taken or missed)
    for (var record in dbRecords) {
      final key = '${record.medicineBoxId}_${record.reminderTimeId}';
      mergedRecords[key] = record;
      print(
        '📋 Merging DB record from Firestore: key=$key, isTaken=${record.isTaken}, id=${record.id}',
      );
    }

    // Also merge local records (these might be more recent than Firestore due to eventual consistency)
    // Use startOfDay and endOfDay that are already calculated above
    for (var record in _medicineRecords) {
      if (record.scheduledTime.isAfter(
            startOfDay.subtract(const Duration(seconds: 1)),
          ) &&
          record.scheduledTime.isBefore(endOfDay)) {
        final key = '${record.medicineBoxId}_${record.reminderTimeId}';
        // Local records take precedence over Firestore records (they're more recent)
        mergedRecords[key] = record;
        print(
          '📋 Merging local record: key=$key, isTaken=${record.isTaken}, id=${record.id}',
        );
      }
    }

    final result = mergedRecords.values.toList()
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

    print(
      '📊 Total merged records: ${result.length}, Taken: ${result.where((r) => r.isTaken).length}',
    );
    for (var r in result) {
      print(
        '  - ${r.id}: isTaken=${r.isTaken}, box=${r.medicineBoxId}, reminder=${r.reminderTimeId}',
      );
    }

    return result;
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot>? _medicineBoxesSubscription;

  List<MedicineBox> _medicineBoxes = [];
  final List<MedicineRecord> _medicineRecords = [];
  bool _isLoading = false;
  String? _error;

  List<MedicineBox> get medicineBoxes => _medicineBoxes;
  List<MedicineRecord> get medicineRecords => _medicineRecords;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Track the last tapped LED reminder (when user taps light bulb button)
  String? _lastTappedReminderTimeId;
  int? _lastTappedBoxNumber;
  DateTime? _lastTappedTime;

  // Set the last tapped reminder when LED button is tapped
  void setLastTappedReminder(int boxNumber, String reminderTimeId) {
    _lastTappedBoxNumber = boxNumber;
    _lastTappedReminderTimeId = reminderTimeId;
    _lastTappedTime = DateTime.now();
    print(
      '💡 Tracked LED tap: boxNumber=$boxNumber, reminderTimeId=$reminderTimeId',
    );
  }

  // Clear the last tapped reminder after it's used or expires (5 minutes)
  void _clearLastTappedReminder() {
    _lastTappedBoxNumber = null;
    _lastTappedReminderTimeId = null;
    _lastTappedTime = null;
    print('🧹 Cleared last tapped reminder');
  }

  // Check if last tapped reminder is still valid (within 10 minutes)
  bool get _hasValidTappedReminder {
    if (_lastTappedTime == null) return false;
    final now = DateTime.now();
    final minutesSinceTap = now.difference(_lastTappedTime!).inMinutes;
    return minutesSinceTap < 10;
  }

  // Get records for a specific date range
  // For today's records, includes scheduled doses that haven't been created as records yet
  List<MedicineRecord> getRecordsForDateRange(DateTime start, DateTime end) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayEnd = today.add(const Duration(days: 1));

    // Get records from database for the date range
    final dbRecords = _medicineRecords.where((record) {
      return record.scheduledTime.isAfter(
            start.subtract(const Duration(days: 1)),
          ) &&
          record.scheduledTime.isBefore(end.add(const Duration(days: 1)));
    }).toList();

    // If the date range includes today, merge with today's scheduled doses
    if (start.isBefore(todayEnd) &&
        end.isAfter(today.subtract(const Duration(seconds: 1)))) {
      final todaySchedule = _generateTodayScheduleFromReminders();
      final Map<String, MedicineRecord> mergedRecords = {};

      // Add all scheduled doses for today (from reminders)
      for (var schedule in todaySchedule) {
        final key = '${schedule.medicineBoxId}_${schedule.reminderTimeId}';
        mergedRecords[key] = schedule;
      }

      // Override with actual records from DB (taken or missed) that are in the date range
      for (var record in dbRecords) {
        if (record.scheduledTime.isAfter(
              today.subtract(const Duration(seconds: 1)),
            ) &&
            record.scheduledTime.isBefore(todayEnd)) {
          final key = '${record.medicineBoxId}_${record.reminderTimeId}';
          mergedRecords[key] = record; // DB record overrides schedule
        }
      }

      // Add other records (not from today) from dbRecords
      final otherRecords = dbRecords.where((record) {
        return !(record.scheduledTime.isAfter(
              today.subtract(const Duration(seconds: 1)),
            ) &&
            record.scheduledTime.isBefore(todayEnd));
      }).toList();

      return [...mergedRecords.values, ...otherRecords]
        ..sort((a, b) => b.scheduledTime.compareTo(a.scheduledTime));
    }

    // For date ranges that don't include today, just return DB records
    return dbRecords
      ..sort((a, b) => b.scheduledTime.compareTo(a.scheduledTime));
  }

  // Generate today's schedule dynamically from MedicineBox reminders
  List<MedicineRecord> _generateTodayScheduleFromReminders() {
    final now = DateTime.now();
    final today = now.weekday; // 1 = Monday, 7 = Sunday
    final todayDate = DateTime(now.year, now.month, now.day);
    final List<MedicineRecord> todaySchedule = [];

    print('📅 Generating schedule for today (weekday: $today)');
    print('📦 Total medicine boxes: ${_medicineBoxes.length}');

    for (var box in _medicineBoxes) {
      print(
        '  📦 Box: ${box.name} (ID: ${box.id}) - ${box.reminderTimes.length} reminders',
      );
      for (var reminder in box.reminderTimes) {
        // Only include if reminder is enabled and scheduled for today
        if (reminder.isEnabled && reminder.daysOfWeek.contains(today)) {
          final scheduledTime = DateTime(
            now.year,
            now.month,
            now.day,
            reminder.hour,
            reminder.minute,
          );

          print(
            '     ✅ Reminder enabled for today: ${reminder.hour}:${reminder.minute.toString().padLeft(2, '0')} (ID: ${reminder.id})',
          );

          todaySchedule.add(
            MedicineRecord(
              id: 'schedule_${box.id}_${reminder.id}_${todayDate.millisecondsSinceEpoch}',
              medicineBoxId: box.id,
              reminderTimeId: reminder.id,
              scheduledTime: scheduledTime,
              isTaken: false,
              isMissed: false,
            ),
          );
        }
      }
    }

    print('📊 Total scheduled doses for today: ${todaySchedule.length}');

    return todaySchedule
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
  }

  // Get records for today - dynamically generated from reminders and merged with actual DB records
  List<MedicineRecord> getTodayRecords() {
    // Generate today's schedule from reminders
    final todaySchedule = _generateTodayScheduleFromReminders();

    // Merge with actual records from DB (taken/missed)
    final Map<String, MedicineRecord> mergedRecords = {};

    // Add all scheduled doses (from reminders)
    for (var schedule in todaySchedule) {
      final key = '${schedule.medicineBoxId}_${schedule.reminderTimeId}';
      mergedRecords[key] = schedule;
    }

    // Override with actual records from DB (taken or missed)
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    for (var record in _medicineRecords) {
      if (record.scheduledTime.isAfter(
            start.subtract(const Duration(seconds: 1)),
          ) &&
          record.scheduledTime.isBefore(end)) {
        final key = '${record.medicineBoxId}_${record.reminderTimeId}';
        mergedRecords[key] = record; // DB record overrides schedule
      }
    }

    return mergedRecords.values.toList()
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
  }

  // Get statistics for a date range
  MedicineStatistics getStatistics(DateTime start, DateTime end) {
    final records = getRecordsForDateRange(start, end);
    return MedicineStatistics.fromRecords(records);
  }

  // Helper method to parse Firestore date (handles both Timestamp and string formats)
  DateTime _parseFirestoreDate(dynamic value) {
    if (value == null) return DateTime.now();

    // Handle Firestore Timestamp
    if (value is Timestamp) {
      return value.toDate();
    }

    // Handle Map format (from Firestore)
    if (value is Map && value.containsKey('_seconds')) {
      return DateTime.fromMillisecondsSinceEpoch(value['_seconds'] * 1000);
    }

    // Handle String (ISO8601)
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }

    // Try toDate() method (for Timestamp objects)
    try {
      return (value as dynamic).toDate();
    } catch (_) {}

    return DateTime.now();
  }

  // Mark medicine as taken - creates record if it doesn't exist
  Future<void> markAsTaken(
    String recordId, {
    MedicineBox? box,
    ReminderTime? reminder,
  }) async {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    MedicineRecord? record;

    // Try to find existing record in DB
    final index = _medicineRecords.indexWhere((r) => r.id == recordId);
    if (index != -1) {
      record = _medicineRecords[index];
    } else {
      // If record doesn't exist, we need box and reminder to create it
      if (box != null && reminder != null) {
        final scheduledTime = DateTime(
          now.year,
          now.month,
          now.day,
          reminder.hour,
          reminder.minute,
        );
        // Generate proper record ID (not schedule ID)
        final newRecordId =
            'record_${box.id}_${reminder.id}_${todayDate.millisecondsSinceEpoch}';
        record = MedicineRecord(
          id: newRecordId,
          medicineBoxId: box.id,
          reminderTimeId: reminder.id,
          scheduledTime: scheduledTime,
          isTaken: false,
          isMissed: false,
        );
      } else {
        // Try to find from today's schedule by matching recordId or key
        final todayRecords = getTodayRecords();
        final scheduleRecord = todayRecords.firstWhere(
          (r) => r.id == recordId,
          orElse: () =>
              throw Exception('Record not found in today\'s schedule'),
        );
        // Generate proper record ID from schedule record
        final newRecordId =
            'record_${scheduleRecord.medicineBoxId}_${scheduleRecord.reminderTimeId}_${todayDate.millisecondsSinceEpoch}';
        record = scheduleRecord.copyWith(id: newRecordId);
      }
    }

    // At this point, record is guaranteed to be non-null (assigned in all branches)
    final nonNullRecord = record;

    // Do NOT convert a missed record to taken (user/device should not revive missed)
    if (nonNullRecord.isMissed) {
      print(
        '⚠️ markAsTaken ignored: record is already missed (${nonNullRecord.id})',
      );
      return;
    }

    // Create proper record ID if it's a schedule ID
    String finalRecordId = nonNullRecord.id;
    if (finalRecordId.startsWith('schedule_')) {
      finalRecordId =
          'record_${nonNullRecord.medicineBoxId}_${nonNullRecord.reminderTimeId}_${todayDate.millisecondsSinceEpoch}';
    }

    // Create or update record with taken status
    final takenRecord = nonNullRecord.copyWith(
      id: finalRecordId,
      isTaken: true,
      takenTime: now,
      isMissed: false,
    );

    // Update local list
    if (index != -1) {
      _medicineRecords[index] = takenRecord;
    } else {
      // Remove old record if ID changed
      _medicineRecords.removeWhere((r) => r.id == nonNullRecord.id);
      _medicineRecords.add(takenRecord);
    }

    // Save to Firestore - convert dates to Timestamps for proper Firestore format
    try {
      final firestoreData = {
        'id': takenRecord.id,
        'medicineBoxId': takenRecord.medicineBoxId,
        'reminderTimeId': takenRecord.reminderTimeId,
        'scheduledTime': Timestamp.fromDate(takenRecord.scheduledTime),
        'isTaken': takenRecord.isTaken,
        'isMissed': takenRecord.isMissed,
        if (takenRecord.takenTime != null)
          'takenTime': Timestamp.fromDate(takenRecord.takenTime!),
      };
      await _firestore
          .collection('medicineRecords')
          .doc(finalRecordId)
          .set(firestoreData);
      print(
        '✅ Saved taken record to Firestore: $finalRecordId, isTaken: ${takenRecord.isTaken}',
      );

      // Ensure the taken record is in local list (already updated above, but ensure it's there)
      final existingIndex = _medicineRecords.indexWhere(
        (r) => r.id == finalRecordId,
      );
      if (existingIndex != -1) {
        _medicineRecords[existingIndex] = takenRecord;
      } else {
        // Remove any schedule record with same key and add the taken record
        _medicineRecords.removeWhere(
          (r) =>
              r.medicineBoxId == takenRecord.medicineBoxId &&
              r.reminderTimeId == takenRecord.reminderTimeId &&
              r.id.startsWith('schedule_'),
        );
        _medicineRecords.add(takenRecord);
      }

      // Don't reload from Firestore here - it might not have the update yet due to eventual consistency
      // The local record is already updated and fetchTodayRecordsFromDatabase() will merge it
    } catch (e) {
      print('Error saving taken record to Firestore: $e');
      // Even if Firestore fails, keep the local update so UI reflects the change
    }

    // Notify listeners immediately so UI updates
    notifyListeners();
  }

  // Mark medicine as missed
  Future<void> markAsMissed(String recordId) async {
    final index = _medicineRecords.indexWhere((r) => r.id == recordId);
    if (index != -1) {
      final updatedRecord = _medicineRecords[index].copyWith(
        isMissed: true,
        isTaken: false,
      );
      _medicineRecords[index] = updatedRecord;

      // Save to Firestore
      try {
        await _firestore
            .collection('medicineRecords')
            .doc(recordId)
            .set(updatedRecord.toJson());
      } catch (e) {
        print('Error saving missed status to Firestore: $e');
      }

      notifyListeners();
    }
  }

  // Add a new medicine box to Firestore
  Future<void> addMedicineBox(MedicineBox box) async {
    try {
      await _firestore.collection('medicineBox').doc(box.id).set(box.toJson());
      // Local list will be updated by the stream listener
      // No longer generating records automatically - records are generated dynamically

      // Send medicineBox.id to ESP32 if deviceId is set
      if (box.deviceId != null && box.deviceId!.isNotEmpty) {
        _sendMedicineBoxIdToESP32(box.deviceId!, box.id, box.boxNumber);
      }
    } catch (e) {
      _error = 'Failed to add medicine box: $e';
      notifyListeners();
    }
  }

  // Update an existing medicine box in Firestore
  Future<void> updateMedicineBox(String id, MedicineBox updatedBox) async {
    try {
      await _firestore
          .collection('medicineBox')
          .doc(id)
          .update(updatedBox.toJson());
      // Local list will be updated by the stream listener

      // Send medicineBox.id to ESP32 if deviceId is set
      if (updatedBox.deviceId != null && updatedBox.deviceId!.isNotEmpty) {
        _sendMedicineBoxIdToESP32(
          updatedBox.deviceId!,
          updatedBox.id,
          updatedBox.boxNumber,
        );
      }
    } catch (e) {
      _error = 'Failed to update medicine box: $e';
      notifyListeners();
    }
  }

  // Send medicineBox.id to ESP32 device
  Future<void> _sendMedicineBoxIdToESP32(
    String deviceId,
    String medicineBoxId,
    int boxNumber,
  ) async {
    try {
      // Import ESP32Service dynamically to avoid circular dependency
      final esp32Service = ESP32Service();

      // Set IP address from deviceId (deviceId might be IP or device identifier)
      String ip = deviceId;
      if (!ip.startsWith('http://') && !ip.startsWith('https://')) {
        // If it's not a full URL, assume it's an IP address
        if (!ip.contains('.')) {
          // If it's not an IP, try to find it from connected devices
          // For now, just use it as-is
          ip = 'http://$ip';
        } else {
          ip = 'http://$ip';
        }
      }

      esp32Service.setIpAddress(ip);
      final success = await esp32Service.setMedicineBoxId(medicineBoxId);
      if (success) {
        print(
          '✅ Sent medicineBox.id=$medicineBoxId to ESP32 device at $deviceId',
        );
      } else {
        print(
          '⚠️ Failed to send medicineBox.id to ESP32: ${esp32Service.error}',
        );
      }
    } catch (e) {
      print('⚠️ Error sending medicineBox.id to ESP32: $e');
    }
  }

  // Delete a medicine box from Firestore
  Future<void> deleteMedicineBox(String id) async {
    try {
      await _firestore.collection('medicineBox').doc(id).delete();
      // Local list will be updated by the stream listener
    } catch (e) {
      _error = 'Failed to delete medicine box: $e';
      notifyListeners();
    }
  }

  // Add a reminder time to a specific box
  Future<void> addReminderTime(String boxId, ReminderTime reminderTime) async {
    final index = _medicineBoxes.indexWhere((box) => box.id == boxId);
    if (index != -1) {
      final updatedReminders = [
        ..._medicineBoxes[index].reminderTimes,
        reminderTime,
      ];
      final updatedBox = _medicineBoxes[index].copyWith(
        reminderTimes: updatedReminders,
      );

      // Update in Firestore
      await updateMedicineBox(boxId, updatedBox);
      // No longer generating records automatically - records are generated dynamically
    }
  }

  // Update a reminder time
  Future<void> updateReminderTime(
    String boxId,
    String reminderId,
    ReminderTime updatedReminder,
  ) async {
    final boxIndex = _medicineBoxes.indexWhere((box) => box.id == boxId);
    if (boxIndex != -1) {
      final reminderIndex = _medicineBoxes[boxIndex].reminderTimes.indexWhere(
        (r) => r.id == reminderId,
      );
      if (reminderIndex != -1) {
        final updatedReminders = List<ReminderTime>.from(
          _medicineBoxes[boxIndex].reminderTimes,
        );
        updatedReminders[reminderIndex] = updatedReminder;
        final updatedBox = _medicineBoxes[boxIndex].copyWith(
          reminderTimes: updatedReminders,
        );

        // Update in Firestore
        await updateMedicineBox(boxId, updatedBox);
        notifyListeners();
      }
    }
  }

  // Delete a reminder time
  Future<void> deleteReminderTime(String boxId, String reminderId) async {
    final boxIndex = _medicineBoxes.indexWhere((box) => box.id == boxId);
    if (boxIndex != -1) {
      final updatedReminders = _medicineBoxes[boxIndex].reminderTimes
          .where((r) => r.id != reminderId)
          .toList();
      final updatedBox = _medicineBoxes[boxIndex].copyWith(
        reminderTimes: updatedReminders,
      );

      // Update in Firestore
      await updateMedicineBox(boxId, updatedBox);
      notifyListeners();
    }
  }

  // Toggle reminder enabled state
  Future<void> toggleReminderEnabled(String boxId, String reminderId) async {
    final boxIndex = _medicineBoxes.indexWhere((box) => box.id == boxId);
    if (boxIndex != -1) {
      final reminderIndex = _medicineBoxes[boxIndex].reminderTimes.indexWhere(
        (r) => r.id == reminderId,
      );
      if (reminderIndex != -1) {
        final updatedReminders = List<ReminderTime>.from(
          _medicineBoxes[boxIndex].reminderTimes,
        );
        updatedReminders[reminderIndex] = updatedReminders[reminderIndex]
            .copyWith(isEnabled: !updatedReminders[reminderIndex].isEnabled);
        final updatedBox = _medicineBoxes[boxIndex].copyWith(
          reminderTimes: updatedReminders,
        );

        // Update in Firestore
        await updateMedicineBox(boxId, updatedBox);
        notifyListeners();
      }
    }
  }

  // Update days of week for a reminder
  Future<void> updateReminderDaysOfWeek(
    String boxId,
    String reminderId,
    List<int> daysOfWeek,
  ) async {
    final boxIndex = _medicineBoxes.indexWhere((box) => box.id == boxId);
    if (boxIndex != -1) {
      final reminderIndex = _medicineBoxes[boxIndex].reminderTimes.indexWhere(
        (r) => r.id == reminderId,
      );
      if (reminderIndex != -1) {
        final updatedReminders = List<ReminderTime>.from(
          _medicineBoxes[boxIndex].reminderTimes,
        );
        updatedReminders[reminderIndex] = updatedReminders[reminderIndex]
            .copyWith(daysOfWeek: daysOfWeek);
        final updatedBox = _medicineBoxes[boxIndex].copyWith(
          reminderTimes: updatedReminders,
        );

        // Update in Firestore
        await updateMedicineBox(boxId, updatedBox);
        notifyListeners();
      }
    }
  }

  // Load medicine boxes from Firestore with real-time updates
  Future<void> loadMedicineBoxes() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Cancel existing subscription if any
      await _medicineBoxesSubscription?.cancel();

      // Schedule daily check for missed records ONCE (not on every Firestore update)
      if (_dailyMissedCheckTimer == null || !_dailyMissedCheckTimer!.isActive) {
        print('🕐 Initializing daily missed check timer...');
        _scheduleDailyMissedCheck();
      }

      // Listen to real-time updates from Firestore medicineBox collection
      _medicineBoxesSubscription = _firestore
          .collection('medicineBox')
          .snapshots()
          .listen(
            (snapshot) {
              _medicineBoxes = snapshot.docs.map((doc) {
                final data = doc.data();
                return MedicineBox.fromJson(data, docId: doc.id);
              }).toList();

              _isLoading = false;
              _error = null;
              notifyListeners();

              // Load today's records from Firestore to get taken/missed status
              _loadTodayRecordsFromFirestore();

              // Check immediately if any records should be marked as missed (for overdue reminders)
              _checkAndCreateMissedRecords();
            },
            onError: (error) {
              _error = 'Failed to load medicine boxes: $error';
              _isLoading = false;
              notifyListeners();
            },
          );
    } catch (e) {
      _error = 'Error setting up Firestore listener: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load today's records from Firestore and merge with generated records
  Future<void> _loadTodayRecordsFromFirestore() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snapshot = await _firestore
          .collection('medicineRecords')
          .where(
            'scheduledTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('scheduledTime', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      // Store taken records before removing (to preserve them)
      final takenRecordsToPreserve = _medicineRecords
          .where(
            (r) =>
                r.scheduledTime.isAfter(
                  startOfDay.subtract(const Duration(seconds: 1)),
                ) &&
                r.scheduledTime.isBefore(endOfDay) &&
                r.isTaken,
          )
          .toList();

      // Remove all local records for today before merging
      _medicineRecords.removeWhere(
        (r) =>
            r.scheduledTime.isAfter(
              startOfDay.subtract(const Duration(seconds: 1)),
            ) &&
            r.scheduledTime.isBefore(endOfDay),
      );

      // Add Firestore records for today (with proper ID)
      final Map<String, MedicineRecord> firestoreRecordsMap = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id; // Ensure document ID is included

        // Properly parse the record, handling both Timestamp and string formats
        final firestoreRecord = MedicineRecord(
          id: data['id'] ?? doc.id,
          medicineBoxId: data['medicineBoxId'] ?? '',
          reminderTimeId: data['reminderTimeId'] ?? '',
          scheduledTime: _parseFirestoreDate(data['scheduledTime']),
          takenTime: data['takenTime'] != null
              ? _parseFirestoreDate(data['takenTime'])
              : null,
          isTaken: data['isTaken'] == true || data['isTaken'] == 'true',
          isMissed: data['isMissed'] == true || data['isMissed'] == 'true',
        );

        final key =
            '${firestoreRecord.medicineBoxId}_${firestoreRecord.reminderTimeId}';
        firestoreRecordsMap[key] = firestoreRecord;
        _medicineRecords.add(firestoreRecord);
        print(
          '📥 Loaded from Firestore: id=${firestoreRecord.id}, isTaken=${firestoreRecord.isTaken}, key=$key',
        );
      }

      // Preserve taken records that might not be in Firestore yet (due to eventual consistency)
      // Only add if Firestore doesn't have a record for that key, or if Firestore record is not taken
      for (var takenRecord in takenRecordsToPreserve) {
        final key =
            '${takenRecord.medicineBoxId}_${takenRecord.reminderTimeId}';
        final firestoreRecord = firestoreRecordsMap[key];
        if (firestoreRecord == null || !firestoreRecord.isTaken) {
          // Firestore doesn't have this record or it's not marked as taken, preserve local taken record
          if (firestoreRecord != null) {
            // Remove the non-taken Firestore record and add the taken one
            _medicineRecords.removeWhere((r) => r.id == firestoreRecord.id);
          }
          _medicineRecords.add(takenRecord);
          print(
            '💾 Preserved local taken record: id=${takenRecord.id}, isTaken=${takenRecord.isTaken}, key=$key',
          );
        }
      }

      notifyListeners();
    } catch (e) {
      print('Error loading today\'s records from Firestore: $e');
    }
  }

  // Public method to reload today's records (for UI refresh)
  Future<void> reloadTodayRecords() async {
    await _loadTodayRecordsFromFirestore();
  }

  @override
  void dispose() {
    _medicineBoxesSubscription?.cancel();
    _dailyMissedCheckTimer?.cancel();
    super.dispose();
  }

  // Check and create missed records for today (to be called daily at 23:55)
  Future<void> createMissedRecordsForToday() async {
    print('🔍 Starting createMissedRecordsForToday()...');
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    // Get all scheduled doses for today from reminders
    final todaySchedule = _generateTodayScheduleFromReminders();
    print('📅 Today\'s schedule count: ${todaySchedule.length}');

    // Get existing records from DB for today (ONLY actual records, not schedule_ records)
    final existingRecords = await fetchTodayRecordsFromDatabase();
    print('📦 Total merged records from DB: ${existingRecords.length}');

    // Filter to only ACTUAL database records (with record_ prefix, not schedule_)
    final actualDbRecords = existingRecords
        .where((r) => r.id.startsWith('record_'))
        .toList();
    print('📝 Actual DB records (record_*): ${actualDbRecords.length}');

    final existingKeys = actualDbRecords
        .map((r) => '${r.medicineBoxId}_${r.reminderTimeId}')
        .toSet();
    print('🔑 Existing keys: $existingKeys');

    int missedCount = 0;
    // Create missed records for any scheduled doses that weren't taken
    for (var scheduled in todaySchedule) {
      final key = '${scheduled.medicineBoxId}_${scheduled.reminderTimeId}';
      print('   Checking: $key - exists: ${existingKeys.contains(key)}');

      // Only create missed record if no actual record exists in DB (not taken)
      if (!existingKeys.contains(key)) {
        final missedRecordId =
            'record_${scheduled.medicineBoxId}_${scheduled.reminderTimeId}_${todayDate.millisecondsSinceEpoch}';
        final missedRecord = MedicineRecord(
          id: missedRecordId,
          medicineBoxId: scheduled.medicineBoxId,
          reminderTimeId: scheduled.reminderTimeId,
          scheduledTime: scheduled.scheduledTime,
          isTaken: false,
          isMissed: true,
        );

        print('❌ Creating missed record: $missedRecordId');

        // Save to Firestore with proper Timestamp format
        try {
          await _firestore
              .collection('medicineRecords')
              .doc(missedRecord.id)
              .set({
                'medicineBoxId': missedRecord.medicineBoxId,
                'reminderTimeId': missedRecord.reminderTimeId,
                'scheduledTime': Timestamp.fromDate(missedRecord.scheduledTime),
                'isTaken': false,
                'isMissed': true,
              });
          _medicineRecords.add(missedRecord);
          missedCount++;
          print('   ✅ Saved to Firestore successfully');
        } catch (e) {
          print('   ❌ Error creating missed record: $e');
        }
      }
    }

    print('📊 Summary: Created $missedCount missed records');
    notifyListeners();
  }

  // Sync with ESP32 IoT device and update local records
  Future<void> syncWithDevice() async {
    _isLoading = true;
    notifyListeners();

    try {
      final esp32Service = ESP32Service();
      final status = await esp32Service.getStatus();
      // Print the API response in the debug console/terminal
      print(
        '[ESP32 API] /status response: isBoxOpen=${status?.isBoxOpen}, medicineTaken=${status?.medicineTaken}, weightLoss=${status?.weightLoss}',
      );
      if (status != null && status.medicineTaken) {
        // Find today's untaken record and mark as taken
        final todayRecords = getTodayRecords();
        for (final r in todayRecords) {
          if (!r.isTaken) {
            // Find box and reminder for this record
            final box = _medicineBoxes.firstWhere(
              (b) => b.id == r.medicineBoxId,
              orElse: () => throw Exception('Box not found'),
            );
            final reminder = box.reminderTimes.firstWhere(
              (rem) => rem.id == r.reminderTimeId,
              orElse: () => throw Exception('Reminder not found'),
            );
            await markAsTaken(r.id, box: box, reminder: reminder);
          }
        }
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // Check and create missed records for overdue reminders (called on app start and throughout the day)
  Future<void> _checkAndCreateMissedRecords() async {
    try {
      final now = DateTime.now();
      final todayDate = DateTime(now.year, now.month, now.day);

      // Get all scheduled doses for today from reminders
      final todaySchedule = _generateTodayScheduleFromReminders();

      // Get existing records from DB for today
      final existingRecords = await fetchTodayRecordsFromDatabase();
      final existingKeys = existingRecords
          .map((r) => '${r.medicineBoxId}_${r.reminderTimeId}')
          .toSet();

      // Get valid medicine box IDs
      final validBoxIds = _medicineBoxes.map((b) => b.id).toSet();
      print('🔍 Valid medicine box IDs: $validBoxIds');

      // Create missed records for any scheduled doses that are overdue and not taken
      for (var scheduled in todaySchedule) {
        // SAFETY CHECK: Only create if medicine box still exists
        if (!validBoxIds.contains(scheduled.medicineBoxId)) {
          print(
            '⚠️ Skipping missed record - medicine box ${scheduled.medicineBoxId} not found!',
          );
          continue;
        }

        // Only check if the scheduled time has passed
        if (scheduled.scheduledTime.isBefore(now)) {
          final key = '${scheduled.medicineBoxId}_${scheduled.reminderTimeId}';

          // Only create missed record if no record exists (not taken)
          if (!existingKeys.contains(key)) {
            final missedRecord = MedicineRecord(
              id: 'record_${scheduled.medicineBoxId}_${scheduled.reminderTimeId}_${todayDate.millisecondsSinceEpoch}',
              medicineBoxId: scheduled.medicineBoxId,
              reminderTimeId: scheduled.reminderTimeId,
              scheduledTime: scheduled.scheduledTime,
              isTaken: false,
              isMissed: true,
            );

            // Save to Firestore
            try {
              await _firestore
                  .collection('medicineRecords')
                  .doc(missedRecord.id)
                  .set({
                    'medicineBoxId': missedRecord.medicineBoxId,
                    'reminderTimeId': missedRecord.reminderTimeId,
                    'scheduledTime': Timestamp.fromDate(
                      missedRecord.scheduledTime,
                    ),
                    'isTaken': false,
                    'isMissed': true,
                  });
              _medicineRecords.add(missedRecord);
              print(
                '📝 Created missed record for overdue reminder: ${missedRecord.id}',
              );
            } catch (e) {
              print('Error creating missed record: $e');
            }
          }
        }
      }

      notifyListeners();
    } catch (e) {
      print('Error in _checkAndCreateMissedRecords: $e');
    }
  }

  // Schedule daily check for missed records at 23:55
  Timer? _dailyMissedCheckTimer;

  void _scheduleDailyMissedCheck() {
    // Cancel existing timer if any
    _dailyMissedCheckTimer?.cancel();

    final now = DateTime.now();
    print(
      '🕐 Current time: ${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
    );

    // For TESTING: run check in 2 minutes (change to 23:55 for production)
    var targetTime = now.add(const Duration(minutes: 7));
    print('🧪 TEST MODE: Will check for missed records in 7 minutes');

    // For PRODUCTION: run at 23:55 daily
    // Uncomment the following lines for production:
    // final today = DateTime(now.year, now.month, now.day);
    // var targetTime = today.add(const Duration(hours: 23, minutes: 55));
    // if (targetTime.isBefore(now)) {
    //    targetTime = targetTime.add(const Duration(days: 1));
    //   print('⏰ 23:55 already passed today, scheduling for tomorrow');
    // }

    var delay = targetTime.difference(now);

    // Safety check: if delay is negative or zero, add 24 hours and retry
    if (delay.isNegative || delay.inSeconds == 0) {
      print(
        '⚠️ WARNING: Calculated delay is negative! now=$now, targetTime=$targetTime',
      );
      delay = const Duration(hours: 24);
      targetTime = now.add(delay);
    }

    print(
      '⏰ Scheduled missed check in ${delay.inMinutes}m ${delay.inSeconds % 60}s',
    );
    print(
      '⏰ Will run at: ${targetTime.hour}:${targetTime.minute.toString().padLeft(2, '0')}:${targetTime.second.toString().padLeft(2, '0')}',
    );
    print('⏰ Timer ID: ${_dailyMissedCheckTimer.hashCode}');

    _dailyMissedCheckTimer = Timer(delay, () async {
      final runTime = DateTime.now();
      print('⏰ ========================================');
      print(
        '⏰ MISSED CHECK TRIGGERED at ${runTime.hour}:${runTime.minute.toString().padLeft(2, '0')}:${runTime.second.toString().padLeft(2, '0')}',
      );
      print('⏰ ========================================');

      try {
        await createMissedRecordsForToday();
        print('✅ Missed check completed successfully');
      } catch (e) {
        print('❌ Error in missed check: $e');
      }

      // Schedule next day's check
      print('🔄 Rescheduling next missed check...');
      _scheduleDailyMissedCheck();
    });

    print(
      '✅ Timer scheduled successfully. Timer active: ${_dailyMissedCheckTimer?.isActive}',
    );
  }

  // Record medicine taken immediately (called from UI when box closes with medicine taken detected)
  Future<void> recordMedicineTaken({
    double weightLoss = 0.0,
    String? medicineBoxId,
    int? boxNumber,
  }) async {
    try {
      final now = DateTime.now();
      print('📋 recordMedicineTaken() called');
      print(
        '⏰ Current time: ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
      );
      print(
        '📦 Received - medicineBoxId: $medicineBoxId, boxNumber: $boxNumber',
      );

      final todayRecords = await fetchTodayRecordsFromDatabase();
      print('📊 Today\'s records count: ${todayRecords.length}');
      final untakenCount = todayRecords
          .where((r) => !r.isTaken && !r.isMissed)
          .length;
      print('   Untaken count: $untakenCount');
      for (var i = 0; i < todayRecords.length; i++) {
        final record = todayRecords[i];
        print(
          '   [$i] Box: ${record.medicineBoxId}, '
          'Reminder: ${record.reminderTimeId}, '
          'Time: ${record.scheduledTime.hour}:${record.scheduledTime.minute.toString().padLeft(2, '0')}, '
          'Taken: ${record.isTaken}',
        );
      }

      MedicineRecord? untakenRecord;

      // PRIORITY 1: If user recently tapped LED button in app, use that SPECIFIC reminder
      // This takes highest priority regardless of boxNumber matching
      if (_hasValidTappedReminder) {
        print('🎯 User tapped LED in app recently!');
        print('   Saved boxNumber: $_lastTappedBoxNumber');
        print('   Saved reminderTimeId: $_lastTappedReminderTimeId');
        print('   Received boxNumber from Arduino: $boxNumber');
        print(
          '   Time since tap: ${DateTime.now().difference(_lastTappedTime!).inSeconds}s',
        );

        // Find the EXACT reminder that was tapped
        try {
          untakenRecord = todayRecords.firstWhere(
            (r) =>
                r.reminderTimeId == _lastTappedReminderTimeId &&
                !r.isTaken &&
                !r.isMissed,
          );
          print('✅ Found the exact tapped reminder: ${untakenRecord.id}');
          print(
            '   Reminder time: ${untakenRecord.scheduledTime.hour}:${untakenRecord.scheduledTime.minute.toString().padLeft(2, '0')}',
          );
          _clearLastTappedReminder(); // Clear after using it
        } catch (e) {
          print('⚠️ Could not find the tapped reminder in today\'s records');
          print(
            '   Available reminder IDs: ${todayRecords.map((r) => r.reminderTimeId).toSet()}',
          );
          _clearLastTappedReminder();
        }
      }

      // PRIORITY 2: Use boxNumber if provided (from Arduino's blinking LED)
      // boxNumber > 0 means Arduino was blinking an LED (either from app tap or physical button)
      // boxNumber = 0 means no specific LED was active
      if (untakenRecord == null && boxNumber != null && boxNumber > 0) {
        print('💡 Arduino reports LED was blinking - boxNumber=$boxNumber');
        print('   Finding medicine box with boxNumber=$boxNumber...');
        print(
          '   Available boxes: ${_medicineBoxes.map((b) => 'Box${b.boxNumber}(${b.name})').join(', ')}',
        );

        // Find the medicine box that has this boxNumber (from blinking LED)
        final tappedBox = _medicineBoxes.firstWhere(
          (box) => box.boxNumber == boxNumber,
          orElse: () => MedicineBox(
            id: '',
            name: 'Unknown',
            boxNumber: 0,
            reminderTimes: [],
          ),
        );

        if (tappedBox.id.isEmpty) {
          print('❌ ERROR: No medicine box found with boxNumber=$boxNumber!');
          print(
            '   This means Arduino is tracking a box that doesn\'t exist in app.',
          );
          print(
            '   Please check Arduino LED tracking or create a medicine box with boxNumber=$boxNumber',
          );
        } else {
          print(
            '✅ Found tapped box: ${tappedBox.name} (ID: ${tappedBox.id}, boxNumber: ${tappedBox.boxNumber})',
          );

          // Get all reminder IDs for this specific box
          final tappedBoxReminderIds = tappedBox.reminderTimes
              .map((r) => r.id)
              .toSet();

          // Find all untaken records for THIS box
          final untakenForTappedBox = todayRecords
              .where(
                (r) =>
                    r.medicineBoxId == tappedBox.id &&
                    !r.isTaken &&
                    !r.isMissed &&
                    tappedBoxReminderIds.contains(r.reminderTimeId),
              )
              .toList();

          print(
            '   Untaken records for this box: ${untakenForTappedBox.length}',
          );

          if (untakenForTappedBox.isNotEmpty) {
            // Find the nearest reminder (future > recent past)
            final futureReminders = untakenForTappedBox
                .where(
                  (r) =>
                      r.scheduledTime.isAfter(now) ||
                      now.difference(r.scheduledTime).inMinutes < 5,
                )
                .toList();

            if (futureReminders.isNotEmpty) {
              // Prefer future reminders
              futureReminders.sort((a, b) {
                final diffA = (a.scheduledTime.difference(now).inSeconds).abs();
                final diffB = (b.scheduledTime.difference(now).inSeconds).abs();
                return diffA.compareTo(diffB);
              });
              untakenRecord = futureReminders.first;
              print(
                '✅ LED tapped: Found nearest FUTURE reminder at ${untakenRecord!.scheduledTime.hour}:${untakenRecord!.scheduledTime.minute.toString().padLeft(2, '0')}',
              );
            } else {
              // Use closest past reminder
              untakenForTappedBox.sort((a, b) {
                final diffA = (now.difference(a.scheduledTime).inSeconds).abs();
                final diffB = (now.difference(b.scheduledTime).inSeconds).abs();
                return diffA.compareTo(diffB);
              });
              untakenRecord = untakenForTappedBox.first;
              print(
                '✅ LED tapped: Found closest PAST reminder at ${untakenRecord!.scheduledTime.hour}:${untakenRecord!.scheduledTime.minute.toString().padLeft(2, '0')}',
              );
            }
          } else {
            print('⚠️ LED tapped but NO untaken records found for this box!');
          }
        }
      }

      // STEP 2: NO LED tapped (boxNumber = 0) - Find nearest reminder across ALL boxes
      if (untakenRecord == null) {
        print(
          '🔍 NO LED tapped (boxNumber=$boxNumber) - finding nearest reminder across all boxes',
        );
        final untakenRecords = todayRecords
            .where((r) => !r.isTaken && !r.isMissed)
            .toList();
        print('   Total untaken records: ${untakenRecords.length}');

        if (untakenRecords.isNotEmpty) {
          // Separate into future and near-past reminders
          final futureReminders = untakenRecords
              .where(
                (r) =>
                    r.scheduledTime.isAfter(now) ||
                    now.difference(r.scheduledTime).inMinutes < 5,
              )
              .toList();
          final pastReminders = untakenRecords
              .where(
                (r) =>
                    r.scheduledTime.isBefore(now) &&
                    now.difference(r.scheduledTime).inMinutes >= 5,
              )
              .toList();

          print(
            '   Future reminders: ${futureReminders.length}, Past reminders: ${pastReminders.length}',
          );

          if (futureReminders.isNotEmpty) {
            // PREFER future reminders - sort by time difference (smallest first)
            futureReminders.sort((a, b) {
              final diffA = (a.scheduledTime.difference(now).inSeconds).abs();
              final diffB = (b.scheduledTime.difference(now).inSeconds).abs();
              return diffA.compareTo(diffB);
            });
            untakenRecord = futureReminders.first;
            print(
              '✅ No LED: Found nearest FUTURE reminder at ${untakenRecord!.scheduledTime.hour}:${untakenRecord!.scheduledTime.minute.toString().padLeft(2, '0')} in ${(untakenRecord!.scheduledTime.difference(now).inMinutes).abs()} mins',
            );
            print('   ID: ${untakenRecord!.id}');
            print('   Box: ${untakenRecord!.medicineBoxId}');
          } else if (pastReminders.isNotEmpty) {
            // Use closest past reminder
            pastReminders.sort((a, b) {
              final diffA = (now.difference(a.scheduledTime).inSeconds).abs();
              final diffB = (now.difference(b.scheduledTime).inSeconds).abs();
              return diffA.compareTo(diffB);
            });
            untakenRecord = pastReminders.first;
            print(
              '✅ No LED: Found closest PAST reminder at ${untakenRecord!.scheduledTime.hour}:${untakenRecord!.scheduledTime.minute.toString().padLeft(2, '0')} (${(now.difference(untakenRecord!.scheduledTime).inMinutes).abs()} mins ago)',
            );
            print('   ID: ${untakenRecord!.id}');
            print('   Box: ${untakenRecord!.medicineBoxId}');
          }
        } else {
          print('   ⚠️ No untaken records found at all!');
        }
      }

      // STEP 3: If still no record found, create a new one
      if (untakenRecord == null) {
        print('⚠️ No untaken record found - creating new manual record');
        final medicineBox = _medicineBoxes.isNotEmpty
            ? _medicineBoxes.first
            : MedicineBox(
                id: 'default',
                name: 'Default Box',
                boxNumber: 1,
                reminderTimes: [],
              );
        final todayDate = DateTime(now.year, now.month, now.day);

        // Create a new record
        final newRecordId =
            'record_${medicineBox.id}_manual_${todayDate.millisecondsSinceEpoch}';
        final newRecord = MedicineRecord(
          id: newRecordId,
          medicineBoxId: medicineBox.id,
          reminderTimeId: 'manual',
          scheduledTime: todayDate,
          takenTime: now,
          isTaken: true,
          isMissed: false,
        );

        print('✅ Creating manual record: $newRecordId');
        print('   Box ID: ${medicineBox.id}');
        print('   Weight Loss: ${weightLoss}g');

        // Save directly to Firestore
        await _firestore.collection('medicineRecords').doc(newRecordId).set({
          'medicineBoxId': medicineBox.id,
          'reminderTimeId': 'manual',
          'boxNumber': boxNumber ?? 0,
          'scheduledTime': Timestamp.fromDate(todayDate),
          'takenTime': Timestamp.fromDate(now),
          'isTaken': true,
          'isMissed': false,
          'weightLoss': weightLoss,
        });

        // Add to local list
        _medicineRecords.add(newRecord);
        notifyListeners();

        print('✅ Manual medicine record created: $newRecordId');
        return;
      }

      print('📝 Found untaken record to mark: ${untakenRecord.id}');
      print(
        '   Time: ${untakenRecord.scheduledTime.hour}:${untakenRecord.scheduledTime.minute.toString().padLeft(2, '0')}',
      );
      print('   Box: ${untakenRecord.medicineBoxId}');
      print('   Reminder: ${untakenRecord.reminderTimeId}');

      // Mark the existing record as taken
      await markAsTaken(untakenRecord.id);
      print('✅ Medicine recorded as taken: ${untakenRecord.id}');
    } catch (e) {
      print('❌ Error in recordMedicineTaken: $e');
      rethrow;
    }
  }
}
