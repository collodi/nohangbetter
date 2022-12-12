import 'dart:math';

import 'package:flutter/material.dart';

class WeightDisplay extends StatelessWidget {
  const WeightDisplay(this.weight, {Key? key}) : super(key: key);

  final int weight;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  weight.toString(),
                  style: const TextStyle(fontSize: 50),
                ),
                const Text(
                  ' lbs',
                  style: TextStyle(fontSize: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LoadDisplay extends StatelessWidget {
  const LoadDisplay(this.weight_start, this.weight, {Key? key})
      : super(key: key);

  final int weight_start;
  final int weight;

  @override
  Widget build(BuildContext context) {
    final int load = max(0, weight_start - weight);
    final int load_perc =
        weight_start > 0 ? (load / weight_start * 100).toInt() : 0;

    return Padding(
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
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  load.toString(),
                  style: const TextStyle(fontSize: 50),
                ),
                const Text(
                  ' lbs',
                  style: TextStyle(fontSize: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  load_perc.toString(),
                  style: const TextStyle(fontSize: 50),
                ),
                const Text(
                  ' %',
                  style: TextStyle(fontSize: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
