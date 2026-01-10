import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/medicine_box.dart';
import '../screens/box_detail_screen.dart';
import '../services/esp32_service.dart';

class MedicineBoxCard extends StatelessWidget {
  final MedicineBox medicineBox;

  const MedicineBoxCard({super.key, required this.medicineBox});

  @override
  Widget build(BuildContext context) {
    // Check if ESP32 is connected to this medicine box's device
    final esp32 = context.watch<ESP32Service>();
    final isDeviceConnected =
        esp32.isConnected &&
        medicineBox.deviceId != null &&
        medicineBox.deviceId!.isNotEmpty &&
        (esp32.ipAddress?.contains(medicineBox.deviceId!) ?? false);

    // Use either the real-time connection status or the stored status
    final isConnected = isDeviceConnected || medicineBox.isConnected;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BoxDetailScreen(medicineBox: medicineBox),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.medical_services,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          medicineBox.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Box #${medicineBox.boxNumber}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(153),
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? Colors.green.withAlpha(51)
                          : Colors.grey.withAlpha(51),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isConnected ? Icons.wifi : Icons.wifi_off,
                          size: 16,
                          color: isConnected ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isConnected ? 'Connected' : 'Not Connected',
                          style: TextStyle(
                            fontSize: 12,
                            color: isConnected ? Colors.green : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (medicineBox.reminderTimes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.alarm,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${medicineBox.reminderTimes.length} reminder${medicineBox.reminderTimes.length > 1 ? 's' : ''} set',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: medicineBox.reminderTimes.take(3).map((reminder) {
                    return Chip(
                      label: Text(
                        reminder.formattedTime,
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: reminder.isEnabled
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Colors.grey.withAlpha(51),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
