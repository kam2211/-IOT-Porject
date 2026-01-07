import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'firestore_device_service.dart';

class ESP32Status {
  final bool isBoxOpen;
  final bool medicineTaken;
  final double weightLoss;

  ESP32Status({
    required this.isBoxOpen,
    required this.medicineTaken,
    required this.weightLoss,
  });

  factory ESP32Status.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true';
      return false;
    }

    return ESP32Status(
      isBoxOpen: parseBool(json['isBoxOpen']),
      medicineTaken: parseBool(json['medicineTaken']),
      weightLoss: (json['weightLoss'] ?? 0).toDouble(),
    );
  }
}

// Represents a connected medicine box device
class ConnectedDevice {
  final String ip;
  String name;
  final String version;
  bool isActive;
  ESP32Status? lastStatus;

  ConnectedDevice({
    required this.ip,
    required this.name,
    this.version = '1.0',
    this.isActive = false,
    this.lastStatus,
  });

  Map<String, dynamic> toJson() => {'ip': ip, 'name': name, 'version': version};

  factory ConnectedDevice.fromJson(Map<String, dynamic> json) =>
      ConnectedDevice(
        ip: json['ip'] ?? '',
        name: json['name'] ?? 'Medicine Box',
        version: json['version'] ?? '1.0',
      );
}

class ESP32Service extends ChangeNotifier {
  String? _ipAddress;
  bool _isConnected = false;
  ESP32Status? _lastStatus;
  String? _error;
  Timer? _pollingTimer;

  // Multiple device support
  final List<ConnectedDevice> _connectedDevices = [];
  ConnectedDevice? _activeDevice;
  String? _currentDeviceName;

  // Getters
  String? get ipAddress => _ipAddress;
  bool get isConnected => _isConnected;
  ESP32Status? get lastStatus => _lastStatus;
  String? get error => _error;
  List<ConnectedDevice> get connectedDevices =>
      List.unmodifiable(_connectedDevices);
  ConnectedDevice? get activeDevice => _activeDevice;
  String? get currentDeviceName => _currentDeviceName ?? _activeDevice?.name;

  // Set the ESP32 IP address (get this from Serial Monitor)
  void setIpAddress(String ip, {String? deviceName}) {
    _ipAddress = ip.trim();
    if (!_ipAddress!.startsWith('http://')) {
      _ipAddress = 'http://$_ipAddress';
    }
    _currentDeviceName = deviceName;
    notifyListeners();
  }

  // Add a new device with custom name
  void addDevice(String ip, String name, {String version = '1.0'}) {
    // Check if device already exists
    final existingIndex = _connectedDevices.indexWhere((d) => d.ip == ip);
    if (existingIndex >= 0) {
      // Update existing device name
      _connectedDevices[existingIndex].name = name;
    } else {
      // Add new device
      _connectedDevices.add(
        ConnectedDevice(ip: ip, name: name, version: version),
      );
      // Push to Firestore
      FirestoreDeviceService().addDevice(
        deviceId: ip.replaceAll('.', '_'), // Use IP as ID
        name: name,
        ip: ip,
      );
    }
    notifyListeners();
  }

  // Set active device by IP
  void setActiveDevice(String ip) {
    for (var device in _connectedDevices) {
      device.isActive = device.ip == ip;
      if (device.isActive) {
        _activeDevice = device;
        _currentDeviceName = device.name;
        setIpAddress(ip, deviceName: device.name);
      }
    }
    notifyListeners();
  }

  // Rename a device
  void renameDevice(String ip, String newName) {
    final device = _connectedDevices.firstWhere(
      (d) => d.ip == ip,
      orElse: () => ConnectedDevice(ip: '', name: ''),
    );
    if (device.ip.isNotEmpty) {
      device.name = newName;
      if (_activeDevice?.ip == ip) {
        _currentDeviceName = newName;
      }
      notifyListeners();
    }
  }

