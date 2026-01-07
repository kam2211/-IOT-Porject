import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/medicine_box_provider.dart';
import '../widgets/medicine_box_card.dart';
import '../widgets/today_doses_card.dart';
import '../widgets/esp32_connection_widget.dart';
import '../widgets/esp32_control_widget.dart';
import 'add_medicine_box_screen.dart';
import '../services/esp32_service.dart';
import 'report_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Load medicine boxes when the screen initializes
    Future.microtask(
      () => context.read<MedicineBoxProvider>().loadMedicineBoxes(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Medicine Box'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.assessment),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ReportScreen()),
              );
            },
            tooltip: 'View Reports',
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {
              context.read<MedicineBoxProvider>().syncWithDevice();
            },
            tooltip: 'Sync with device',
          ),
        ],
      ),
      body: Consumer<MedicineBoxProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.medicineBoxes.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${provider.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.loadMedicineBoxes(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (provider.medicineBoxes.isEmpty) {
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Always show ESP32 Connection Widget
                    const ESP32ConnectionWidget(),
                    const SizedBox(height: 16),
                    const ESP32ControlWidget(),
                    const SizedBox(height: 32),
                    Icon(
                      Icons.medical_services_outlined,
                      size: 80,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withAlpha(128),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No Medicine Boxes Yet',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add your first medicine box to get started',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(153),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.loadMedicineBoxes(),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount:
                  provider.medicineBoxes.length +
                  3, // +3 for ESP32 widgets and TodayDoses
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: ESP32ConnectionWidget(),
                  );
                }
                if (index == 1) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: ESP32ControlWidget(),
                  );
                }
                if (index == 2) {
                  return const TodayDosesCard();
                }
                final box = provider.medicineBoxes[index - 3];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: MedicineBoxCard(medicineBox: box),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final esp32 = context.read<ESP32Service>();
          final ip = esp32.ipAddress?.replaceAll('http://', '');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddMedicineBoxScreen(initialDeviceId: ip),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Box'),
      ),
    );
  }
}
