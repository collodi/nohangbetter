import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class IntervalTimer extends StatefulWidget {
  const IntervalTimer(this.timer, {Key? key}) : super(key: key);

  final StopWatchTimer timer;

  @override
  State<IntervalTimer> createState() => _IntervalTimerState();
}

class _IntervalTimerState extends State<IntervalTimer> {
  int nsets = 2;
  int prepare = 5000;
  int work = 10000;
  int rest = 10000;
  bool onearm = false;

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
      final info = getIntervalInfo(sec * 1000 - 1, onearm);
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
      nsets = value;
    });

    prep_sub = prep_controller.stream.listen((value) {
      prepare = value * 1000;
    });

    work_sub = work_controller.stream.listen((value) {
      work = value * 1000;
    });

    rest_sub = rest_controller.stream.listen((value) {
      rest = value * 1000;
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
    if (time < 2 * (prepare + work)) {
      return 0;
    }

    time = time - 2 * (prepare + work);
    return time ~/ (rest + 2 * work + prepare) + 1;
  }

  IntervalInfo getIntervalInfoOneArm(int time) {
    final set = getCurrentSetOneArm(time);
    IntervalStage stage;
    int timeleft;

    if (set == 0) {
      final timeInMiniSet = time % (prepare + work);
      if (timeInMiniSet <= prepare) {
        stage = IntervalStage.prepare;
        timeleft = prepare - timeInMiniSet;
      } else {
        stage = IntervalStage.work;
        timeleft = work - (timeInMiniSet - prepare);
      }
    } else {
      final timeInSet =
          (time - 2 * (prepare + work)) % (rest + 2 * work + prepare);

      if (timeInSet <= rest) {
        stage = IntervalStage.rest;
        timeleft = rest - timeInSet;
      } else if (timeInSet <= rest + work) {
        stage = IntervalStage.work;
        timeleft = work - (timeInSet - rest);
      } else if (timeInSet <= rest + work + prepare) {
        stage = IntervalStage.prepare;
        timeleft = prepare - (timeInSet - rest - work);
      } else {
        stage = IntervalStage.work;
        timeleft = work - (timeInSet - rest - work - prepare);
      }
    }

    return IntervalInfo(set, stage, timeleft);
  }

  int getCurrentSetTwoArms(int time) {
    if (time < prepare + work) {
      return 0;
    }

    time = time - (prepare + work);
    return time ~/ (rest + work) + 1;
  }

  IntervalInfo getIntervalInfoTwoArms(int time) {
    final set = getCurrentSetTwoArms(time);
    IntervalStage stage;
    int timeleft;

    if (set == 0) {
      if (time <= prepare) {
        stage = IntervalStage.prepare;
        timeleft = prepare - time;
      } else {
        stage = IntervalStage.work;
        timeleft = work - (time - prepare);
      }
    } else {
      final timeInSet = (time - (prepare + work)) % (work + rest);
      if (timeInSet <= rest) {
        stage = IntervalStage.rest;
        timeleft = rest - timeInSet;
      } else {
        stage = IntervalStage.work;
        timeleft = work - (timeInSet - rest);
      }
    }

    return IntervalInfo(set, stage, timeleft);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: widget.timer.rawTime,
      initialData: widget.timer.rawTime.value,
      builder: (context, snap) {
        int time = snap.data!;

        IntervalInfo intervalInfo = getIntervalInfo(time, onearm);
        int setLeft = nsets - intervalInfo.set;

        if (setLeft == 0 || !widget.timer.isRunning) {
          widget.timer.onStopTimer();
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(height: 20),
              NumberInput(
                nsets_controller,
                init: nsets,
                label: 'sets',
                maxValue: 99,
              ),
              NumberInput(
                prep_controller,
                label: 'prepare',
                init: prepare ~/ 1000,
                timeFormat: true,
                maxValue: 208860,
              ),
              NumberInput(
                work_controller,
                label: 'work',
                init: work ~/ 1000,
                timeFormat: true,
                maxValue: 208860,
              ),
              NumberInput(
                rest_controller,
                label: 'rest',
                init: rest ~/ 1000,
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
                      value: onearm,
                      onChanged: (val) {
                        setState(() {
                          onearm = val;
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
                  timer = Timer.periodic(const Duration(milliseconds: 60), (t) {
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
                  timer = Timer.periodic(const Duration(milliseconds: 60), (t) {
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
