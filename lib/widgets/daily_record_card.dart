import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/medicine_record.dart';
import '../models/medicine_box.dart';
import '../providers/medicine_box_provider.dart';
import '../services/esp32_service.dart';

class DailyRecordCard extends StatelessWidget {
  final DateTime date;
  final List<MedicineRecord> records;
  final List<MedicineBox> medicineBoxes;

  const DailyRecordCard({
    super.key,
    required this.date,
    required this.records,
    this.medicineBoxes = const [],
  });

  @override
  Widget build(BuildContext context) {
    final takenCount = records.where((r) => r.isTaken).length;
    final missedCount = records.where((r) => r.isMissed).length;
    final overduePendingCount = records.where((r) => r.isOverduePending).length;
    final futurePendingCount = records.where((r) => r.isFuturePending).length;
    final totalCount = records.length;
    final isToday = _isToday(date);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: SizedBox(
            width: 56,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: isToday
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('dd').format(date),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                      color: isToday
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : null,
                    ),
                  ),
                  Text(
                    DateFormat('EEE').format(date),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.0,
                      fontSize: 11,
                      color: isToday
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(153),
                    ),
                  ),
                ],
              ),
            ),
          ),
          title: Text(
            DateFormat('MMMM d, yyyy').format(date),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildBadge(
                  context,
                  Icons.check_circle,
                  takenCount.toString(),
                  Colors.green,
                ),
                if (overduePendingCount > 0)
                  _buildBadge(
                    context,
                    Icons.warning,
                    overduePendingCount.toString(),
                    Colors.orange,
                  ),
                if (futurePendingCount > 0)
                  _buildBadge(
                    context,
                    Icons.access_time,
                    futurePendingCount.toString(),
                    Colors.blue,
                  ),
                _buildBadge(
                  context,
                  Icons.cancel,
                  missedCount.toString(),
                  Colors.red,
                ),
                Text(
                  '($totalCount total)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          children: [
            const Divider(),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];

                return _RecordTile(
                  record: record,
                  medicineBoxes: medicineBoxes,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Widget _buildBadge(
    BuildContext context,
    IconData icon,
    String text,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(51),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final MedicineRecord record;
  final List<MedicineBox> medicineBoxes;

  const _RecordTile({required this.record, required this.medicineBoxes});

  // Get the medicine box for this record, or return a default if not found
  MedicineBox get medicineBox {
    try {
      return medicineBoxes.firstWhere((b) => b.id == record.medicineBoxId);
    } catch (e) {
      // Return a default box with data from the record
      return MedicineBox(
        id: record.medicineBoxId,
        name: record.name ?? 'Box 1',
        boxNumber: record.boxNumber ?? 0,
        reminderTimes: [],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(_getStatusIcon(), color: _getStatusColor(), size: 24),
      title: Text(
        record.name ?? 'Box 1',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Box ${record.boxNumber ?? 0} • Scheduled: ${DateFormat('h:mm a').format(record.scheduledTime)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (record.isTaken && record.takenTime != null)
            Text(
              'Taken: ${DateFormat('h:mm a').format(record.takenTime!)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.green),
            )
          else if (record.isOverduePending)
            Text(
              'Overdue Pending',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.orange),
            )
          else if (record.isFuturePending)
            Text(
              'Future Pending',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.blue),
            )
          else if (record.isMissed)
            Text(
              'Missed',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.red),
            ),
        ],
      ),
      trailing: _buildActionButton(context),
    );
  }

  IconData _getStatusIcon() {
    if (record.isTaken) return Icons.check_circle;
    if (record.isMissed) return Icons.cancel;
    if (record.isOverduePending) return Icons.warning;
    if (record.isFuturePending) return Icons.access_time;
    if (record.isOverdue) return Icons.warning;
    return Icons.schedule;
  }

  Color _getStatusColor() {
    if (record.isTaken) return Colors.green;
    if (record.isMissed) return Colors.red;
    if (record.isOverduePending) return Colors.orange;
    if (record.isFuturePending) return Colors.blue;
    if (record.isOverdue) return Colors.orange;
    return Colors.grey;
  }

  Widget? _buildActionButton(BuildContext context) {
    if (record.isTaken || record.isMissed) {
      return null;
    }

    if (record.isScheduledForToday) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Find Box button for all pending items (not taken or missed)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: OutlinedButton(
              onPressed: () async {
                final esp32Service = context.read<ESP32Service>();

                // Check if ESP32 is connected
                if (!esp32Service.isConnected) {
                  // Try to connect
                  final connected = await esp32Service.testConnection();
                  if (!connected) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'ESP32 not connected. Please connect to device first.',
                        ),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                    return;
                  }
                }

                // Blink the LED 2 times
                final success = await esp32Service.blinkBoxLED(
                  medicineBox.boxNumber,
                  times: 2,
                );

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Box ${medicineBox.boxNumber} LED is blinking'
                          : 'Failed to blink LED: ${esp32Service.error ?? "Unknown error"}',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Icon(Icons.lightbulb, size: 16),
            ),
          ),
          // Take button
          ElevatedButton(
            onPressed: () async {
              // Find the reminder for this record
              final reminder = medicineBox.reminderTimes.firstWhere(
                (r) => r.id == record.reminderTimeId,
                orElse: () => throw Exception('Reminder not found'),
              );

              final provider = context.read<MedicineBoxProvider>();
              await provider.markAsTaken(
                record.id,
                box: medicineBox,
                reminder: reminder,
              );

              // markAsTaken already updates local records and calls notifyListeners()
              // The parent Consumer will rebuild and re-fetch records

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${medicineBox.name} marked as taken'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Take', style: TextStyle(fontSize: 12)),
          ),
        ],
      );
    }

    return null;
  }
}
