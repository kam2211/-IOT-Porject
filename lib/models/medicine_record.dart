class MedicineRecord {
  final String id;
  final String medicineBoxId;
  final String reminderTimeId;
  final DateTime scheduledTime;
  final DateTime? takenTime;
  final bool isTaken;
  final bool isMissed;
  final String? name;
  final int? boxNumber;

  MedicineRecord({
    required this.id,
    required this.medicineBoxId,
    required this.reminderTimeId,
    required this.scheduledTime,
    this.takenTime,
    this.isTaken = false,
    this.isMissed = false,
    this.name,
    this.boxNumber,
  });

  MedicineRecord copyWith({
    String? id,
    String? medicineBoxId,
    String? reminderTimeId,
    DateTime? scheduledTime,
    DateTime? takenTime,
    bool? isTaken,
    bool? isMissed,
    String? name,
    int? boxNumber,
  }) {
    return MedicineRecord(
      id: id ?? this.id,
      medicineBoxId: medicineBoxId ?? this.medicineBoxId,
      reminderTimeId: reminderTimeId ?? this.reminderTimeId,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      takenTime: takenTime ?? this.takenTime,
      isTaken: isTaken ?? this.isTaken,
      isMissed: isMissed ?? this.isMissed,
      name: name ?? this.name,
      boxNumber: boxNumber ?? this.boxNumber,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'medicineBoxId': medicineBoxId,
      'reminderTimeId': reminderTimeId,
      'scheduledTime': scheduledTime.toIso8601String(),
      'takenTime': takenTime?.toIso8601String(),
      'isTaken': isTaken,
      'isMissed': isMissed,
      'name': name,
      'boxNumber': boxNumber,
    };
  }

  factory MedicineRecord.fromJson(Map<String, dynamic> json) {
    DateTime parseDateTime(dynamic value) {
      if (value == null) return DateTime.now();

      // Handle Firestore Timestamp
      if (value is Map && value.containsKey('_seconds')) {
        return DateTime.fromMillisecondsSinceEpoch(value['_seconds'] * 1000);
      }

      // Handle Timestamp object directly
      try {
        return (value as dynamic).toDate();
      } catch (_) {}

      // Handle String (ISO8601)
      if (value is String) {
        return DateTime.parse(value);
      }

      return DateTime.now();
    }

    return MedicineRecord(
      id: json['id'] ?? '',
      medicineBoxId: json['medicineBoxId'] ?? '',
      reminderTimeId: json['reminderTimeId'] ?? '',
      scheduledTime: parseDateTime(json['scheduledTime']),
      takenTime: json['takenTime'] != null
          ? parseDateTime(json['takenTime'])
          : null,
      isTaken: json['isTaken'] == true,
      isMissed: json['isMissed'] == true,
      name: json['name'] as String?,
      boxNumber: json['boxNumber'] as int?,
    );
  }

  bool get isScheduledForToday {
    final now = DateTime.now();
    return scheduledTime.year == now.year &&
        scheduledTime.month == now.month &&
        scheduledTime.day == now.day;
  }

  bool get isOverdue {
    return !isTaken &&
        DateTime.now().isAfter(scheduledTime.add(const Duration(hours: 1)));
  }

  // Check if the scheduled time hasn't arrived yet or is still within grace period (pending)
  // A medication is pending if:
  // 1. It's scheduled for the future, OR
  // 2. It's scheduled for today, not taken, and not explicitly marked as missed
  // This allows a grace period - medications are only marked as missed at end of day (23:55)
  bool get isPending {
    return isFuturePending || isOverduePending;
  }

  // Check if scheduled for future (not yet arrived)
  bool get isFuturePending {
    if (isTaken || isMissed) return false;
    return scheduledTime.isAfter(DateTime.now());
  }

  // Check if overdue but still pending (past scheduled time but not yet marked as missed)
  // This is for medications scheduled for today that are past their time but still within grace period
  // Only marks as overdue after 5 minutes past scheduled time (gives user time to take medicine)
  bool get isOverduePending {
    if (isTaken || isMissed) return false;

    final now = DateTime.now();
    final scheduledDate = DateTime(
      scheduledTime.year,
      scheduledTime.month,
      scheduledTime.day,
    );
    final today = DateTime(now.year, now.month, now.day);

    // Must be scheduled for today
    if (!scheduledDate.isAtSameMomentAs(today)) return false;

    // Only mark as overdue if 5 minutes have passed since scheduled time
    final fiveMinutesAfter = scheduledTime.add(const Duration(minutes: 5));
    return now.isAfter(fiveMinutesAfter);
  }
}

class MedicineStatistics {
  final int totalDoses;
  final int takenDoses;
  final int missedDoses;
  final int pendingDoses;
  final int overduePendingDoses;
  final int futurePendingDoses;
  final double adherenceRate;

  MedicineStatistics({
    required this.totalDoses,
    required this.takenDoses,
    required this.missedDoses,
    required this.pendingDoses,
    required this.overduePendingDoses,
    required this.futurePendingDoses,
  }) : adherenceRate = totalDoses > 0 ? (takenDoses / totalDoses * 100) : 0;

  factory MedicineStatistics.fromRecords(List<MedicineRecord> records) {
    final total = records.length;
    final taken = records.where((r) => r.isTaken).length;
    final missed = records.where((r) => r.isMissed).length;
    final pending = records.where((r) => r.isPending).length;
    final overduePending = records.where((r) => r.isOverduePending).length;
    final futurePending = records.where((r) => r.isFuturePending).length;

    return MedicineStatistics(
      totalDoses: total,
      takenDoses: taken,
      missedDoses: missed,
      pendingDoses: pending,
      overduePendingDoses: overduePending,
      futurePendingDoses: futurePending,
    );
  }
}
