import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/main_navigation_screen.dart';
import 'providers/medicine_box_provider.dart';
import 'services/esp32_service.dart';
import 'services/reminder_service.dart';
import 'services/mqtt_service.dart';
import 'services/mqtt_medicine_listener.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with GCP Firestore
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late ESP32Service _esp32Service;
  late ReminderService _reminderService;

  @override
  void initState() {
    super.initState();
    _esp32Service = ESP32Service();
    // ReminderService will be initialized with provider in _ReminderUpdater
    _reminderService = ReminderService(esp32Service: _esp32Service);
    _reminderService.initialize();
    _reminderService.startMonitoring();

    // Auto-reconnect to last known device on app startup
    _autoReconnectDevice();
  }

  // Auto-reconnect to last known device
  void _autoReconnectDevice() async {
    print('🔌 Attempting to auto-reconnect to last device...');
    final connected = await _esp32Service.loadAndConnectToLastDevice();
    if (connected) {
      print('✅ Successfully auto-reconnected to device');
    } else {
      print('ℹ️ No previous connection found or device offline');
    }
  }

  @override
  void dispose() {
    _reminderService.dispose();
    _esp32Service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => MedicineBoxProvider()),
        ChangeNotifierProvider.value(value: _esp32Service),
        Provider.value(value: _reminderService),
      ],
      child: _ReminderUpdater(
        reminderService: _reminderService,
        esp32Service: _esp32Service,
        child: MaterialApp(
          title: 'Smart Medicine Box',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            cardTheme: CardThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            cardTheme: CardThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          home: const MainNavigationScreen(),
        ),
      ),
    );
  }
}

// Widget to keep reminder service updated with medicine boxes and initialize MQTT
class _ReminderUpdater extends StatefulWidget {
  final ReminderService reminderService;
  final ESP32Service esp32Service;
  final Widget child;

  const _ReminderUpdater({
    required this.reminderService,
    required this.esp32Service,
    required this.child,
  });

  @override
  State<_ReminderUpdater> createState() => _ReminderUpdaterState();
}

class _ReminderUpdaterState extends State<_ReminderUpdater> {
  MQTTService? _mqttService;
  bool _mqttInitialized = false;

  @override
  void initState() {
    super.initState();
    // Initialize MQTT after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_mqttInitialized && mounted) {
        _initializeMQTT();
      }
    });
  }

  void _initializeMQTT() {
    final provider = context.read<MedicineBoxProvider>();

    // Initialize existing MQTT service
    _mqttService = MQTTService(provider);
    _mqttService!.connect().then((connected) {
      if (connected) {
        print(
          '✅ MQTT service connected and listening for medicine status updates',
        );
      } else {
        print('⚠️ MQTT service failed to connect: ${_mqttService!.error}');
      }
    });

    // Initialize MQTT medicine listener for physical button events
    print('🔄 Initializing MQTT medicine listener...');
    MQTTMedicineListener()
        .initialize(provider)
        .then((_) {
          print('✅ MQTT medicine listener initialized');
        })
        .catchError((e) {
          print('❌ MQTT medicine listener error: $e');
        });

    _mqttInitialized = true;
  }

  @override
  void dispose() {
    _mqttService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MedicineBoxProvider>(
      builder: (context, provider, _) {
        // Update reminder service with provider and medicine boxes
        if (widget.reminderService.medicineBoxProvider == null) {
          // Set provider if not already set (one-time initialization)
          widget.reminderService.setMedicineBoxProvider(provider);
        }

        // Set reminder service on the provider for notification cancellation
        provider.setReminderService(widget.reminderService);

        widget.reminderService.updateMedicineBoxes(provider.medicineBoxes);
        return widget.child;
      },
    );
  }
}
