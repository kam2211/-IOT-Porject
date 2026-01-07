import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../providers/medicine_box_provider.dart';
import '../models/medicine_box.dart';

class MQTTService extends ChangeNotifier {
  MqttServerClient? _client;
  bool _isConnected = false;
  String? _error;
  final MedicineBoxProvider _medicineBoxProvider;

  // MQTT Configuration
  final String _mqttServer = '34.19.178.165';
  final int _mqttPort = 1883;
  final String _clientId =
      'flutter_app_${DateTime.now().millisecondsSinceEpoch}';

  MQTTService(this._medicineBoxProvider);

  bool get isConnected => _isConnected;
  String? get error => _error;

  // Connect to MQTT broker and subscribe to all medicine box topics
  Future<bool> connect() async {
    try {
      _client = MqttServerClient(_mqttServer, _clientId);
      _client!.port = _mqttPort;
      _client!.logging(on: false);
      _client!.keepAlivePeriod = 20;
      _client!.onDisconnected = _onDisconnected;
      _client!.onConnected = _onConnected;
      _client!.onSubscribed = _onSubscribed;

      // Set up message callback
      _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        final recMess = c![0].payload as MqttPublishMessage;
        final message = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );
        _handleMessage(c[0].topic, message);
      });

      // Connect
      _error = null;
      notifyListeners();

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(_clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
      _client!.connectionMessage = connMessage;

      print('🔌 Connecting to MQTT broker at $_mqttServer:$_mqttPort...');
      await _client!.connect();

      if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
        print('✅ MQTT Connected');
        _isConnected = true;
        _error = null;

        // Subscribe to all medicine box status topics
        _subscribeToTopics();

        notifyListeners();
        return true;
      } else {
        _error = 'Failed to connect: ${_client!.connectionStatus}';
        _isConnected = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'MQTT connection error: $e';
      _isConnected = false;
      print('❌ MQTT Error: $_error');
      notifyListeners();
      return false;
    }
  }

  // Subscribe to all medicine box status topics
  void _subscribeToTopics() {
    // Subscribe to all medicine box status topics: medicinebox/+/status
    // The + wildcard matches any boxId
    const topic = 'medicinebox/+/status';
    _client!.subscribe(topic, MqttQos.atLeastOnce);
    print('📡 Subscribed to MQTT topic: $topic');
  }

  // Handle incoming MQTT messages
  void _handleMessage(String topic, String message) {
    print('📥 MQTT Message received on topic: $topic');
    print('   Payload: $message');

    try {
      final data = json.decode(message) as Map<String, dynamic>;
      final boxId = data['boxId'] as String?;
      final compartment = data['compartment'] as String?;
      final taken = data['taken'] as bool?;

      if (boxId == null || compartment == null) {
        print('⚠️ Missing boxId or compartment in MQTT message');
        return;
      }

      // Only process if medicine was taken
      if (taken != true) {
        print('ℹ️ Medicine not taken, ignoring message');
        return;
      }

      // Extract box number from compartment (e.g., "box1" -> 1)
      final boxNumberMatch = RegExp(r'box(\d+)').firstMatch(compartment);
      if (boxNumberMatch == null) {
        print('⚠️ Invalid compartment format: $compartment');
        return;
      }
      final boxNumber = int.tryParse(boxNumberMatch.group(1)!);
      if (boxNumber == null || boxNumber < 1 || boxNumber > 7) {
        print('⚠️ Invalid box number: $boxNumber');
        return;
      }

      print(
        '💊 Processing MQTT message: boxId=$boxId, compartment=$compartment, boxNumber=$boxNumber',
      );

      // Find medicine box by medicineBox.id (boxId from MQTT) and boxNumber
      // Note: boxId in MQTT is the medicineBox.id from database
      _processMedicineTaken(boxId, boxNumber);
    } catch (e) {
      print('❌ Error parsing MQTT message: $e');
    }
  }

  // Process medicine taken event
  Future<void> _processMedicineTaken(String mqttBoxId, int boxNumber) async {
    try {
      // Find medicine box that matches the medicineBox.id (boxId from MQTT) and boxNumber
      // The mqttBoxId should be the medicineBox.id from the database
      final boxes = _medicineBoxProvider.medicineBoxes;
      final matchingBox = boxes.firstWhere(
        (box) => box.id == mqttBoxId && box.boxNumber == boxNumber,
        orElse: () => MedicineBox(
          id: '',
          name: 'Unknown',
          boxNumber: 0,
          reminderTimes: [],
        ),
      );

      if (matchingBox.id.isEmpty) {
        print(
          '⚠️ No medicine box found for medicineBox.id=$mqttBoxId, boxNumber=$boxNumber',
        );
        print('   Available boxes:');
        for (var box in boxes) {
          print(
            '     - ${box.name}: id=${box.id}, deviceId=${box.deviceId}, boxNumber=${box.boxNumber}',
          );
        }
        // Try to find by medicineBox.id only (ignore boxNumber mismatch)
        // This handles cases where compartment number is wrong in MQTT
        final boxById = boxes.firstWhere(
          (box) => box.id == mqttBoxId,
          orElse: () => MedicineBox(
            id: '',
            name: 'Unknown',
            boxNumber: 0,
            reminderTimes: [],
          ),
        );
        if (boxById.id.isNotEmpty) {
          print('   ✅ Found box by ID only (ignoring boxNumber mismatch)');
          print(
            '      MQTT compartment: box$boxNumber, but box has boxNumber=${boxById.boxNumber}',
          );
          // Process with the found box (use its actual boxNumber)
          await _processMedicineTakenWithBox(boxById);
          return;
        }
        return;
      }

      print(
        '✅ Found matching medicine box: ${matchingBox.name} (ID: ${matchingBox.id})',
      );

      // Get today's records for this box
      final todayRecords = _medicineBoxProvider.getTodayRecords();
      final boxRecords = todayRecords
          .where((r) => r.medicineBoxId == matchingBox.id && !r.isTaken)
          .toList();

      if (boxRecords.isEmpty) {
        print('⚠️ No untaken records found for ${matchingBox.name} today');
        return;
      }

      // Mark the first untaken record as taken
      // If there are multiple reminders, we'll mark the one that matches the compartment
      final recordToMark = boxRecords.first;

      // Find the reminder for this record
      final reminder = matchingBox.reminderTimes.firstWhere(
        (r) => r.id == recordToMark.reminderTimeId,
        orElse: () => matchingBox.reminderTimes.first,
      );

      print('📝 Marking record as taken: ${recordToMark.id}');
      await _medicineBoxProvider.markAsTaken(
        recordToMark.id,
        box: matchingBox,
        reminder: reminder,
      );

      print('✅ Successfully marked medicine as taken via MQTT');
    } catch (e) {
      print('❌ Error processing medicine taken: $e');
    }
  }

  // Process medicine taken with a specific box (used when boxNumber mismatch)
  Future<void> _processMedicineTakenWithBox(MedicineBox matchingBox) async {
    try {
      print(
        '✅ Found matching medicine box: ${matchingBox.name} (ID: ${matchingBox.id})',
      );
      print('   Note: Using box\'s actual boxNumber=${matchingBox.boxNumber}');

      // Get today's records for this box
      final todayRecords = _medicineBoxProvider.getTodayRecords();
      final boxRecords = todayRecords
          .where((r) => r.medicineBoxId == matchingBox.id && !r.isTaken)
          .toList();

      if (boxRecords.isEmpty) {
        print('⚠️ No untaken records found for ${matchingBox.name} today');
        return;
      }

      // Mark the first untaken record as taken
      final recordToMark = boxRecords.first;

      // Find the reminder for this record
      final reminder = matchingBox.reminderTimes.firstWhere(
        (r) => r.id == recordToMark.reminderTimeId,
        orElse: () => matchingBox.reminderTimes.first,
      );

      print('📝 Marking record as taken: ${recordToMark.id}');
      await _medicineBoxProvider.markAsTaken(
        recordToMark.id,
        box: matchingBox,
        reminder: reminder,
      );

      print('✅ Successfully marked medicine as taken via MQTT');
    } catch (e) {
      print('❌ Error processing medicine taken: $e');
    }
  }

  void _onConnected() {
    print('✅ MQTT Connected');
    _isConnected = true;
    _error = null;
    notifyListeners();
  }

  void _onDisconnected() {
    print('⚠️ MQTT Disconnected');
    _isConnected = false;
    notifyListeners();
  }

  void _onSubscribed(String topic) {
    print('✅ Subscribed to topic: $topic');
  }

  // Disconnect from MQTT
  void disconnect() {
    _client?.disconnect();
    _isConnected = false;
    _client = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
