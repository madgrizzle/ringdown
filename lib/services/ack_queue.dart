import 'package:shared_preferences/shared_preferences.dart';

class AckQueue {
  AckQueue(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'ack_queue';

  List<int> peek() {
    final raw = _prefs.getStringList(_key) ?? const [];
    return raw.map(int.parse).toList();
  }

  Future<void> enqueue(int id) async {
    final ids = peek();
    if (!ids.contains(id)) {
      ids.add(id);
      await _prefs.setStringList(_key, ids.map((e) => e.toString()).toList());
    }
  }

  Future<void> enqueueAll(Iterable<int> more) async {
    final ids = peek();
    var changed = false;
    for (final id in more) {
      if (!ids.contains(id)) {
        ids.add(id);
        changed = true;
      }
    }
    if (changed) {
      await _prefs.setStringList(_key, ids.map((e) => e.toString()).toList());
    }
  }

  Future<void> remove(int id) async {
    final ids = peek()..remove(id);
    await _prefs.setStringList(_key, ids.map((e) => e.toString()).toList());
  }

  Future<void> clear() => _prefs.remove(_key);
}
