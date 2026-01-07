import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/esp32_service.dart';
import '../providers/medicine_box_provider.dart';

class ESP32ControlWidget extends StatefulWidget {
  const ESP32ControlWidget({super.key});

  @override
  State<ESP32ControlWidget> createState() => _ESP32ControlWidgetState();
}

class _ESP32ControlWidgetState extends State<ESP32ControlWidget> {
  bool _isAlarmRinging = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<ESP32Service>(
      builder: (context, esp32, child) {
        if (!esp32.isConnected) {
          return const SizedBox.shrink();
        }

        final isOpen = esp32.lastStatus?.isBoxOpen ?? false;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.medical_services, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Medicine Box Control',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Box status indicator
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isOpen
                        ? Colors.orange.withValues(alpha: 0.1)
                        : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOpen ? Colors.orange : Colors.green,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        isOpen ? Icons.lock_open : Icons.lock,
                        size: 48,
                        color: isOpen ? Colors.orange : Colors.green,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isOpen ? 'Box is OPEN' : 'Box is CLOSED',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isOpen ? Colors.orange : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Control buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isOpen
                            ? null
                            : () => _openBox(context, esp32),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Open Box'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isOpen
                            ? () => _closeBox(context, esp32)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: const Icon(Icons.lock),
                        label: const Text('Close Box'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Reset button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _resetStatus(context, esp32),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset Medicine Taken Status'),
                  ),
                ),
                const SizedBox(height: 8),

                // Find Device button - toggle alarm
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _toggleFindDevice(context, esp32),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isAlarmRinging
                          ? Colors.red
                          : Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: Icon(
                      _isAlarmRinging ? Icons.volume_off : Icons.volume_up,
                    ),
                    label: Text(
                      _isAlarmRinging ? '🔔 STOP RINGING' : 'Find My Device',
                    ),
                  ),
                ),

                // Medicine taken status
                if (esp32.lastStatus?.medicineTaken == true) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          'Medicine has been taken!',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openBox(BuildContext context, ESP32Service esp32) async {
    // Get the first medicine box or use default box 1
    final provider = context.read<MedicineBoxProvider>();
    final boxNumber = provider.medicineBoxes.isNotEmpty 
        ? provider.medicineBoxes.first.boxNumber 
        : 1;
    
    print('📦 Opening box: $boxNumber');
    final success = await esp32.openBox(boxNumber: boxNumber);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Box $boxNumber opened!' : 'Failed to open box'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _closeBox(BuildContext context, ESP32Service esp32) async {
    print('🔄 _closeBox() called - attempting to close box');

    final result = await esp32.closeBox();
    print('📦 closeBox() returned: $result');

    if (!context.mounted) {
      print('⚠️ Context not mounted, cannot show UI');
      return;
    }

    if (result != null) {
      print('✅ Result is not null');
      print('   Full result: $result');

      final medicineTaken = result['medicineTaken'] == true;
      final weightLoss = result['weightLoss'] ?? 0;
      final medicineBoxId = result['medicineBoxId'] as String?;
      final boxNumber = result['boxNumber'] as int?;

      print('💊 medicineTaken: $medicineTaken');
      print('⚖️ weightLoss: $weightLoss');
      print('📦 medicineBoxId: $medicineBoxId');
      print('📦 boxNumber: $boxNumber');

      // If medicine was taken, immediately create a MedicineRecord
      if (medicineTaken) {
        print('🔍 Attempting to record medicine taken...');
        try {
          final medicineBoxProvider = context.read<MedicineBoxProvider>();

          print('💊 Weight loss: $weightLoss');

          // Create medicine record for today with box info
          await medicineBoxProvider.recordMedicineTaken(
            weightLoss: weightLoss,
            medicineBoxId: medicineBoxId,
            boxNumber: boxNumber,
          );

          print('✅ Medicine record created and saved to database');
        } catch (e) {
          print('❌ Error creating medicine record: $e');
        }
      } else {
        print('⚠️ medicineTaken is FALSE - no record will be created');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            medicineTaken
                ? 'Box closed. Medicine taken! (${weightLoss.toStringAsFixed(1)}g)'
                : 'Box closed. No medicine taken.',
          ),
          backgroundColor: medicineTaken ? Colors.green : Colors.orange,
        ),
      );
    } else {
      print('❌ Result is NULL from closeBox()');
    }
  }

  Future<void> _resetStatus(BuildContext context, ESP32Service esp32) async {
    final success = await esp32.resetStatus();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Status reset!' : 'Failed to reset'),
          backgroundColor: success ? Colors.blue : Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleFindDevice(
    BuildContext context,
    ESP32Service esp32,
  ) async {
    if (_isAlarmRinging) {
      // Stop the alarm
      final success = await esp32.stopBuzzer();
      if (mounted) {
        setState(() {
          _isAlarmRinging = false;
        });
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Alarm stopped!' : 'Failed to stop alarm'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } else {
      // Start continuous alarm
      final success = await esp32.startAlarm();
      if (mounted) {
        setState(() {
          _isAlarmRinging = success;
        });
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '🔔 Device is ringing! Tap again to stop.'
                  : 'Failed to start alarm',
            ),
            backgroundColor: success ? Colors.purple : Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}
