import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../providers/medicine_box_provider.dart';

class MQTTMedicineListener {
  static final MQTTMedicineListener _instance =
      MQTTMedicineListener._internal();

  factory MQTTMedicineListener() {
    return _instance;
  }

  MQTTMedicineListener._internal();

  late MqttServerClient _client;
  final String _broker = '34.19.178.165';
  final int _port = 1883;
  bool _isConnected = false;
  StreamSubscription? _subscription;
  MedicineBoxProvider? _medicineBoxProvider;

  bool get isConnected => _isConnected;

  /// Initialize MQTT connection and start listening for medicine events
  Future<void> initialize(MedicineBoxProvider medicineBoxProvider) async {
    _medicineBoxProvider = medicineBoxProvider;

    try {
      _client = MqttServerClient(_broker, 'flutter_medicine_listener');
      _client.port = _port;
      _client.keepAlivePeriod = 30;
      _client.logging(on: false);
      _client.onConnected = _onConnected;
      _client.onDisconnected = _onDisconnected;

      print('🔌 MQTT Connecting to $_broker:$_port...');

      await _client.connect();

      if (_client.connectionStatus?.state == MqttConnectionState.connected) {
        _isConnected = true;
        print('✅ MQTT connected successfully');
        _subscribeToMedicineEvents();
      } else {
        print('❌ MQTT connection failed: ${_client.connectionStatus?.state}');
        _isConnected = false;
      }
    } catch (e) {
      print('❌ MQTT connection error: $e');
      _isConnected = false;
    }
  }

  /// Subscribe to all medicine box status messages
  void _subscribeToMedicineEvents() {
    print('📡 Subscribing to medicine status updates...');

    // Subscribe to all medicine box topics: medicinebox/+/status
    _client.subscribe('medicinebox/+/status', MqttQos.atLeastOnce);

    // Listen for messages
    _subscription = _client.updates?.listen((
      List<MqttReceivedMessage<MqttMessage>> c,
    ) {
      for (var message in c) {
        final MqttPublishMessage recMess =
            message.payload as MqttPublishMessage;
        final pt = utf8.decode(recMess.payload.message);

        print('📨 Received MQTT message on ${message.topic}: $pt');

        // Parse the JSON message
        try {
          final data = jsonDecode(pt);
          _handleMedicineStatus(data);
        } catch (e) {
          print('❌ Error parsing MQTT message: $e');
        }
      }
    });
  }

  /// Handle medicine status message from Arduino
  Future<void> _handleMedicineStatus(Map<String, dynamic> data) async {
    final medicineBoxId = data['medicineBoxId'] as String?;
    final taken = data['taken'] == true || data['taken'] == 'true';
    final boxNumber = data['boxNumber'] as int?;
    final weight = data['weight'] as num?;

    print('🔄 Processing medicine status:');
    print('   medicineBoxId: $medicineBoxId');
    print('   taken: $taken');
    print('   boxNumber: $boxNumber');
    print('   weight: $weight');

    // Only record if medicine was taken
    if (taken && medicineBoxId != null && medicineBoxId.isNotEmpty) {
      print('🎯 Medicine taken detected! Creating record...');

      if (_medicineBoxProvider != null) {
        try {
          await _medicineBoxProvider!.recordMedicineTaken(
            weightLoss: (weight ?? 0).toDouble(),
            medicineBoxId: medicineBoxId,
            boxNumber: boxNumber,
          );
          print('✅ Medicine record created from MQTT');
        } catch (e) {
          print('❌ Error creating medicine record: $e');
        }
      } else {
        print('⚠️ MedicineBoxProvider not initialized');
      }
    }
  }

  void _onConnected() {
    print('✅ MQTT onConnected callback');
    _isConnected = true;
  }

  void _onDisconnected() {
    print('❌ MQTT onDisconnected callback');
    _isConnected = false;
    _subscription?.cancel();
  }

  /// Disconnect from MQTT broker
  Future<void> disconnect() async {
    print('🔌 Disconnecting from MQTT...');
    _subscription?.cancel();
    _client.disconnect();
    _isConnected = false;
  }
}
