import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundpool/soundpool.dart';
import 'package:sprintf/sprintf.dart';
import 'package:stop_watch_timer/stop_watch_timer.dart';

enum IntervalStage {
  prepare,
  work,
  rest,
}

class IntervalInfo {
  int set;
  IntervalStage stage;
  int timeleft;

  IntervalInfo(this.set, this.stage, this.timeleft);
}

class TimerSetting {
  int nsets;
  int prepare;
  int work;
  int rest;
  bool onearm;

  TimerSetting(this.nsets, this.prepare, this.work, this.rest, this.onearm);
}

Future<TimerSetting> getTimerSetting() async {
  final prefs = await SharedPreferences.getInstance();

  final nsets = await prefs.getInt('nsets');
  final prepare = await prefs.getInt('prepare');
  final work = await prefs.getInt('work');
  final rest = await prefs.getInt('rest');
  final onearm = await prefs.getBool('onearm');

  return TimerSetting(
    nsets ?? 5,
    prepare ?? 5000,
    work ?? 10000,
    rest ?? 10000,
    onearm ?? false,
  );
}

TimerSetting defaultTimerSetting() {
  return TimerSetting(5, 5000, 10000, 10000, false);
}

Future<void> storeTimerSetting(TimerSetting ts) async {
  final prefs = await SharedPreferences.getInstance();

  await prefs.setInt('nsets', ts.nsets);
  await prefs.setInt('prepare', ts.prepare);
  await prefs.setInt('work', ts.work);
  await prefs.setInt('rest', ts.rest);
  await prefs.setBool('onearm', ts.onearm);
}

class IntervalTimer extends StatefulWidget {
  const IntervalTimer(this.timer, {Key? key}) : super(key: key);

  final StopWatchTimer timer;

  @override
  State<IntervalTimer> createState() => _IntervalTimerState();
}

class _IntervalTimerState extends State<IntervalTimer> {
  TimerSetting ts = defaultTimerSetting();

  Soundpool pool = Soundpool.fromOptions(
    options: const SoundpoolOptions(streamType: StreamType.music),
  );

  late int beepId, beep2Id;
  late StreamSubscription<int> timer_sec_sub;

  late StreamSubscription<int> nsets_sub;
  late StreamSubscription<int> prep_sub;
  late StreamSubscription<int> work_sub;
  late StreamSubscription<int> rest_sub;

  StreamController<int> nsets_controller = StreamController<int>();
  StreamController<int> prep_controller = StreamController<int>();
  StreamController<int> work_controller = StreamController<int>();
  StreamController<int> rest_controller = StreamController<int>();

  @override
  void initState() {
    super.initState();

    rootBundle.load("sounds/beep.wav").then((ByteData soundData) async {
      beepId = await pool.load(soundData);
    });

    rootBundle.load("sounds/doublebeep.wav").then((ByteData soundData) async {
      beep2Id = await pool.load(soundData);
    });

    timer_sec_sub = widget.timer.secondTime.listen((sec) {
      final info = getIntervalInfo(sec * 1000 - 1, ts.onearm);
      // minus 1 fixes a bug where timeleft for work is never 0
      // which breaks the beep when work is finished
      int timeleft = info.timeleft ~/ 1000;
      if (timeleft == 0 && info.stage == IntervalStage.work) {
        pool.play(beep2Id);
      } else if (timeleft <= 3) {
        pool.play(beepId);
      }
    });

    nsets_sub = nsets_controller.stream.listen((value) {
      ts.nsets = value;
      storeTimerSetting(ts);
    });

    prep_sub = prep_controller.stream.listen((value) {
      ts.prepare = value * 1000;
      storeTimerSetting(ts);
    });

    work_sub = work_controller.stream.listen((value) {
      ts.work = value * 1000;
      storeTimerSetting(ts);
    });

    rest_sub = rest_controller.stream.listen((value) {
      ts.rest = value * 1000;
      storeTimerSetting(ts);
    });
  }

