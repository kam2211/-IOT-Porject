import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/medicine_box_provider.dart';
import '../widgets/medicine_box_card.dart';
import 'add_medicine_box_screen.dart';
import '../services/esp32_service.dart';

class MedicineBoxesScreen extends StatefulWidget {
  const MedicineBoxesScreen({super.key});

  @override
  State<MedicineBoxesScreen> createState() => _MedicineBoxesScreenState();
}

class _MedicineBoxesScreenState extends State<MedicineBoxesScreen> {
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
        title: const Text('Medicine Boxes'),
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
          if (provider.isLoading && provider.medicineBoxes.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (provider.error != null) {
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
                  Text(
                    'Error: ${provider.error}',
                    textAlign: TextAlign.center,
                  ),
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.medical_services_outlined,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary.withAlpha(128),
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
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.loadMedicineBoxes(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.medicineBoxes.length,
              itemBuilder: (context, index) {
                final box = provider.medicineBoxes[index];
                return MedicineBoxCard(medicineBox: box);
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
