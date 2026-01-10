import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/esp32_service.dart';
import '../widgets/esp32_control_widget.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  List<DiscoveredDevice> _discoveredDevices = [];
  bool _isScanning = false;
  String _scanStatus = 'Tap "Scan" to find devices';
  double _scanProgress = 0;
  int _scannedCount = 0;
  int _totalToScan = 0;

  @override
  Widget build(BuildContext context) {
    final esp32 = context.watch<ESP32Service>();

    print(
      '🖥️ DeviceScreen build - isConnected: ${esp32.isConnected}, devices: ${esp32.connectedDevices.length}, activeDevice: ${esp32.activeDevice?.name}',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Device Connection'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection Status Card
            Card(
              color: esp32.isConnected
                  ? Colors.green.shade50
                  : Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      esp32.isConnected ? Icons.check_circle : Icons.warning,
                      color: esp32.isConnected ? Colors.green : Colors.orange,
                      size: 40,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            esp32.isConnected
                                ? (esp32.currentDeviceName ?? 'Connected!')
                                : 'Not Connected',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: esp32.isConnected
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                          if (esp32.isConnected && esp32.ipAddress != null)
                            Text(
                              'IP: ${esp32.ipAddress!.replaceAll("http://", "")}',
                            ),
                          if (!esp32.isConnected)
                            const Text('Scan to find your device'),
                        ],
                      ),
                    ),
                    if (esp32.isConnected)
                      ElevatedButton(
                        onPressed: () {
                          esp32.disconnect();
                          setState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Disconnect'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // My Saved Devices Section
            if (esp32.connectedDevices.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.devices,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'My Devices (${esp32.connectedDevices.length})',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...esp32.connectedDevices.map(
                        (device) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: esp32.activeDevice?.ip == device.ip
                              ? Colors.green.shade100
                              : Colors.grey.shade100,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  esp32.activeDevice?.ip == device.ip
                                  ? Colors.green
                                  : Colors.grey,
                              child: const Icon(
                                Icons.medical_services,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              device.name,
                              style: TextStyle(
                                fontWeight: esp32.activeDevice?.ip == device.ip
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text('IP: ${device.ip}'),
                            trailing: esp32.activeDevice?.ip == device.ip
                                ? const Chip(
                                    label: Text('Active'),
                                    backgroundColor: Colors.green,
                                    labelStyle: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  )
                                : ElevatedButton(
                                    onPressed: () => _switchToDevice(device),
                                    child: const Text('Switch'),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Control Widget (only show if connected)
            if (esp32.isConnected) ...[
              const ESP32ControlWidget(),
              const SizedBox(height: 16),
            ],

            // Scan Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.wifi_find,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Find Devices on WiFi',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _scanStatus,
                      style: TextStyle(
                        color: _isScanning ? Colors.blue : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_isScanning) ...[
                      LinearProgressIndicator(value: _scanProgress),
                      const SizedBox(height: 8),
                      Text(
                        'Scanned $_scannedCount / $_totalToScan IPs',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _isScanning = false),
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop Scanning'),
                        ),
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _startScan,
                          icon: const Icon(Icons.search),
                          label: const Text('Scan for Devices'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Discovered Devices
            if (_discoveredDevices.isNotEmpty) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.devices, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'Found ${_discoveredDevices.length} Device(s)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._discoveredDevices.map(
                        (device) => _DeviceCard(
                          device: device,
                          isConnected:
                              esp32.ipAddress?.contains(device.ip) ?? false,
                          onConnect: () => _connectToDevice(device),
                          onRename: () => _showRenameDialog(device),
                          onRemove: () => _removeDevice(device),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (!_isScanning && _scannedCount > 0) ...[
              Card(
                color: Colors.red.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No devices found. Make sure:\n'
                          '• ESP32 is powered on\n'
                          '• ESP32 is connected to same WiFi\n'
                          '• Check Serial Monitor for ESP32 IP',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Manual Entry Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.edit,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Manual Connection',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ManualConnectWidget(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices = [];
      _scanProgress = 0;
      _scannedCount = 0;
      _scanStatus = 'Getting network info...';
    });

    try {
      // Get local IP to determine network range
      String? localIp;

      try {
        final interfaces = await NetworkInterface.list();
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 &&
                !addr.isLoopback &&
                addr.address.startsWith('192.168')) {
              localIp = addr.address;
              break;
            }
          }
          if (localIp != null) break;
        }
      } catch (e) {
        print('Error getting interfaces: $e');
      }

      if (localIp == null) {
        setState(() {
          _scanStatus = 'Could not find local IP. Using common range...';
        });
        // Try common home network range
        localIp = '192.168.0.1';
      }

      // Get network prefix (e.g., 192.168.0)
      final parts = localIp.split('.');
      final networkPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';

      setState(() {
        _totalToScan = 254;
        _scanStatus = 'Scanning $networkPrefix.1 - $networkPrefix.254...';
      });

      // Scan in batches for better performance
      const batchSize = 20;
      for (int start = 1; start <= 254 && _isScanning; start += batchSize) {
        final end = (start + batchSize - 1).clamp(1, 254);
        final futures = <Future>[];

        for (int i = start; i <= end && _isScanning; i++) {
          final ip = '$networkPrefix.$i';
          futures.add(_checkDevice(ip));
        }

        await Future.wait(futures);

        setState(() {
          _scannedCount = end;
          _scanProgress = end / 254;
          _scanStatus = 'Scanning $networkPrefix.$end...';
        });

        // Small delay between batches
        await Future.delayed(const Duration(milliseconds: 100));
      }

      setState(() {
        _isScanning = false;
        _scanProgress = 1;
        if (_discoveredDevices.isEmpty) {
          _scanStatus = 'Scan complete. No devices found.';
        } else {
          _scanStatus =
              'Scan complete! Found ${_discoveredDevices.length} device(s).';
        }
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _scanStatus = 'Error: $e';
      });
    }
  }

  Future<void> _checkDevice(String ip) async {
    if (!_isScanning) return;

    try {
      // First try /discover endpoint
      final response = await http
          .get(Uri.parse('http://$ip/discover'))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          if (data['device'] == 'Smart Medicine Box') {
            setState(() {
              // Avoid duplicates
              if (!_discoveredDevices.any((d) => d.ip == ip)) {
                _discoveredDevices.add(
                  DiscoveredDevice(
                    ip: ip,
                    name: data['device'] ?? 'Smart Medicine Box',
                    version: data['version'] ?? '1.0',
                  ),
                );
              }
            });
            return;
          }
        } catch (_) {}
      }

      // Also try /status endpoint as fallback
      final statusResponse = await http
          .get(Uri.parse('http://$ip/status'))
          .timeout(const Duration(seconds: 1));

      if (statusResponse.statusCode == 200) {
        try {
          final data = json.decode(statusResponse.body);
          if (data.containsKey('isBoxOpen') &&
              data.containsKey('medicineTaken')) {
            setState(() {
              if (!_discoveredDevices.any((d) => d.ip == ip)) {
                _discoveredDevices.add(
                  DiscoveredDevice(
                    ip: ip,
                    name: 'Smart Medicine Box',
                    version: '1.0',
                  ),
                );
              }
            });
          }
        } catch (_) {}
      }
    } catch (e) {
      // Device not found or not responding - ignore
    }
  }

  void _connectToDevice(DiscoveredDevice device) {
    // Show name dialog before connecting
    _showNameDialogAndConnect(device);
  }

  void _showNameDialogAndConnect(DiscoveredDevice device) {
    final nameController = TextEditingController(text: device.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name Your Device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'IP: ${device.ip}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Device Name',
                hintText: 'e.g., Mom\'s Medicine Box',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a name')),
                );
                return;
              }
              Navigator.pop(context);
              _doConnect(device, name);
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _doConnect(DiscoveredDevice device, String customName) {
    final esp32 = context.read<ESP32Service>();

    // Update device name
    device.name = customName;

    // Add to connected devices list
    esp32.addDevice(device.ip, customName, version: device.version);
    esp32.setIpAddress(device.ip, deviceName: customName);

    setState(() {
      _scanStatus = 'Connecting to $customName...';
    });

    esp32.testConnection().then((success) {
      if (mounted) {
        if (success) {
          esp32.setActiveDevice(device.ip);
        }

        setState(() {
          _scanStatus = success
              ? 'Connected to $customName!'
              : 'Failed to connect to ${device.ip}';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? '✓ Connected to $customName!' : '✗ Failed to connect',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
        if (success) {
          esp32.startPolling();
        }
      }
    });
  }

  void _showRenameDialog(DiscoveredDevice device) {
    final nameController = TextEditingController(text: device.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Device'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Device Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              Navigator.pop(context);

              setState(() {
                device.name = name;
              });

              final esp32 = context.read<ESP32Service>();
              esp32.renameDevice(device.ip, name);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Device renamed to "$name"'),
                  backgroundColor: Colors.blue,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _removeDevice(DiscoveredDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text('Remove "${device.name}" from the list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);

              setState(() {
                _discoveredDevices.removeWhere((d) => d.ip == device.ip);
              });

              final esp32 = context.read<ESP32Service>();
              esp32.removeDevice(device.ip);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _switchToDevice(ConnectedDevice device) {
    final esp32 = context.read<ESP32Service>();

    setState(() {
      _scanStatus = 'Switching to ${device.name}...';
    });

    esp32.setIpAddress(device.ip, deviceName: device.name);
    esp32.testConnection().then((success) {
      if (mounted) {
        if (success) {
          esp32.setActiveDevice(device.ip);
        }

        setState(() {
          _scanStatus = success
              ? 'Switched to ${device.name}!'
              : 'Failed to connect to ${device.name}';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '✓ Switched to ${device.name}!'
                  : '✗ ${device.name} is offline',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );

        if (success) {
          esp32.startPolling();
        }
      }
    });
  }
}

class DiscoveredDevice {
  final String ip;
  String name;
  final String version;

  DiscoveredDevice({
    required this.ip,
    required this.name,
    required this.version,
  });
}

class _DeviceCard extends StatelessWidget {
  final DiscoveredDevice device;
  final bool isConnected;
  final VoidCallback onConnect;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  const _DeviceCard({
    required this.device,
    required this.isConnected,
    required this.onConnect,
    required this.onRename,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isConnected ? Colors.green.shade100 : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isConnected ? Colors.green : Colors.blue,
          child: const Icon(Icons.medical_services, color: Colors.white),
        ),
        title: Text(
          device.name,
          style: TextStyle(
            fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text('IP: ${device.ip} • v${device.version}'),
        trailing: isConnected
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: onRename,
                    tooltip: 'Rename',
                  ),
                  const Chip(
                    label: Text('Connected'),
                    backgroundColor: Colors.green,
                    labelStyle: TextStyle(color: Colors.white),
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                    onPressed: onRemove,
                    tooltip: 'Remove',
                  ),
                  ElevatedButton(
                    onPressed: onConnect,
                    child: const Text('Connect'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ManualConnectWidget extends StatefulWidget {
  @override
  State<_ManualConnectWidget> createState() => _ManualConnectWidgetState();
}

class _ManualConnectWidgetState extends State<_ManualConnectWidget> {
  final _ipController = TextEditingController();
  bool _isConnecting = false;
  String? _message;

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'If scanning doesn\'t work, enter IP from ESP32 Serial Monitor:',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  hintText: 'e.g., 192.168.0.40',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isConnecting ? null : _connect,
              child: _isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(
            _message!,
            style: TextStyle(
              color: _message!.contains('✓') ? Colors.green : Colors.red,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _connect() async {
    if (_ipController.text.isEmpty) {
      setState(() => _message = '✗ Please enter IP address');
      return;
    }

    setState(() {
      _isConnecting = true;
      _message = null;
    });

    final esp32 = context.read<ESP32Service>();
    final ipAddress = _ipController.text.trim();

    // Set IP and test connection
    esp32.setIpAddress(ipAddress);
    final success = await esp32.testConnection();

    if (success) {
      // Add device to connected devices list
      esp32.addDevice(
        ipAddress,
        'Medicine Box', // Default name, can be renamed later
        version: '1.0',
      );
      esp32.setActiveDevice(ipAddress);
      esp32.startPolling();
    }

    setState(() {
      _isConnecting = false;
      _message = success
          ? '✓ Connected successfully!'
          : '✗ Connection failed. Check IP and try again.';
    });

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Connected to ESP32!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
