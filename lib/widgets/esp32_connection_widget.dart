import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/esp32_service.dart';

class ESP32ConnectionWidget extends StatefulWidget {
  const ESP32ConnectionWidget({super.key});

  @override
  State<ESP32ConnectionWidget> createState() => _ESP32ConnectionWidgetState();
}

class _ESP32ConnectionWidgetState extends State<ESP32ConnectionWidget> {
  final _ipController = TextEditingController();
  bool _isConnecting = false;

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final esp32 = context.read<ESP32Service>();

    if (_ipController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter ESP32 IP address')),
      );
      return;
    }

    setState(() => _isConnecting = true);

    esp32.setIpAddress(_ipController.text);
    final success = await esp32.testConnection();

    setState(() => _isConnecting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Connected to ESP32!' : 'Connection failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );

      if (success) {
        esp32.startPolling();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ESP32Service>(
      builder: (context, esp32, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      esp32.isConnected ? Icons.wifi : Icons.wifi_off,
                      color: esp32.isConnected ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ESP32 Connection',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (esp32.isConnected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Connected',
                          style: TextStyle(color: Colors.green, fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                if (!esp32.isConnected) ...[
                  TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'ESP32 IP Address',
                      hintText: 'e.g., 192.168.1.100',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.router),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isConnecting ? null : _connect,
                      icon: _isConnecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link),
                      label: Text(_isConnecting ? 'Connecting...' : 'Connect'),
                    ),
                  ),
                ] else ...[
                  Text('IP: ${esp32.ipAddress}'),
                  const SizedBox(height: 8),
                  if (esp32.lastStatus != null) ...[
                    _StatusRow(
                      label: 'Box Status',
                      value: esp32.lastStatus!.isBoxOpen ? 'Open' : 'Closed',
                      icon: esp32.lastStatus!.isBoxOpen
                          ? Icons.lock_open
                          : Icons.lock,
                      color: esp32.lastStatus!.isBoxOpen
                          ? Colors.orange
                          : Colors.green,
                    ),
                    _StatusRow(
                      label: 'Medicine Taken',
                      value: esp32.lastStatus!.medicineTaken ? 'Yes' : 'No',
                      icon: esp32.lastStatus!.medicineTaken
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: esp32.lastStatus!.medicineTaken
                          ? Colors.green
                          : Colors.grey,
                    ),
                    _StatusRow(
                      label: 'Weight Change',
                      value:
                          '${esp32.lastStatus!.weightLoss.toStringAsFixed(1)}g',
                      icon: Icons.scale,
                      color: Colors.blue,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => esp32.getStatus(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            esp32.disconnect();
                            _ipController.clear();
                          },
                          icon: const Icon(Icons.link_off),
                          label: const Text('Disconnect'),
                        ),
                      ),
                    ],
                  ),
                ],

                if (esp32.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    esp32.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatusRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label),
          const Spacer(),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
