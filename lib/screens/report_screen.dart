import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/medicine_box_provider.dart';
import '../models/medicine_record.dart';
import '../widgets/statistics_card.dart';
import '../widgets/daily_record_card.dart';

enum ReportPeriod { week, month, all }

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  ReportPeriod _selectedPeriod = ReportPeriod.week;

  DateTimeRange _getDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_selectedPeriod) {
      case ReportPeriod.week:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 7)),
          end: today,
        );
      case ReportPeriod.month:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 30)),
          end: today,
        );
      case ReportPeriod.all:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 365)),
          end: today,
        );
    }
  }

  String _getPeriodLabel() {
    switch (_selectedPeriod) {
      case ReportPeriod.week:
        return 'This Week';
      case ReportPeriod.month:
        return 'This Month';
      case ReportPeriod.all:
        return 'All Time';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Consumer<MedicineBoxProvider>(
        builder: (context, provider, child) {
          final dateRange = _getDateRange();
          final records = provider.getRecordsForDateRange(
            dateRange.start,
            dateRange.end,
          );
          final statistics = provider.getStatistics(
            dateRange.start,
            dateRange.end,
          );

          // Group records by date
          final recordsByDate = <String, List<MedicineRecord>>{};
          for (var record in records) {
            final dateKey = DateFormat('yyyy-MM-dd').format(record.scheduledTime);
            if (!recordsByDate.containsKey(dateKey)) {
              recordsByDate[dateKey] = [];
            }
            recordsByDate[dateKey]!.add(record);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Period selector
              SegmentedButton<ReportPeriod>(
                segments: const [
                  ButtonSegment(
                    value: ReportPeriod.week,
                    label: Text('Week'),
                    icon: Icon(Icons.calendar_view_week),
                  ),
                  ButtonSegment(
                    value: ReportPeriod.month,
                    label: Text('Month'),
                    icon: Icon(Icons.calendar_month),
                  ),
                  ButtonSegment(
                    value: ReportPeriod.all,
                    label: Text('All'),
                    icon: Icon(Icons.calendar_today),
                  ),
                ],
                selected: {_selectedPeriod},
                onSelectionChanged: (Set<ReportPeriod> newSelection) {
                  setState(() {
                    _selectedPeriod = newSelection.first;
                  });
                },
              ),

              const SizedBox(height: 16),

              // Period label
              Text(
                _getPeriodLabel(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Statistics card
              StatisticsCard(statistics: statistics),

              const SizedBox(height: 16),

              // Daily records
              if (recordsByDate.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.event_busy,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary.withAlpha(128),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No records for this period',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...recordsByDate.entries.map((entry) {
                  final date = DateTime.parse(entry.key);
                  final dayRecords = entry.value;

                  return DailyRecordCard(
                    date: date,
                    records: dayRecords,
                    medicineBoxes: provider.medicineBoxes,
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
