import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/medicine_box_provider.dart';
import '../models/medicine_box.dart';
import '../models/medicine_record.dart';

class TodayDosesCard extends StatefulWidget {
  const TodayDosesCard({super.key});

  @override
  State<TodayDosesCard> createState() => _TodayDosesCardState();
}

class _TodayDosesCardState extends State<TodayDosesCard> {
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    return Consumer<MedicineBoxProvider>(
      builder: (context, provider, child) {
        return FutureBuilder<List<MedicineRecord>>(
          key: ValueKey(_refreshKey),
          future: provider.fetchTodayRecordsFromDatabase(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const SizedBox.shrink();
            }
            final todayRecords = snapshot.data!;
            final validBoxIds = provider.medicineBoxes.map((b) => b.id).toSet();
            final filteredRecords = todayRecords
                .where((r) => validBoxIds.contains(r.medicineBoxId))
                .toList();
            final taken = filteredRecords.where((r) => r.isTaken).length;
            final total = filteredRecords.length;

            if (total == 0) {
              return const SizedBox.shrink();
            }

            return Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Today\'s Doses',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '$taken / $total',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: total > 0 ? taken / total : 0,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 16),
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

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              record.isTaken
                                  ? Icons.check_circle
                                  : record.isOverduePending
                                  ? Icons.warning
                                  : Icons.schedule,
                              color: record.isTaken
                                  ? Colors.green
                                  : record.isOverduePending
                                  ? Colors.orange
                                  : Colors.blue,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    box.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        DateFormat(
                                          'h:mm a',
                                        ).format(record.scheduledTime),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                      if (record.isOverduePending) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withAlpha(51),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            'Overdue',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (!record.isTaken && !record.isMissed)
                              ElevatedButton(
                                onPressed: () async {
                                  // Find the reminder for this record
                                  final reminder = box.reminderTimes.firstWhere(
                                    (r) => r.id == record.reminderTimeId,
                                    orElse: () =>
                                        throw Exception('Reminder not found'),
                                  );

                                  await provider.markAsTaken(
                                    record.id,
                                    box: box,
                                    reminder: reminder,
                                  );

                                  // Force UI to refresh by updating the key
                                  // markAsTaken already updates local records and calls notifyListeners()
                                  if (mounted) {
                                    setState(() {
                                      _refreshKey++;
                                    });
                                  }

                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${box.name} marked as taken',
                                        ),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Take'),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
