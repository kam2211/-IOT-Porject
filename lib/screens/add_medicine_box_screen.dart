import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/medicine_box.dart';
import '../providers/medicine_box_provider.dart';
import '../services/esp32_service.dart';

class AddMedicineBoxScreen extends StatefulWidget {
  final String? initialDeviceId;
  const AddMedicineBoxScreen({super.key, this.initialDeviceId});

  @override
  State<AddMedicineBoxScreen> createState() => _AddMedicineBoxScreenState();
}

class _AddMedicineBoxScreenState extends State<AddMedicineBoxScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _selectedDeviceId;
  int _selectedBoxNumber = 1;

  @override
  void initState() {
    super.initState();
    // Set initial device ID if provided
    if (widget.initialDeviceId != null && widget.initialDeviceId!.isNotEmpty) {
      _selectedDeviceId = widget.initialDeviceId;
    } else {
      // Try to get active device from ESP32Service after first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final esp32 = context.read<ESP32Service>();
          if (esp32.activeDevice != null) {
            setState(() {
              _selectedDeviceId = esp32.activeDevice!.ip.replaceAll(
                'http://',
                '',
              );
            });
          } else if (esp32.connectedDevices.isNotEmpty) {
            setState(() {
              _selectedDeviceId = esp32.connectedDevices.first.ip.replaceAll(
                'http://',
                '',
              );
            });
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveMedicineBox() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    if (_selectedDeviceId == null || _selectedDeviceId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a device'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final newBox = MedicineBox(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      boxNumber: _selectedBoxNumber,
      reminderTimes: [],
      deviceId: _selectedDeviceId,
    );

    try {
      await context.read<MedicineBoxProvider>().addMedicineBox(newBox);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding box: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Medicine Box')),
      body: Builder(
        builder: (context) {
          try {
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Select Medicine Box',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  // Visual box selector
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // First row - 4 boxes
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (int i = 1; i <= 4; i++)
                                _BoxSelector(
                                  boxNumber: i,
                                  isSelected: _selectedBoxNumber == i,
                                  onTap: () {
                                    setState(() {
                                      _selectedBoxNumber = i;
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Second row - 3 boxes
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (int i = 5; i <= 7; i++)
                                _BoxSelector(
                                  boxNumber: i,
                                  isSelected: _selectedBoxNumber == i,
                                  onTap: () {
                                    setState(() {
                                      _selectedBoxNumber = i;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Consumer<ESP32Service>(
                    builder: (context, esp32, child) {
                      final devices = esp32.connectedDevices;

                      if (devices.isEmpty) {
                        return Card(
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.warning,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'No Devices Available',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onErrorContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Please connect to a device first from the Device screen.',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      // Build device IP list (normalized, without http://)
                      final validDeviceIds = devices
                          .map((d) => d.ip.replaceAll('http://', '').trim())
                          .toList();

                      // Normalize selected device ID for comparison
                      String? normalizedSelectedId;
                      if (_selectedDeviceId != null) {
                        normalizedSelectedId = _selectedDeviceId!
                            .replaceAll('http://', '')
                            .trim();
                      }

                      // Ensure selected device ID is valid
                      if (normalizedSelectedId != null &&
                          !validDeviceIds.contains(normalizedSelectedId)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {
                              _selectedDeviceId = validDeviceIds.isNotEmpty
                                  ? validDeviceIds.first
                                  : null;
                            });
                          }
                        });
                      }

                      final currentValue =
                          validDeviceIds.contains(normalizedSelectedId)
                          ? normalizedSelectedId
                          : (devices.isNotEmpty ? validDeviceIds.first : null);

                      return SizedBox(
                        height:
                            80, // Give explicit height to prevent layout issues
                        child: DropdownButtonFormField<String>(
                          value: currentValue,
                          decoration: const InputDecoration(
                            labelText: 'Select Device',
                            hintText: 'Choose a device',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.devices),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          isExpanded: true,
                          items: devices.map((device) {
                            final deviceIp = device.ip.replaceAll(
                              'http://',
                              '',
                            );
                            return DropdownMenuItem<String>(
                              value: deviceIp,
                              child: Row(
                                children: [
                                  Icon(
                                    device.isActive
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    size: 16,
                                    color: device.isActive
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${device.name} ($deviceIp)',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedDeviceId = value;
                              });
                            }
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select a device';
                            }
                            return null;
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Box Name',
                      hintText: 'e.g., Monday Morning',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a box name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saveMedicineBox,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Medicine Box'),
                  ),
                ],
              ),
            );
          } catch (e, stackTrace) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading screen: $e',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Stack trace: $stackTrace',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }
        },
      ),
    );
  }
}

class _BoxSelector extends StatelessWidget {
  final int boxNumber;
  final bool isSelected;
  final VoidCallback onTap;

  const _BoxSelector({
    required this.boxNumber,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 3,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.medication,
              size: 32,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface,
            ),
            const SizedBox(height: 4),
            Text(
              '$boxNumber',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
