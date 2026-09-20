import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Single 1 Hz clock for every visible timer. Do not start a Timer per row.
class Ticker extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    ref.onDispose(() => _timer?.cancel());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = DateTime.now();
    });
    return DateTime.now();
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (_timer != null) return;
    state = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = DateTime.now();
    });
  }
}

final tickerProvider = NotifierProvider<Ticker, DateTime>(Ticker.new);
