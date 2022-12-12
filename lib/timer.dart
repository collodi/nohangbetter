import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soundpool/soundpool.dart';
import 'package:sprintf/sprintf.dart';
import 'package:stop_watch_timer/stop_watch_timer.dart';

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

  Soundpool pool = Soundpool.fromOptions(
    options: const SoundpoolOptions(streamType: StreamType.music),
  );

  late int beepId;
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

    timer_sec_sub = widget.timer.secondTime.listen((sec) {
      int anyLeft = leftInAny(sec * 1000) ~/ 1000;
      if (0 <= anyLeft && anyLeft <= 3) {
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

  int leftInPrepare(int time) {
    return prepare - time;
  }

  int leftInWork(int time) {
    final int t = (time - prepare) % (work + rest);
    return work - t;
  }

  int leftInRest(int time) {
    final int t = (time - prepare - work) % (work + rest);
    return rest - t;
  }

  int leftInAny(int time) {
    final prepLeft = leftInPrepare(time);
    if (prepLeft >= 0) {
      return prepLeft;
    }

    final workLeft = leftInWork(time);
    final restLeft = leftInRest(time);

    final minLeft = min(workLeft, restLeft);
    if (minLeft >= 0) {
      return minLeft;
    }

    return max(workLeft, restLeft);
  }

  bool isDone(int time) {
    final int finish = prepare + (work + rest) * nsets - rest;
    return time >= finish;
  }

  int getCurrentSet(int time) {
    if (time < prepare + work) {
      return nsets;
    }

    time = time - (prepare + work);
    return nsets - time ~/ (work + rest) - 1;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: widget.timer.rawTime,
      initialData: widget.timer.rawTime.value,
      builder: (context, snap) {
        int time = snap.data!;
        if (isDone(time) || !widget.timer.isRunning) {
          widget.timer.onStopTimer();
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(height: 30),
              NumberInput(
                nsets_controller,
                init: nsets,
                label: 'sets',
                maxValue: 20,
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
              const SizedBox(height: 30),
            ],
          );
        }

        int set = getCurrentSet(time);

        int prepLeft = leftInPrepare(time);
        if (prepLeft > 0) {
          return TimerDisplay(Colors.amber, "prepare", prepLeft, set);
        }

        int workLeft = leftInWork(time);
        if (workLeft > 0) {
          return TimerDisplay(Colors.lightGreen, "work", workLeft, set);
        }

        int restLeft = leftInRest(time);
        return TimerDisplay(Colors.lightBlue, "rest", restLeft, set);
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
            ElevatedButton(
              onPressed: () {
                setState(() {
                  value = max(value - 1, 0);
                  widget.controller.add(value);
                });
              },
              child: const Text(
                '-',
                style: TextStyle(fontSize: 20),
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
            ElevatedButton(
              onPressed: () {
                setState(() {
                  value = min(value + 1, widget.maxValue);
                  widget.controller.add(value);
                });
              },
              child: const Text(
                '+',
                style: TextStyle(fontSize: 20),
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
