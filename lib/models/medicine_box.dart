class Compartment {
  final double? weight;
  final bool? taken;
  final DateTime? lastTaken;

  Compartment({this.weight, this.taken, this.lastTaken});

  Map<String, dynamic> toJson() {
    return {
      'weight': weight,
      'taken': taken,
      'lastTaken': lastTaken?.toIso8601String(),
    };
  }

  factory Compartment.fromJson(Map<String, dynamic> json) {
    DateTime? parseLastTaken() {
      if (json['lastTaken'] == null) return null;

      // Handle Firestore Timestamp
      if (json['lastTaken'] is Map) {
        return (json['lastTaken'] as dynamic).toDate();
      }

      // Handle String (ISO8601)
      if (json['lastTaken'] is String) {
        return DateTime.parse(json['lastTaken']);
      }

      // Handle Timestamp object directly
      return (json['lastTaken'] as dynamic).toDate();
    }

    return Compartment(
      weight: json['weight']?.toDouble(),
      taken: json['taken'] as bool?,
      lastTaken: parseLastTaken(),
    );
  }
}

class MedicineBox {
  final String id;
  final String name;
  final int boxNumber;
  final List<ReminderTime> reminderTimes;
  final bool isConnected;
  final String? deviceId;
  final Map<String, Compartment>? compartments;
  final DateTime? lastUpdated;

  MedicineBox({
    required this.id,
    required this.name,
    required this.boxNumber,
    required this.reminderTimes,
    this.isConnected = false,
    this.deviceId,
    this.compartments,
    this.lastUpdated,
  });

  MedicineBox copyWith({
    String? id,
    String? name,
    int? boxNumber,
    List<ReminderTime>? reminderTimes,
    bool? isConnected,
    String? deviceId,
    Map<String, Compartment>? compartments,
    DateTime? lastUpdated,
  }) {
    return MedicineBox(
      id: id ?? this.id,
      name: name ?? this.name,
      boxNumber: boxNumber ?? this.boxNumber,
      reminderTimes: reminderTimes ?? this.reminderTimes,
      isConnected: isConnected ?? this.isConnected,
      deviceId: deviceId ?? this.deviceId,
      compartments: compartments ?? this.compartments,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'boxNumber': boxNumber,
      'reminderTimes': reminderTimes.map((r) => r.toJson()).toList(),
      'isConnected': isConnected,
      'deviceId': deviceId,
      'compartments': compartments?.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'lastUpdated': lastUpdated?.toIso8601String(),
    };
  }

  factory MedicineBox.fromJson(Map<String, dynamic> json, {String? docId}) {
    Map<String, Compartment>? compartmentsMap;
    if (json['compartments'] != null) {
      compartmentsMap = (json['compartments'] as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(key, Compartment.fromJson(value as Map<String, dynamic>)),
      );
    }

    return MedicineBox(
      id: docId ?? json['id'],
      name: json['name'] ?? 'Medicine Box',
      boxNumber: json['boxNumber'] ?? 1,
      reminderTimes: json['reminderTimes'] != null
          ? (json['reminderTimes'] as List)
                .map((r) => ReminderTime.fromJson(r))
                .toList()
          : [],
      isConnected: json['isConnected'] ?? false,
      deviceId: json['deviceId'] ?? '',
      compartments: compartmentsMap,
      lastUpdated: json['lastUpdated'] != null
          ? (json['lastUpdated'] is String
                ? DateTime.parse(json['lastUpdated'])
                : (json['lastUpdated'] as dynamic).toDate())
          : null,
    );
  }
}

class ReminderTime {
  final String id;
  final int hour;
  final int minute;
  final bool isEnabled;
  final List<int> daysOfWeek; // 1-7 (Monday-Sunday)

  ReminderTime({
    required this.id,
    required this.hour,
    required this.minute,
    this.isEnabled = true,
    this.daysOfWeek = const [1, 2, 3, 4, 5, 6, 7],
  });

  ReminderTime copyWith({
    String? id,
    int? hour,
    int? minute,
    bool? isEnabled,
    List<int>? daysOfWeek,
  }) {
    return ReminderTime(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      isEnabled: isEnabled ?? this.isEnabled,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
    );
  }

  String get formattedTime {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hour': hour,
      'minute': minute,
      'isEnabled': isEnabled,
      'daysOfWeek': daysOfWeek,
    };
  }

  factory ReminderTime.fromJson(Map<String, dynamic> json) {
    return ReminderTime(
      id: json['id'],
      hour: json['hour'],
      minute: json['minute'],
      isEnabled: json['isEnabled'] ?? true,
      daysOfWeek: List<int>.from(json['daysOfWeek'] ?? [1, 2, 3, 4, 5, 6, 7]),
    );
  }
}
