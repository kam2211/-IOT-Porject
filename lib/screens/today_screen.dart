import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/medicine_box_provider.dart';
import '../models/medicine_box.dart';
import '../models/medicine_record.dart';
import '../services/reminder_service.dart';
import '../services/esp32_service.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  int _refreshKey = 0; // Key to force FutureBuilder to rebuild

  @override
  void initState() {
    super.initState();
    // Load medicine boxes and sync with device when the screen initializes
    Future.microtask(() async {
      final provider = context.read<MedicineBoxProvider>();
      provider.loadMedicineBoxes();
      await provider.syncWithDevice();

      // Set up box status change listener
      final esp32Service = context.read<ESP32Service>();
      esp32Service.onBoxStatusChanged = (data) {
        _handleBoxStatusChanged(data);
      };
    });
  }

  void _handleBoxStatusChanged(Map<String, dynamic> data) {
    if (!mounted) return;

    final medicineTaken = data['medicineTaken'] == true;
    final weightLoss = data['weightLoss'] ?? 0;

    // Show snackbar notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  medicineTaken ? Icons.check_circle : Icons.info,
                  color: medicineTaken ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    medicineTaken ? '✓ Medicine Taken!' : '⚠ No Medicine Taken',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              medicineTaken
                  ? 'Medicine successfully detected (${weightLoss.toStringAsFixed(1)}g)'
                  : 'Please mark as taken if you took the medicine manually',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: medicineTaken ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 5),
        action: medicineTaken
            ? null
            : SnackBarAction(
                label: 'Mark Taken',
                textColor: Colors.white,
                onPressed: () {
                  // Will be handled when user clicks - just close snackbar for now
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today\'s Doses'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {
              context.read<MedicineBoxProvider>().syncWithDevice();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Syncing with device...')),
              );
            },
            tooltip: 'Sync with device',
          ),
        ],
      ),
      body: Consumer<MedicineBoxProvider>(
        builder: (context, provider, child) {
          return FutureBuilder<List<MedicineRecord>>(
            key: ValueKey(_refreshKey), // Force rebuild when key changes
            future: provider.fetchTodayRecordsFromDatabase(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text('Error: ${snapshot.error}'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => setState(() {}),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              final todayRecords = snapshot.data ?? [];
              // Filter to only show records for existing medicine boxes
              final validBoxIds = provider.medicineBoxes
                  .map((b) => b.id)
                  .toSet();
              final filteredRecords = todayRecords
                  .where((r) => validBoxIds.contains(r.medicineBoxId))
                  .toList();

              // Sort records: Ongoing (within 5min) first, overdue second, upcoming third, taken last
              final now = DateTime.now();
              filteredRecords.sort((a, b) {
                // Helper function to get sort priority
                int getPriority(MedicineRecord record) {
                  if (record.isTaken) {
                    return 4; // Taken (LAST)
                  }

                  // Check if within 5 minutes of scheduled time (FIRST priority - Ongoing)
                  final minutesUntilDue = record.scheduledTime
                      .difference(now)
                      .inMinutes;
                  final minutesSinceDue = now
                      .difference(record.scheduledTime)
                      .inMinutes;

                  // Ongoing: reminder time is within +5 minutes (can be before or after)
                  if (minutesUntilDue >= -5 && minutesUntilDue <= 5) {
                    return 1; // Ongoing (FIRST)
                  } else if (minutesSinceDue > 5) {
                    // More than 5 minutes past
                    return 2; // Overdue (SECOND)
                  } else if (minutesUntilDue > 5) {
                    // More than 5 minutes in future
                    return 3; // Upcoming (THIRD)
                  }

                  return 5; // Missed
                }

                final priorityA = getPriority(a);
                final priorityB = getPriority(b);

                if (priorityA != priorityB) {
                  return priorityA.compareTo(priorityB);
                }

                // Within same priority, sort by scheduled time (earliest first)
                return a.scheduledTime.compareTo(b.scheduledTime);
              });

              final taken = filteredRecords.where((r) => r.isTaken).length;
              final total = filteredRecords.length;

              if (total == 0) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 80,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withAlpha(128),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No doses scheduled for today',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add medicine boxes to get started',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withAlpha(153),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  // Force FutureBuilder to rebuild by changing the key
                  setState(() {
                    _refreshKey++;
                  });
                  // Also reload records from provider
                  await provider.reloadTodayRecords();
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Summary Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Progress',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '$taken / $total',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value: total > 0 ? taken / total : 0,
                              minHeight: 12,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              total > 0
                                  ? '${((taken / total) * 100).toStringAsFixed(0)}% completed'
                                  : '0% completed',
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
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Scheduled Doses',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Doses List
                    ...filteredRecords.map((record) {
                      final box = provider.medicineBoxes.firstWhere(
                        (b) => b.id == record.medicineBoxId,
                        orElse: () => MedicineBox(
                          id: '',
                          name: 'Unknown',
                          boxNumber: 0,
                          reminderTimes: [],
                        ),
                      );

                      if (box.id.isEmpty) return const SizedBox.shrink();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: record.isTaken
                                  ? Colors.green.withAlpha(51)
                                  : record.isMissed
                                  ? Colors.red.withAlpha(51)
                                  : record.isOverduePending
                                  ? Colors.orange.withAlpha(51)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              record.isTaken
                                  ? Icons.check_circle
                                  : record.isMissed
                                  ? Icons.cancel
                                  : record.isOverduePending
                                  ? Icons.warning
                                  : Icons.medication,
                              color: record.isTaken
                                  ? Colors.green
                                  : record.isMissed
                                  ? Colors.red
                                  : record.isOverduePending
                                  ? Colors.orange
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                              size: 28,
                            ),
                          ),
                          title: Text(
                            box.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withAlpha(153),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat(
                                      'h:mm a',
                                    ).format(record.scheduledTime),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withAlpha(153),
                                    ),
                                  ),
                                ],
                              ),
                              if (record.isTaken &&
                                  record.takenTime != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Taken at ${DateFormat('h:mm a').format(record.takenTime!)}',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else if (record.isMissed) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.cancel,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Missed',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else if (record.isOverduePending) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.warning,
                                      size: 16,
                                      color: Colors.orange,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Overdue',
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else if (record.isFuturePending) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 16,
                                      color: Colors.blue,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Upcoming',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: !record.isTaken && !record.isMissed
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Find Box button for all pending items (not taken or missed)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: OutlinedButton(
                                        onPressed: () async {
                                          final esp32Service = context
                                              .read<ESP32Service>();

                                          // Check if ESP32 is connected
                                          if (!esp32Service.isConnected) {
                                            // Try to connect
                                            final connected = await esp32Service
                                                .testConnection();
                                            if (!connected) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'ESP32 not connected. Please connect to device first.',
                                                    ),
                                                    backgroundColor: Colors.red,
                                                    duration: const Duration(
                                                      seconds: 3,
                                                    ),
                                                  ),
                                                );
                                              }
                                              return;
                                            }
                                          }

                                          // Track which specific reminder's LED was tapped
                                          provider.setLastTappedReminder(
                                            box.boxNumber,
                                            record.reminderTimeId,
                                          );

                                          // Blink the LED 2 times
                                          final success = await esp32Service
                                              .blinkBoxLED(
                                                box.boxNumber,
                                                times: 2,
                                              );

                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  success
                                                      ? 'Box ${box.boxNumber} LED is blinking'
                                                      : 'Failed to blink LED: ${esp32Service.error ?? "Unknown error"}',
                                                ),
                                                backgroundColor: success
                                                    ? Colors.green
                                                    : Colors.red,
                                                duration: const Duration(
                                                  seconds: 2,
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.orange,
                                          side: const BorderSide(
                                            color: Colors.orange,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 6,
                                          ),
                                          minimumSize: const Size(0, 32),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Icon(
                                          Icons.lightbulb,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                    // Take button
                                    FilledButton(
                                      onPressed: () async {
                                        // Find the reminder for this record
                                        final reminder = box.reminderTimes
                                            .firstWhere(
                                              (r) =>
                                                  r.id == record.reminderTimeId,
                                              orElse: () => throw Exception(
                                                'Reminder not found',
                                              ),
                                            );

                                        await provider.markAsTaken(
                                          record.id,
                                          box: box,
                                          reminder: reminder,
                                        );

                                        // Stop notification escalation for this reminder
                                        final reminderService = context
                                            .read<ReminderService>();
                                        reminderService.stopEscalation(
                                          box.id,
                                          record.reminderTimeId,
                                        );

                                        // Immediately sync with device after marking as taken
                                        await provider.syncWithDevice();

                                        // Force UI to refresh by updating the key
                                        // markAsTaken already updates local records and calls notifyListeners()
                                        if (mounted) {
                                          setState(() {
                                            _refreshKey++;
                                          });
                                        }

                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '${box.name} marked as taken',
                                            ),
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                          ),
                                        );
                                      },
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        minimumSize: const Size(0, 32),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Take',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
