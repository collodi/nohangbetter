import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_donation_buttons/donationButtons/patreonButton.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:stop_watch_timer/stop_watch_timer.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'scale_display.dart';
import 'timer.dart';

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

const website_url = "https://willy.kim";

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
      ),
      home: const StartPage(),
    );
  }
}

class StartPage extends StatelessWidget {
  const StartPage({Key? key}) : super(key: key);

  Future<void> alertCantOpenWebsite(BuildContext context) {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Error'),
            content: const Text('Sorry, I can\'t open the website.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ok'),
              ),
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const CircleAvatar(
                radius: 100,
                backgroundImage: AssetImage('images/my_photo.jpg'),
              ),
              Padding(
                padding: const EdgeInsets.all(30),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    style: TextStyle(fontSize: 20),
                    text: 'Hi! My name is Willy.'
                        '\n\n'
                        'You need a Xiaomi Mi 2 smart scale for this app. If you like this app, check out my other ideas on my website.'
                        '\n\n'
                        'For feature requests or bug reports, please open an issue on github.'
                        '\n\n'
                        'To contribute to accessible and open-source climbing technologies, consider supporting me on Patreon.',
                  ),
                ),
              ),
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: () async {
                        if (await canLaunchUrlString(website_url)) {
                          await launchUrlString(website_url);
                        } else {
                          alertCantOpenWebsite(context);
                        }
                      },
                      child: const Text('Check Out My Website'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: PatreonButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: Colors.deepOrange,
                      ),
                      patreonName: 'willykim',
                      text: 'Support Me On Patreon',
                    ),
                  ),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(70),
                      ),
                      onPressed: () {
                        Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const MainPage()));
                      },
                      child: const Text('Start App'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final ble = FlutterReactiveBle();

  StreamSubscription<DiscoveredDevice>? discover_sub;
  StreamSubscription<ConnectionStateUpdate>? conn_sub;
  StreamSubscription<List<int>>? listen_sub;
  StreamSubscription<BleStatus>? btstat_sub;

  int weight = 0;
  int weight_start = 0;
  bool pin_weight = false;

  bool bt_ready = true;
  bool conn_btn_enable = true;
  bool conn_loading = false;
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

    btstat_sub = ble.statusStream.listen((stat) {
      bt_ready = false;
      switch (stat) {
        case BleStatus.locationServicesDisabled:
          setState(() {
            conn_btn_enable = false;
            conn_text = 'location disabled';
            conn_loading = false;
          });
          break;
        case BleStatus.poweredOff:
          setState(() {
            conn_btn_enable = false;
            conn_text = 'bluetooth off';
            conn_loading = false;
          });
          break;
        case BleStatus.ready:
        case BleStatus.unauthorized: // taken care thru popup
          bt_ready = true;
          setState(() {
            conn_btn_enable = true;
            conn_text = 'connect to scale';
            conn_loading = false;
          });
          break;
        case BleStatus.unsupported:
          setState(() {
            conn_btn_enable = false;
            conn_text = 'bluetooth unsupported';
            conn_loading = false;
          });
          break;
        default:
          break;
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
    if (discover_sub != null) {
      discover_sub!.cancel();
    }
    if (btstat_sub != null) {
      btstat_sub!.cancel();
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
            title: const Text('Permissions Required'),
            content: const Text(
                'The permissions are required to communicate with the weight scale. '
                'You can grant permissions in the app settings.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ok'),
              ),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text('open settings'),
              )
            ],
          );
        });
  }

  void scanForScale(BuildContext context) {
    confirmPermissions().then((pstat) {
      if (!pstat) {
        showPermissionDialog(context);
        return;
      }

      setState(() {
        conn_btn_enable = false;
        conn_text = 'searching for scale';
        conn_loading = true;
      });

      discover_sub = ble.scanForDevices(
        withServices: [BODY_COMP_SERVICE],
        scanMode: ScanMode.lowLatency,
        requireLocationServicesEnabled: true,
      ).listen((device) {
        connectToScale(device);
      }, onError: (obj) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('bluetooth scan failed'),
            padding: EdgeInsets.all(20),
          ),
        );

        setState(() {
          conn_btn_enable = true;
          conn_text = 'connect to scale';
          conn_loading = false;
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
      conn_loading = true;
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
          conn_loading = false;
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
          if (bt_ready) {
            conn_btn_enable = true;
            conn_text = 'connect to scale';
            conn_loading = false;
          }
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

  Future<bool> confirmPermissions() async {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt < 31) {
        await Permission.locationWhenInUse.request();
        bool locationGranted = await Permission.locationWhenInUse.isGranted;
        if (!locationGranted) {
          return false;
        }

        await Permission.bluetooth.request();
        bool btGranted = await Permission.bluetooth.isGranted;
        if (!btGranted) {
          return false;
        }

        return true;
      }
    }

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
      body: SafeArea(
        child: Column(
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
                  onPressed:
                      conn_btn_enable ? () => scanForScale(context) : null,
                  child: Row(
                    children: [
                      if (conn_loading)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(0, 0, 10, 0),
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      Text(conn_text),
                    ],
                  ),
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
      ),
    );
  }
}
