import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreDeviceService {
  final _db = FirebaseFirestore.instance;

  Future<void> addDevice({
    required String deviceId,
    required String name,
    required String ip,
  }) async {
    await _db.collection('devices').doc(deviceId).set({
      'name': name,
      'ip': ip,
      'connectedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addReminder({
    required String deviceId,
    required String medicineName,
    required int hour,
    required int minute,
    required List<int> daysOfWeek,
    bool isEnabled = true,
  }) async {
    await _db.collection('devices').doc(deviceId).collection('reminders').add({
      'medicineName': medicineName,
      'hour': hour,
      'minute': minute,
      'daysOfWeek': daysOfWeek,
      'isEnabled': isEnabled,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Example: fetch all reminders for a device
  Stream<QuerySnapshot> remindersStream(String deviceId) {
    return _db
        .collection('devices')
        .doc(deviceId)
        .collection('reminders')
        .snapshots();
  }

  // Fetch all devices from Firestore
  Future<List<Map<String, dynamic>>> fetchAllDevices() async {
    try {
      final snapshot = await _db.collection('devices').get();
      return snapshot.docs.map((doc) {
        return {
          'ip': doc['ip'] as String? ?? '',
          'name': doc['name'] as String? ?? 'Medicine Box',
          'version': doc['version'] as String? ?? '1.0',
        };
      }).toList();
    } catch (e) {
      print('Error fetching devices from Firestore: $e');
      return [];
    }
  }
}
