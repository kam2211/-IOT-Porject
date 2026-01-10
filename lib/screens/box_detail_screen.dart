import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/medicine_box.dart';
import '../providers/medicine_box_provider.dart';
import 'edit_medicine_box_screen.dart';

class BoxDetailScreen extends StatelessWidget {
  final MedicineBox medicineBox;

  const BoxDetailScreen({
    super.key,
    required this.medicineBox,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(medicineBox.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditMedicineBoxScreen(medicineBox: medicineBox),
                ),
              );
            },
            tooltip: 'Edit box',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              _showDeleteDialog(context);
            },
            tooltip: 'Delete box',
          ),
        ],
      ),
      body: Consumer<MedicineBoxProvider>(
        builder: (context, provider, child) {
          final box = provider.medicineBoxes.firstWhere(
            (b) => b.id == medicineBox.id,
            orElse: () => medicineBox,
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Box Information Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Box Information',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.label,
                        label: 'Name',
                        value: box.name,
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.numbers,
                        label: 'Box Number',
                        value: box.boxNumber.toString(),
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.devices,
                        label: 'Device ID',
                        value: box.deviceId ?? 'Not set',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Reminders Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Reminders',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  FilledButton.icon(
                    onPressed: () => _addReminder(context, box.id),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (box.reminderTimes.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.alarm_off,
                            size: 48,
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(128),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No reminders set',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ...(box.reminderTimes.toList()
                  ..sort((a, b) {
                    final aMinutes = a.hour * 60 + a.minute;
                    final bMinutes = b.hour * 60 + b.minute;
                    return aMinutes.compareTo(bMinutes);
                  })).map((reminder) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        Icons.alarm,
                        color: reminder.isEnabled
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      title: Text(
                        reminder.formattedTime,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: reminder.isEnabled ? null : Colors.grey,
                        ),
                      ),
                      subtitle: Text(
                        _getDaysText(reminder.daysOfWeek),
                        style: TextStyle(
                          color: reminder.isEnabled ? null : Colors.grey,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: reminder.isEnabled,
                            onChanged: (value) {
                              provider.toggleReminderEnabled(box.id, reminder.id);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () {
                              _editReminder(context, box.id, reminder);
                            },
                            tooltip: 'Edit reminder',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              _deleteReminder(context, box.id, reminder.id);
                            },
                            tooltip: 'Delete reminder',
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  String _getDaysText(List<int> days) {
    if (days.length == 7) return 'Every day';
    if (days.isEmpty) return 'No days selected';
    
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days.map((d) => dayNames[d - 1]).join(', ');
  }

  void _addReminder(BuildContext context, String boxId) async {
    final now = DateTime.now();
    int selectedHour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    int selectedMinute = now.minute;
    bool isPM = now.hour >= 12;
    bool isRepeating = true;
    Set<int> selectedDays = {1, 2, 3, 4, 5, 6, 7}; // Default to all days

    final hourController = FixedExtentScrollController(initialItem: selectedHour - 1);
    final minuteController = FixedExtentScrollController(initialItem: selectedMinute);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Set Reminder Time'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time picker
                SizedBox(
                  height: 200,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Hour and Minute pickers with highlight overlay
                      Expanded(
                        child: Stack(
                          children: [
                            // Selection highlight overlay (drawn first, behind)
                            Center(
                              child: IgnorePointer(
                                child: Container(
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer.withAlpha(250),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            // Number pickers (drawn on top)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Hour Picker (1-12)
                                Expanded(
                                  child: ListWheelScrollView.useDelegate(
                                    controller: hourController,
                                    itemExtent: 50,
                                    diameterRatio: 1.5,
                                    physics: const FixedExtentScrollPhysics(),
                                    onSelectedItemChanged: (index) {
                                      selectedHour = index + 1;
                                    },
                                    childDelegate: ListWheelChildBuilderDelegate(
                                      builder: (context, index) {
                                        if (index < 0 || index > 11) return null;
                                        return Center(
                                          child: Text(
                                            (index + 1).toString().padLeft(2, '0'),
                                            style: Theme.of(context).textTheme.headlineMedium,
                                          ),
                                        );
                                      },
                                      childCount: 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  ':',
                                  style: Theme.of(context).textTheme.headlineLarge,
                                ),
                                // Minute Picker
                                Expanded(
                                  child: ListWheelScrollView.useDelegate(
                                    controller: minuteController,
                                    itemExtent: 50,
                                    diameterRatio: 1.5,
                                    physics: const FixedExtentScrollPhysics(),
                                    onSelectedItemChanged: (index) {
                                      selectedMinute = index;
                                    },
                                    childDelegate: ListWheelChildBuilderDelegate(
                                      builder: (context, index) {
                                        if (index < 0 || index > 59) return null;
                                        return Center(
                                          child: Text(
                                            index.toString().padLeft(2, '0'),
                                            style: Theme.of(context).textTheme.headlineMedium,
                                          ),
                                        );
                                      },
                                      childCount: 60,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // AM/PM Picker (outside the Stack)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                isPM = false;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: !isPM
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'AM',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: !isPM
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () {
                              setState(() {
                                isPM = true;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isPM
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'PM',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isPM
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Repeat toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Repeat',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Switch(
                      value: isRepeating,
                      onChanged: (value) {
                        setState(() {
                          isRepeating = value;
                          if (!value) {
                            selectedDays.clear();
                          } else {
                            selectedDays = {1, 2, 3, 4, 5, 6, 7};
                          }
                        });
                      },
                    ),
                  ],
                ),
                if (isRepeating) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Repeat on',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  // Days of week selector
                  Wrap(
                    spacing: 8,
                    children: [
                      for (int day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(_getDayName(day)),
                          selected: selectedDays.contains(day),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                selectedDays.add(day);
                              } else {
                                selectedDays.remove(day);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                // Validate at least one day is selected if repeating
                if (isRepeating && selectedDays.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select at least one day'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }

                // Convert to 24-hour format
                int hour24 = selectedHour;
                if (isPM && selectedHour != 12) {
                  hour24 = selectedHour + 12;
                } else if (!isPM && selectedHour == 12) {
                  hour24 = 0;
                }
                
                Navigator.pop(context, {
                  'hour': hour24,
                  'minute': selectedMinute,
                  'daysOfWeek': selectedDays.toList()..sort(),
                });
              },
              child: const Text('Set'),
            ),
          ],
        ),
      ),
    );

    hourController.dispose();
    minuteController.dispose();

    if (result != null && context.mounted) {
      final reminder = ReminderTime(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        hour: result['hour']!,
        minute: result['minute']!,
        daysOfWeek: result['daysOfWeek'] as List<int>,
      );

      context.read<MedicineBoxProvider>().addReminderTime(boxId, reminder);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder added successfully')),
      );
    }
  }

  void _editReminder(BuildContext context, String boxId, ReminderTime existingReminder) async {
    // Convert existing 24-hour time to 12-hour format
    int hour12 = existingReminder.hour > 12 
        ? existingReminder.hour - 12 
        : (existingReminder.hour == 0 ? 12 : existingReminder.hour);
    bool isPM = existingReminder.hour >= 12;
    
    int selectedHour = hour12;
    int selectedMinute = existingReminder.minute;
    bool isRepeating = existingReminder.daysOfWeek.length > 1;
    Set<int> selectedDays = existingReminder.daysOfWeek.toSet();

    final hourController = FixedExtentScrollController(initialItem: selectedHour - 1);
    final minuteController = FixedExtentScrollController(initialItem: selectedMinute);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Reminder Time'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time picker
                SizedBox(
                  height: 200,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Center(
                              child: IgnorePointer(
                                child: Container(
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer.withAlpha(250),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: ListWheelScrollView.useDelegate(
                                    controller: hourController,
                                    itemExtent: 50,
                                    diameterRatio: 1.5,
                                    physics: const FixedExtentScrollPhysics(),
                                    onSelectedItemChanged: (index) {
                                      selectedHour = index + 1;
                                    },
                                    childDelegate: ListWheelChildBuilderDelegate(
                                      builder: (context, index) {
                                        if (index < 0 || index > 11) return null;
                                        return Center(
                                          child: Text(
                                            (index + 1).toString().padLeft(2, '0'),
                                            style: Theme.of(context).textTheme.headlineMedium,
                                          ),
                                        );
                                      },
                                      childCount: 12,
                                    ),
                                  ),
                                ),
                                Text(':', style: Theme.of(context).textTheme.headlineLarge),
                                Expanded(
                                  child: ListWheelScrollView.useDelegate(
                                    controller: minuteController,
                                    itemExtent: 50,
                                    diameterRatio: 1.5,
                                    physics: const FixedExtentScrollPhysics(),
                                    onSelectedItemChanged: (index) {
                                      selectedMinute = index;
                                    },
                                    childDelegate: ListWheelChildBuilderDelegate(
                                      builder: (context, index) {
                                        if (index < 0 || index > 59) return null;
                                        return Center(
                                          child: Text(
                                            index.toString().padLeft(2, '0'),
                                            style: Theme.of(context).textTheme.headlineMedium,
                                          ),
                                        );
                                      },
                                      childCount: 60,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ChoiceChip(
                            label: const Text('AM'),
                            selected: !isPM,
                            onSelected: (selected) {
                              setState(() => isPM = false);
                            },
                          ),
                          const SizedBox(height: 8),
                          ChoiceChip(
                            label: const Text('PM'),
                            selected: isPM,
                            onSelected: (selected) {
                              setState(() => isPM = true);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Repeat on:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: List.generate(7, (index) {
                    final day = index + 1;
                    final isSelected = selectedDays.contains(day);
                    return FilterChip(
                      label: Text(_getDayName(day)),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            selectedDays.add(day);
                          } else {
                            if (selectedDays.length > 1) {
                              selectedDays.remove(day);
                            }
                          }
                        });
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                int hour24 = selectedHour;
                if (isPM && selectedHour != 12) {
                  hour24 = selectedHour + 12;
                } else if (!isPM && selectedHour == 12) {
                  hour24 = 0;
                }
                
                Navigator.pop(context, {
                  'hour': hour24,
                  'minute': selectedMinute,
                  'daysOfWeek': selectedDays.toList()..sort(),
                });
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );

    hourController.dispose();
    minuteController.dispose();

    if (result != null && context.mounted) {
      final updatedReminder = existingReminder.copyWith(
        hour: result['hour']!,
        minute: result['minute']!,
        daysOfWeek: result['daysOfWeek'] as List<int>,
      );

      context.read<MedicineBoxProvider>().updateReminderTime(
        boxId,
        existingReminder.id,
        updatedReminder,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder updated successfully')),
      );
    }
  }

  String _getDayName(int day) {
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return dayNames[day - 1];
  }

  void _deleteReminder(BuildContext context, String boxId, String reminderId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reminder'),
        content: const Text('Are you sure you want to delete this reminder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<MedicineBoxProvider>().deleteReminderTime(boxId, reminderId);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reminder deleted')),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Medicine Box'),
        content: const Text('Are you sure you want to delete this medicine box? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<MedicineBoxProvider>().deleteMedicineBox(medicineBox.id);
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close detail screen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Medicine box deleted')),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
            ),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
