import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:stop_watch_timer/stop_watch_timer.dart';

import 'scale_display.dart';
import 'timer.dart';

// TODO intermediate widget to make sure the location permission is granted for android

final Uuid BODY_COMP_SERVICE =
    Uuid.parse('0000181b-0000-1000-8000-00805f9b34fb');
final Uuid CURRENT_TIME_CHAR =
    Uuid.parse('00002a2b-0000-1000-8000-00805f9b34fb');
final Uuid BODY_COMP_FEATURE_CHAR =
    Uuid.parse('00002a9b-0000-1000-8000-00805f9b34fb');
final Uuid BODY_COMP_MEASUREMENT_CHAR =
    Uuid.parse('00002a9c-0000-1000-8000-00805f9b34fb');
final Uuid WEIGHT_MEASUREMENT_CHAR =
    Uuid.parse('00002a9c-0000-1000-8000-00805f9b34fb');

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.indigo,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final ble = FlutterReactiveBle();
  late StreamSubscription<DiscoveredDevice> discover_sub;
  late StreamSubscription<ConnectionStateUpdate> conn_sub;
  late StreamSubscription<List<int>> listen_sub;
  late StreamSubscription<bool> timer_stop_sub;

  int weight = 0;
  int weight_start = 0;

  final StopWatchTimer timer = StopWatchTimer();

  @override
  void initState() {
    super.initState();

    timer_stop_sub = timer.fetchStopped.listen((stopped) {
      if (stopped) {
        setState(() {
          timer.onResetTimer();
          weight_start = 0;
        });
      }
    });
  }

  Future<void> showPermissionDialog(BuildContext context) {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Connection Failed'),
            content: const Text(
                'The permissions are needed for the app to communicate with the weight scale.\n'
                'You can change the permissions in the app settings.'),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Ok')),
              TextButton(
                  onPressed: () => openAppSettings(),
                  child: const Text('Go To Settings'))
            ],
          );
        });
  }

  void scanForScale(BuildContext context) {
    confirmBlePermissions().then((pstat) {
      if (!pstat) {
        showPermissionDialog(context);
        return;
      }

      discover_sub = ble.scanForDevices(
          withServices: [BODY_COMP_SERVICE],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: true).listen((device) {
        connectToScale(device);
      }, onError: (obj) {
        print('error!');
        print(obj);
      });
    });
  }

  // code for local BT status change (permissions, etc.)
  // _ble.statusStream.listen((status) {
  //
  // });

  void connectToScale(DiscoveredDevice device) {
    print(device);
    discover_sub.pause();

    conn_sub = ble.connectToDevice(id: device.id).listen((stat) {
      print(stat);

      if (stat.connectionState == DeviceConnectionState.connected) {
        print('connected to the weight scale!');

        final characteristic = QualifiedCharacteristic(
            characteristicId: WEIGHT_MEASUREMENT_CHAR,
            serviceId: BODY_COMP_SERVICE,
            deviceId: stat.deviceId);

        listen_sub =
            ble.subscribeToCharacteristic(characteristic).listen(listenToScale);
      } else if (stat.connectionState != DeviceConnectionState.connecting) {
        listen_sub.cancel();
        conn_sub.cancel();
        discover_sub.resume();
      }
    });
  }

  void listenToScale(value) {
    print('received value');
    print(value);

    int weightJin = (value[12] << 8) + value[11]; // TODO it's not always in jin
    int weightLbs = ((weightJin / 200.0) * 2.2046).toInt();
    print(weightLbs);

    setState(() {
      weight = weightLbs;
    });
  }

  // TODO location (and different bluetooth permissions?) permission with lower android versions
  Future<bool> confirmBlePermissions() async {
    await Permission.bluetoothScan.request();
    bool scanGranted = await Permission.bluetoothScan.isGranted;
    if (!scanGranted) {
      return false;
    }

    await Permission.bluetoothConnect.request();
    bool connGranted = await Permission.bluetoothScan.isGranted;
    if (!connGranted) {
      return false;
    }

    return true;
  }

  @override
  void dispose() async {
    listen_sub.cancel();
    conn_sub.cancel();
    discover_sub.cancel();
    timer_stop_sub.cancel();
    await timer.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeightDisplay(weight),
          LoadDisplay(weight_start, weight),
          Expanded(
            child: IntervalTimer(timer),
          ),
          ButtonBar(
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  textStyle: const TextStyle(fontSize: 20),
                ),
                onPressed: () => scanForScale(context),
                child: const Text('connect to scale'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  textStyle: const TextStyle(fontSize: 20),
                ),
                onPressed: () {
                  setState(() {
                    if (timer.isRunning) {
                      timer.onResetTimer();
                      weight_start = 0;
                    } else {
                      timer.onStartTimer();
                      weight_start = weight;
                    }
                  });
                },
                child: Text(timer.isRunning ? 'stop' : 'start'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
