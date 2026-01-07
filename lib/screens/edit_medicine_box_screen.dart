import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/medicine_box.dart';
import '../providers/medicine_box_provider.dart';

class EditMedicineBoxScreen extends StatefulWidget {
  final MedicineBox medicineBox;

  const EditMedicineBoxScreen({
    super.key,
    required this.medicineBox,
  });

  @override
  State<EditMedicineBoxScreen> createState() => _EditMedicineBoxScreenState();
}

class _EditMedicineBoxScreenState extends State<EditMedicineBoxScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _deviceIdController;
  late int _selectedBoxNumber;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.medicineBox.name);
    _deviceIdController = TextEditingController(text: widget.medicineBox.deviceId ?? '');
    _selectedBoxNumber = widget.medicineBox.boxNumber;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  void _saveChanges() {
    if (_formKey.currentState!.validate()) {
      final updatedBox = widget.medicineBox.copyWith(
        name: _nameController.text,
        boxNumber: _selectedBoxNumber,
        deviceId: _deviceIdController.text.isEmpty ? null : _deviceIdController.text,
      );

      context.read<MedicineBoxProvider>().updateMedicineBox(
        widget.medicineBox.id,
        updatedBox,
      );
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine box updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Medicine Box'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Medicine Name',
                hintText: 'e.g., Morning Pills',
                prefixIcon: Icon(Icons.medication),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a medicine name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _selectedBoxNumber,
              decoration: const InputDecoration(
                labelText: 'Box Number',
                prefixIcon: Icon(Icons.numbers),
                border: OutlineInputBorder(),
              ),
              items: List.generate(10, (index) => index + 1)
                  .map((num) => DropdownMenuItem(
                        value: num,
                        child: Text('Box #$num'),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedBoxNumber = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _deviceIdController,
              decoration: const InputDecoration(
                labelText: 'Device ID (Optional)',
                hintText: 'e.g., ESP32_001',
                prefixIcon: Icon(Icons.devices),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saveChanges,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