  // Remove a device
  void removeDevice(String ip) {
    _connectedDevices.removeWhere((d) => d.ip == ip);
    if (_activeDevice?.ip == ip) {
      _activeDevice = null;
      _currentDeviceName = null;
      _isConnected = false;
    }
    notifyListeners();
  }

  // Base URL for API calls
  String get _baseUrl => _ipAddress ?? '';

  // Test connection to ESP32
  Future<bool> testConnection() async {
    if (_ipAddress == null || _ipAddress!.isEmpty) {
      _error = 'IP address not set';
      _isConnected = false;
      notifyListeners();
      return false;
    }

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _isConnected = true;
        _error = null;
        _lastStatus = ESP32Status.fromJson(json.decode(response.body));

        // Update active device status
        if (_activeDevice != null) {
          _activeDevice!.lastStatus = _lastStatus;
        }

        notifyListeners();
        return true;
      } else {
        _isConnected = false;
        _error = 'Connection failed: ${response.statusCode}';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isConnected = false;
      _error = 'Connection error: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Get current status from ESP32
  Future<ESP32Status?> getStatus() async {
    if (!_isConnected && _ipAddress != null) {
      await testConnection();
    }

    if (_ipAddress == null || _ipAddress!.isEmpty) {
      _error = 'IP address not set';
      return null;
    }

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _lastStatus = ESP32Status.fromJson(json.decode(response.body));
        _error = null;
        notifyListeners();
        return _lastStatus;
      } else {
        _error = 'Failed to get status';
        return null;
      }
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      _isConnected = false;
      notifyListeners();
      return null;
    }
  }

  // Open the medicine box remotely
  Future<bool> openBox({int boxNumber = 1}) async {
    if (_ipAddress == null || _ipAddress!.isEmpty) {
      _error = 'IP address not set';
      notifyListeners();
      return false;
    }

    try {
      final url = '$_baseUrl/open?box=$boxNumber';
      print('📡 Opening box $boxNumber via: $url');
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _error = null;
          await getStatus(); // Refresh status
          return true;
        }
      }
      _error = 'Failed to open box';
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Close the medicine box remotely
  Future<Map<String, dynamic>?> closeBox() async {
    if (_ipAddress == null || _ipAddress!.isEmpty) {
      _error = 'IP address not set';
      notifyListeners();
      return null;
    }

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/close'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _error = null;
          await getStatus(); // Refresh status
          return data;
        }
      }
      _error = 'Failed to close box';
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  // Reset medicine taken status
  Future<bool> resetStatus() async {
    if (_ipAddress == null || _ipAddress!.isEmpty) {
      _error = 'IP address not set';
      notifyListeners();
      return false;
    }

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/reset'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _error = null;
        await getStatus(); // Refresh status
        return true;
      }
      _error = 'Failed to reset';
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Trigger buzzer for reminder (beeps X times)
  Future<bool> triggerBuzzer({int times = 3}) async {
    if (_ipAddress == null || _ipAddress!.isEmpty) {
      _error = 'IP address not set';
      notifyListeners();
      return false;
    }

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/buzzer?times=$times'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _error = null;
        return true;
      }
      _error = 'Failed to trigger buzzer';
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Start continuous alarm
  Future<bool> startAlarm() async {
    if (_ipAddress == null || _ipAddress!.isEmpty) {
      return false;
    }

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/startalarm'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Stop buzzer/alarm
  Future<bool> stopBuzzer() async {
    if (_ipAddress == null || _ipAddress!.isEmpty) {
      return false;
    }

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/stopbuzzer'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Set medicineBox.id on ESP32 device
  Future<bool> setMedicineBoxId(String medicineBoxId) async {
    if (_ipAddress == null || _ipAddress!.isEmpty) {
      _error = 'IP address not set';
      notifyListeners();
      return false;
    }

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/setmedicineboxid?id=$medicineBoxId'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _error = null;
        print('[ESP32Service] ✅ MedicineBox ID set: $medicineBoxId');
        return true;
      }
      _error =
          'Failed to set MedicineBox ID. Status code: ${response.statusCode}';
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Trigger reminder for specific box (1-7)
  Future<bool> triggerReminder(int boxNumber) async {
    if (_ipAddress == null || _ipAddress!.isEmpty) {
      _error = 'IP address not set';
      notifyListeners();
      return false;
    }

    if (boxNumber < 1 || boxNumber > 7) {
      _error = 'Invalid box number. Must be between 1 and 7';
      notifyListeners();
      return false;
    }

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/reminder?box=$boxNumber'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _error = null;
        print('[ESP32Service] ✅ Reminder triggered for Box $boxNumber');
        return true;
      }
      _error =
          'Failed to trigger reminder. Status code: ${response.statusCode}';
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Control LED for specific pill box (1-7)
  Future<bool> setBoxLED(int boxNumber, bool state) async {
    print('[ESP32Service] setBoxLED called: box=$boxNumber, state=$state');
    print('[ESP32Service] IP Address: $_ipAddress');
    print('[ESP32Service] Is Connected: $_isConnected');

    if (_ipAddress == null || _ipAddress!.isEmpty) {
      _error = 'IP address not set. Please connect to ESP32 first.';
      print('[ESP32Service] ❌ Error: $_error');
      notifyListeners();
      return false;
    }

    if (boxNumber < 1 || boxNumber > 7) {
      _error = 'Invalid box number. Must be between 1 and 7';
      print('[ESP32Service] ❌ Error: $_error');
      notifyListeners();
      return false;
    }

    try {
      final stateStr = state ? 'on' : 'off';
      final url = '$_baseUrl/led?box=$boxNumber&state=$stateStr';
      print('[ESP32Service] Sending request to: $url');

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      print('[ESP32Service] Response status: ${response.statusCode}');
      print('[ESP32Service] Response body: ${response.body}');

      if (response.statusCode == 200) {
        _error = null;
        print('[ESP32Service] ✅ LED control successful');
        return true;
      }
      _error = 'Failed to control LED. Status code: ${response.statusCode}';
      print('[ESP32Service] ❌ Error: $_error');
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      print('[ESP32Service] ❌ Exception: $_error');
      notifyListeners();
      return false;
    }
  }

  // Blink LED for specific pill box (1-7) - blinks 2 times
  // Uses ESP32 hardware-side blinking for better reliability
  Future<bool> blinkBoxLED(int boxNumber, {int times = 2}) async {
    print('[ESP32Service] blinkBoxLED called: box=$boxNumber, times=$times');

    if (_ipAddress == null || _ipAddress!.isEmpty) {
      _error = 'IP address not set. Please connect to ESP32 first.';
      print('[ESP32Service] ❌ Error: $_error');
      notifyListeners();
      return false;
    }

    if (boxNumber < 1 || boxNumber > 7) {
      _error = 'Invalid box number. Must be between 1 and 7';
      print('[ESP32Service] ❌ Error: $_error');
      notifyListeners();
      return false;
    }

    try {
      // Use the new /blink endpoint for hardware-side blinking
      final url = '$_baseUrl/blink?box=$boxNumber&times=$times';
      print('[ESP32Service] Sending blink request to: $url');

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      print('[ESP32Service] Response status: ${response.statusCode}');
      print('[ESP32Service] Response body: ${response.body}');

      if (response.statusCode == 200) {
        _error = null;
        print(
          '[ESP32Service] ✅ LED blink started for Box $boxNumber ($times times)',
        );
        return true;
      }
      _error = 'Failed to blink LED. Status code: ${response.statusCode}';
      print('[ESP32Service] ❌ Error: $_error');
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      print('[ESP32Service] ❌ Exception: $_error');
      notifyListeners();
      return false;
    }
  }

  // Start polling for status updates
  void startPolling({Duration interval = const Duration(seconds: 5)}) {
    stopPolling();
    _pollingTimer = Timer.periodic(interval, (_) => getStatus());
  }

  // Stop polling
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // Disconnect
  void disconnect() {
    stopPolling();
    _isConnected = false;
    _lastStatus = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