  @override
  void dispose() {
    timer_sec_sub.cancel();
    pool.dispose();

    nsets_sub.cancel();
    prep_sub.cancel();
    work_sub.cancel();
    rest_sub.cancel();

    nsets_controller.close();
    prep_controller.close();
    work_controller.close();
    rest_controller.close();

    super.dispose();
  }

  IntervalInfo getIntervalInfo(int time, bool onearm) {
    return onearm ? getIntervalInfoOneArm(time) : getIntervalInfoTwoArms(time);
  }

  int getCurrentSetOneArm(int time) {
    if (time < 2 * (ts.prepare + ts.work)) {
      return 0;
    }

    time = time - 2 * (ts.prepare + ts.work);
    return time ~/ (ts.rest + 2 * ts.work + ts.prepare) + 1;
  }

  IntervalInfo getIntervalInfoOneArm(int time) {
    final set = getCurrentSetOneArm(time);
    IntervalStage stage;
    int timeleft;

    if (set == 0) {
      final timeInMiniSet = time % (ts.prepare + ts.work);
      if (timeInMiniSet <= ts.prepare) {
        stage = IntervalStage.prepare;
        timeleft = ts.prepare - timeInMiniSet;
      } else {
        stage = IntervalStage.work;
        timeleft = ts.work - (timeInMiniSet - ts.prepare);
      }
    } else {
      final timeInSet = (time - 2 * (ts.prepare + ts.work)) %
          (ts.rest + 2 * ts.work + ts.prepare);

      if (timeInSet <= ts.rest) {
        stage = IntervalStage.rest;
        timeleft = ts.rest - timeInSet;
      } else if (timeInSet <= ts.rest + ts.work) {
        stage = IntervalStage.work;
        timeleft = ts.work - (timeInSet - ts.rest);
      } else if (timeInSet <= ts.rest + ts.work + ts.prepare) {
        stage = IntervalStage.prepare;
        timeleft = ts.prepare - (timeInSet - ts.rest - ts.work);
      } else {
        stage = IntervalStage.work;
        timeleft = ts.work - (timeInSet - ts.rest - ts.work - ts.prepare);
      }
    }

    return IntervalInfo(set, stage, timeleft);
  }

  int getCurrentSetTwoArms(int time) {
    if (time < ts.prepare + ts.work) {
      return 0;
    }

    time = time - (ts.prepare + ts.work);
    return time ~/ (ts.rest + ts.work) + 1;
  }

