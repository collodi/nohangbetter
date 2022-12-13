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

  StreamSubscription<DiscoveredDevice>? discover_sub;
  StreamSubscription<ConnectionStateUpdate>? conn_sub;
  StreamSubscription<ConnectionStateUpdate>? disconn_sub;
  StreamSubscription<List<int>>? listen_sub;

  int weight = 0;
  int weight_start = 0;
  bool pin_weight = false;

  bool conn_btn_enable = true;
  String conn_text = 'connect to scale';

  final StopWatchTimer timer = StopWatchTimer();
  late StreamSubscription<bool> timer_stop_sub;

  @override
  void initState() {
    super.initState();

    timer_stop_sub = timer.fetchStopped.listen((stopped) {
      if (stopped) {
        setState(() {
          timer.onResetTimer();
        });
      }
    });
  }

  @override
  void dispose() async {
    if (listen_sub != null) {
      listen_sub!.cancel();
    }
    if (conn_sub != null) {
      conn_sub!.cancel();
    }
    if (disconn_sub != null) {
      disconn_sub!.cancel();
    }
    if (discover_sub != null) {
      discover_sub!.cancel();
    }
    timer_stop_sub.cancel();
    await timer.dispose();

    super.dispose();
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

      setState(() {
        conn_btn_enable = false;
        conn_text = 'searching for scale';
      });

      discover_sub = ble.scanForDevices(
        withServices: [BODY_COMP_SERVICE],
        scanMode: ScanMode.lowLatency,
        requireLocationServicesEnabled: true,
      ).listen((device) {
        connectToScale(device);
      }, onError: (obj) {
        print('bt scan error!');
        print(obj);
        // TODO toast 'failed to scan for scale'

        setState(() {
          conn_btn_enable = false;
          conn_text = 'searching for scale';
        });
      });
    });
  }

  // code for local BT status change (permissions, etc.)
  // _ble.statusStream.listen((status) {
  //
  // });

  void connectToScale(DiscoveredDevice device) {
    discover_sub!.cancel();
    setState(() {
      conn_btn_enable = false;
      conn_text = 'connecting';
    });

    if (conn_sub != null) {
      conn_sub!.cancel();
    }

    conn_sub = ble.connectToDevice(id: device.id).listen((stat) {
      print(stat);

      if (stat.connectionState == DeviceConnectionState.connected) {
        setState(() {
          conn_btn_enable = false;
          conn_text = 'connected';
        });

        final characteristic = QualifiedCharacteristic(
            characteristicId: WEIGHT_MEASUREMENT_CHAR,
            serviceId: BODY_COMP_SERVICE,
            deviceId: stat.deviceId);

        if (listen_sub != null) {
          listen_sub!.cancel();
        }

        listen_sub =
            ble.subscribeToCharacteristic(characteristic).listen(listenToScale);
      } else if (stat.connectionState == DeviceConnectionState.disconnected &&
          listen_sub != null) {
        listen_sub!.cancel();
        listen_sub = null;

        setState(() {
          conn_btn_enable = true;
          conn_text = 'connect to scale';
        });
      }
    });
  }

  void listenToScale(value) {
    int weightJin = (value[12] << 8) + value[11]; // TODO it's not always in jin
    int weightLbs = ((weightJin / 200.0) * 2.2046).toInt();

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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text(
                  'pin weight',
                  style: TextStyle(fontSize: 20),
                ),
                Switch(
                  value: pin_weight,
                  onChanged: (value) {
                    setState(() {
                      pin_weight = value;
                      weight_start = value ? weight : 0;
                    });
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 30),
                  child: Icon(
                    Icons.monitor_weight,
                    size: 30,
                  ),
                ),
                Expanded(
                  child: WeightDisplay(weight),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 30),
                  child: Icon(
                    Icons.fitness_center,
                    size: 30,
                  ),
                ),
                LoadDisplayLbs(weight_start, weight),
                LoadDisplayPerc(weight_start, weight),
              ],
            ),
          ),
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
                onPressed: conn_btn_enable ? () => scanForScale(context) : null,
                child: Text(conn_text),
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
                    } else {
                      timer.onStartTimer();
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
