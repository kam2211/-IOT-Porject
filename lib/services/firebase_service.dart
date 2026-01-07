import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/medicine_box.dart';
import '../models/medicine_record.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references
  CollectionReference get _medicineBoxesCollection =>
      _firestore.collection('medicine_boxes');

  CollectionReference get _medicineRecordsCollection =>
      _firestore.collection('medicine_records');

  // ==================== MEDICINE BOXES ====================

  // Get all medicine boxes
  Stream<List<MedicineBox>> getMedicineBoxesStream() {
    return _medicineBoxesCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => _medicineBoxFromFirestore(doc))
              .toList(),
        );
  }

  // Get all medicine boxes (one-time)
  Future<List<MedicineBox>> getMedicineBoxes() async {
    final snapshot = await _medicineBoxesCollection
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map((doc) => _medicineBoxFromFirestore(doc)).toList();
  }

  // Add a new medicine box
  Future<String> addMedicineBox(MedicineBox box) async {
    final docRef = await _medicineBoxesCollection.add(
      _medicineBoxToFirestore(box),
    );
    return docRef.id;
  }

  // Update a medicine box
  Future<void> updateMedicineBox(String id, MedicineBox box) async {
    await _medicineBoxesCollection.doc(id).update(_medicineBoxToFirestore(box));
  }

  // Delete a medicine box
  Future<void> deleteMedicineBox(String id) async {
    await _medicineBoxesCollection.doc(id).delete();
    // Also delete associated records
    final records = await _medicineRecordsCollection
        .where('medicineBoxId', isEqualTo: id)
        .get();
    for (var doc in records.docs) {
      await doc.reference.delete();
    }
  }

  // ==================== MEDICINE RECORDS ====================

  // Get records for a date range
  Stream<List<MedicineRecord>> getRecordsStream(DateTime start, DateTime end) {
    return _medicineRecordsCollection
        .where(
          'scheduledTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
        )
        .where('scheduledTime', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('scheduledTime', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => _medicineRecordFromFirestore(doc))
              .toList(),
        );
  }

  // Get records (one-time)
  Future<List<MedicineRecord>> getRecords(DateTime start, DateTime end) async {
    final snapshot = await _medicineRecordsCollection
        .where(
          'scheduledTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
        )
        .where('scheduledTime', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('scheduledTime', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => _medicineRecordFromFirestore(doc))
        .toList();
  }

  // Add a medicine record
  Future<String> addMedicineRecord(MedicineRecord record) async {
    final docRef = await _medicineRecordsCollection.add(
      _medicineRecordToFirestore(record),
    );
    return docRef.id;
  }

  // Update a medicine record (mark as taken/missed)
  Future<void> updateMedicineRecord(String id, MedicineRecord record) async {
    await _medicineRecordsCollection
        .doc(id)
        .update(_medicineRecordToFirestore(record));
  }

  // Mark medicine as taken
  Future<void> markAsTaken(String recordId) async {
    await _medicineRecordsCollection.doc(recordId).update({
      'isTaken': true,
      'isMissed': false,
      'takenTime': Timestamp.now(),
    });
  }

  // Mark medicine as missed
  Future<void> markAsMissed(String recordId) async {
    await _medicineRecordsCollection.doc(recordId).update({
      'isMissed': true,
      'isTaken': false,
    });
  }

  // ==================== CONVERTERS ====================

  // Convert Firestore document to MedicineBox
  MedicineBox _medicineBoxFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MedicineBox(
      id: doc.id,
      name: data['name'] ?? '',
      boxNumber: data['boxNumber'] ?? 1,
      reminderTimes:
          (data['reminderTimes'] as List<dynamic>?)
              ?.map(
                (r) => ReminderTime(
                  id: r['id'] ?? '',
                  hour: r['hour'] ?? 0,
                  minute: r['minute'] ?? 0,
                  daysOfWeek: List<int>.from(
                    r['daysOfWeek'] ?? [1, 2, 3, 4, 5, 6, 7],
                  ),
                  isEnabled: r['isEnabled'] ?? true,
                ),
              )
              .toList() ??
          [],
      isConnected: data['isConnected'] ?? false,
      deviceId: data['deviceId'],
    );
  }

  // Convert MedicineBox to Firestore map
  Map<String, dynamic> _medicineBoxToFirestore(MedicineBox box) {
    return {
      'name': box.name,
      'boxNumber': box.boxNumber,
      'reminderTimes': box.reminderTimes
          .map(
            (r) => {
              'id': r.id,
              'hour': r.hour,
              'minute': r.minute,
              'daysOfWeek': r.daysOfWeek,
              'isEnabled': r.isEnabled,
            },
          )
          .toList(),
      'isConnected': box.isConnected,
      'deviceId': box.deviceId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  // Convert Firestore document to MedicineRecord
  MedicineRecord _medicineRecordFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MedicineRecord(
      id: doc.id,
      medicineBoxId: data['medicineBoxId'] ?? '',
      reminderTimeId: data['reminderTimeId'] ?? '',
      scheduledTime: (data['scheduledTime'] as Timestamp).toDate(),
      isTaken: data['isTaken'] ?? false,
      isMissed: data['isMissed'] ?? false,
      takenTime: data['takenTime'] != null
          ? (data['takenTime'] as Timestamp).toDate()
          : null,
    );
  }

  // Convert MedicineRecord to Firestore map
  Map<String, dynamic> _medicineRecordToFirestore(MedicineRecord record) {
    return {
      'medicineBoxId': record.medicineBoxId,
      'reminderTimeId': record.reminderTimeId,
      'scheduledTime': Timestamp.fromDate(record.scheduledTime),
      'isTaken': record.isTaken,
      'isMissed': record.isMissed,
      'takenTime': record.takenTime != null
          ? Timestamp.fromDate(record.takenTime!)
          : null,
    };
  }
}