  IntervalInfo getIntervalInfoTwoArms(int time) {
    final set = getCurrentSetTwoArms(time);
    IntervalStage stage;
    int timeleft;

    if (set == 0) {
      if (time <= ts.prepare) {
        stage = IntervalStage.prepare;
        timeleft = ts.prepare - time;
      } else {
        stage = IntervalStage.work;
        timeleft = ts.work - (time - ts.prepare);
      }
    } else {
      final timeInSet = (time - (ts.prepare + ts.work)) % (ts.work + ts.rest);
      if (timeInSet <= ts.rest) {
        stage = IntervalStage.rest;
        timeleft = ts.rest - timeInSet;
      } else {
        stage = IntervalStage.work;
        timeleft = ts.work - (timeInSet - ts.rest);
      }
    }

    return IntervalInfo(set, stage, timeleft);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: getTimerSetting(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Text(
            'loading timer settings',
            style: TextStyle(fontSize: 30),
          );
        }

        ts = snap.data!;
        return StreamBuilder<int>(
          stream: widget.timer.rawTime,
          initialData: widget.timer.rawTime.value,
          builder: (context, snap) {
            int time = snap.data!;

            IntervalInfo intervalInfo = getIntervalInfo(time, ts.onearm);
            int setLeft = ts.nsets - intervalInfo.set;

            if (setLeft == 0 || !widget.timer.isRunning) {
              widget.timer.onStopTimer();
              return Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const SizedBox(height: 20),
                  NumberInput(
                    nsets_controller,
                    init: ts.nsets,
                    label: 'sets',
                    maxValue: 99,
                  ),
                  NumberInput(
                    prep_controller,
                    label: 'prepare',
                    init: ts.prepare ~/ 1000,
                    timeFormat: true,
                    maxValue: 208860,
                  ),
                  NumberInput(
                    work_controller,
                    label: 'work',
                    init: ts.work ~/ 1000,
                    timeFormat: true,
                    maxValue: 208860,
                  ),
                  NumberInput(
                    rest_controller,
                    label: 'rest',
                    init: ts.rest ~/ 1000,
                    timeFormat: true,
                    maxValue: 208860,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text(
                          'one arm',
                          style: TextStyle(fontSize: 25),
                        ),
                        Switch(
                          value: ts.onearm,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onChanged: (val) {
                            setState(() {
                              ts.onearm = val;
                              storeTimerSetting(ts);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              );
            }

            const displayColors = [
              Colors.amber,
              Colors.lightGreen,
              Colors.lightBlue,
            ];

            return TimerDisplay(
              displayColors[intervalInfo.stage.index],
              intervalInfo.stage.name,
              intervalInfo.timeleft,
              setLeft,
            );
          },
        );
      },
    );
  }
}

class NumberInput extends StatefulWidget {
  const NumberInput(this.controller,
      {this.init = 0,
      this.label,
      this.timeFormat = false,
      this.maxValue = 100,
      Key? key})
      : super(key: key);

  final int init;
  final StreamController<int> controller;
  final String? label;
  final bool timeFormat;
  final int maxValue;

  @override
  State<NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<NumberInput> {
  late int value;
  late Timer timer;

  @override
  void initState() {
    super.initState();
    value = widget.init;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.label != null)
          Text(
            widget.label!,
            style: const TextStyle(fontSize: 25),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: GestureDetector(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      value = max(value - 1, 0);
                      widget.controller.add(value);
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(10),
                  ),
                  child: const Text(
                    '-',
                    style: TextStyle(fontSize: 20),
                  ),
                ),
                onTapDown: (TapDownDetails details) {
                  timer = Timer.periodic(const Duration(milliseconds: 30), (t) {
                    setState(() {
                      value = max(value - 1, 0);
                      widget.controller.add(value);
                    });
                  });
                },
                onTapUp: (TapUpDetails details) {
                  timer.cancel();
                },
                onTapCancel: () {
                  timer.cancel();
                },
              ),
            ),
            if (widget.timeFormat)
              Text(
                sprintf("%02d : %02d", [value ~/ 60, value % 60]),
                style: const TextStyle(fontSize: 25),
              )
            else
              Text(
                value.toString(),
                style: const TextStyle(fontSize: 25),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: GestureDetector(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      value = min(value + 1, widget.maxValue);
                      widget.controller.add(value);
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(10),
                  ),
                  child: const Text(
                    '+',
                    style: TextStyle(fontSize: 20),
                  ),
                ),
                onTapDown: (TapDownDetails details) {
                  timer = Timer.periodic(const Duration(milliseconds: 30), (t) {
                    setState(() {
                      value = min(value + 1, widget.maxValue);
                      widget.controller.add(value);
                    });
                  });
                },
                onTapUp: (TapUpDetails details) {
                  timer.cancel();
                },
                onTapCancel: () {
                  timer.cancel();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class TimerDisplay extends StatelessWidget {
  const TimerDisplay(this.color, this.word, this.time, this.set, {Key? key})
      : super(key: key);

  final Color color;
  final String word;
  final int time;
  final int set;

  @override
  Widget build(BuildContext context) {
    final displayTime = StopWatchTimer.getDisplayTime(time).substring(3);

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              set.toString(),
              style: const TextStyle(fontSize: 60),
            ),
          ),
          Expanded(
            child: FittedBox(
              alignment: Alignment.bottomCenter,
              fit: BoxFit.none,
              child: Text(
                word,
                style: const TextStyle(fontSize: 60),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: FittedBox(
              alignment: Alignment.topCenter,
              fit: BoxFit.contain,
              child: Text(displayTime),
            ),
          ),
        ],
      ),
    );
  }
}
