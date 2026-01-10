import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/medicine_box_provider.dart';
import '../models/medicine_record.dart';
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

  /// Fetch records for date range, merging today's schedule data if today is in range
  Future<List<MedicineRecord>> _fetchRecordsWithSchedule(
    MedicineBoxProvider provider,
    DateTime startDate,
    DateTime endDate,
    bool isTodayInRange,
  ) async {
    // Get DB records for the date range
    final dbRecords = await provider.fetchRecordsForDateRangeFromDatabase(
      startDate,
      endDate,
    );

    // If today is in the date range, also include schedule data for today
    if (isTodayInRange) {
      // Get today's merged records (DB + schedule)
      final todayRecords = await provider.fetchTodayRecordsFromDatabase();

      // Merge: prefer today's merged records over DB-only records for today
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      // Remove DB records for today (we'll replace with merged records)
      final nonTodayRecords = dbRecords
          .where(
            (r) =>
                r.scheduledTime.isBefore(today) ||
                r.scheduledTime.isAfter(tomorrow),
          )
          .toList();

      // Combine non-today records with today's merged records
      return [...nonTodayRecords, ...todayRecords]
        ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    }

    return dbRecords;
  }

  MedicineStatistics _calculateReportStatistics(List<MedicineRecord> records) {
    int taken = 0, missed = 0, overdue = 0;
    final now = DateTime.now();

    for (final record in records) {
      if (record.isTaken) {
        taken++;
      } else if (record.isMissed) {
        missed++;
      } else if (record.scheduledTime.isBefore(now)) {
        overdue++; // not taken, not marked missed, and past due
      }
    }

    return MedicineStatistics(
      totalDoses: taken + missed + overdue,
      takenDoses: taken,
      missedDoses: missed,
      pendingDoses: 0,
      overduePendingDoses: overdue,
      futurePendingDoses: 0,
    );
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
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final isTodayInRange =
              !today.isBefore(dateRange.start) && !today.isAfter(dateRange.end);

          return FutureBuilder<List<MedicineRecord>>(
            future: _fetchRecordsWithSchedule(
              provider,
              dateRange.start,
              dateRange.end,
              isTodayInRange,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading records: ${snapshot.error}'),
                );
              }

              final records = snapshot.data ?? [];

              // Filter out records from deleted medicine boxes (Unknown name or boxNumber 0)
              final validRecords = records.where((record) {
                final hasValidName =
                    record.name != null &&
                    record.name!.isNotEmpty &&
                    record.name != 'Unknown';
                final hasValidBoxNumber =
                    record.boxNumber != null && record.boxNumber! > 0;
                return hasValidName && hasValidBoxNumber;
              }).toList();

              // Calculate statistics locally so overdue (not taken & not missed) are counted
              final statistics = _calculateReportStatistics(validRecords);

              // Group records by TAKEN date (not scheduled date)
              final recordsByDate = <String, List<MedicineRecord>>{};
              for (var record in validRecords) {
                // Use takenTime if available, otherwise use scheduledTime
                final dateToUse = record.isTaken && record.takenTime != null
                    ? record.takenTime!
                    : record.scheduledTime;
                final dateKey = DateFormat('yyyy-MM-dd').format(dateToUse);
                if (!recordsByDate.containsKey(dateKey)) {
                  recordsByDate[dateKey] = [];
                }
                recordsByDate[dateKey]!.add(record);
              }

              // Sort date keys descending (newest first)
              final sortedDateKeys = recordsByDate.keys.toList()
                ..sort(
                  (a, b) => DateTime.parse(b).compareTo(DateTime.parse(a)),
                );

              return _buildReportContent(
                context,
                recordsByDate,
                sortedDateKeys,
                statistics,
                provider,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildReportContent(
    BuildContext context,
    Map<String, List<MedicineRecord>> recordsByDate,
    List<String> sortedDateKeys,
    MedicineStatistics statistics,
    MedicineBoxProvider provider,
  ) {
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
              label: Text('Last 30 days'),
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
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 16),

        // Pie Chart Statistics Card
        _buildPieChartCard(statistics, context),

        const SizedBox(height: 16),

        // Overdue section - show items with isTaken=false and isMissed=false
        _buildOverdueSection(recordsByDate, context),

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
          ...sortedDateKeys.map((dateKey) {
            final date = DateTime.parse(dateKey);
            final dayRecords = recordsByDate[dateKey]!;

            return DailyRecordCard(
              date: date,
              records: dayRecords,
              medicineBoxes: provider.medicineBoxes,
            );
          }),
      ],
    );
  }

  Widget _buildOverdueSection(
    Map<String, List<MedicineRecord>> recordsByDate,
    BuildContext context,
  ) {
    // Get all overdue items (isTaken=false, isMissed=false, and scheduledTime is in the past)
    final overdueRecords = <MedicineRecord>[];
    final now = DateTime.now();
    for (var dateRecords in recordsByDate.values) {
      overdueRecords.addAll(
        dateRecords.where(
          (r) => !r.isTaken && !r.isMissed && r.scheduledTime.isBefore(now),
        ),
      );
    }

    if (overdueRecords.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Colors.orange.shade700, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Overdue Medicines (${overdueRecords.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...overdueRecords.map((record) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.name ?? 'Box 1',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Scheduled: ${record.scheduledTime.hour}:${record.scheduledTime.minute.toString().padLeft(2, '0')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChartCard(
    MedicineStatistics statistics,
    BuildContext context,
  ) {
    final total =
        statistics.takenDoses +
        statistics.missedDoses +
        statistics.overduePendingDoses;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Overall Adherence',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 50,
                      sections: [
                        if (statistics.takenDoses > 0)
                          PieChartSectionData(
                            value: statistics.takenDoses.toDouble(),
                            color: const Color(0xFF66BB6A),
                            title: statistics.takenDoses.toString(),
                            radius: 40,
                            titleStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        if (statistics.missedDoses > 0)
                          PieChartSectionData(
                            value: statistics.missedDoses.toDouble(),
                            color: const Color(0xFFE53935),
                            title: statistics.missedDoses.toString(),
                            radius: 40,
                            titleStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        if (statistics.overduePendingDoses > 0)
                          PieChartSectionData(
                            value: statistics.overduePendingDoses.toDouble(),
                            color: const Color(0xFFFF9800),
                            title: statistics.overduePendingDoses.toString(),
                            radius: 40,
                            titleStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${statistics.adherenceRate.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      Text(
                        'Adherence',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[400]
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  'Total',
                  total,
                  const Color(0xFF1976D2),
                  null,
                  context,
                ),
                _buildStatColumn(
                  'Taken',
                  statistics.takenDoses,
                  const Color(0xFF66BB6A),
                  Icons.check_circle,
                  context,
                ),
                _buildStatColumn(
                  'Missed',
                  statistics.missedDoses,
                  const Color(0xFFE53935),
                  Icons.cancel,
                  context,
                ),
                _buildStatColumn(
                  'Overdue',
                  statistics.overduePendingDoses,
                  const Color(0xFFFF9800),
                  Icons.warning,
                  context,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(
    String label,
    int value,
    Color color,
    IconData? icon,
    BuildContext context,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        if (icon != null)
          Icon(icon, color: color, size: 20)
        else
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(height: 4),
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class _ReportStatistics {
  final int takenDoses;
  final int missedDoses;
  final int overduePendingDoses;
  final double adherenceRate;

  const _ReportStatistics({
    required this.takenDoses,
    required this.missedDoses,
    required this.overduePendingDoses,
    required this.adherenceRate,
  });
}
