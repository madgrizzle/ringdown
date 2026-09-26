import 'package:shared_preferences/shared_preferences.dart';

class AckQueue {
  AckQueue(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'ack_queue';
  static const _ownerKey = 'ack_queue_owner';

  String? get owner => _prefs.getString(_ownerKey);

  /// Ties this queue to a technician. Switching to a different owner drops
  /// whatever was queued (it belongs to whoever was previously logged in on
  /// this device and must not flush under the new session), then records
  /// the new owner. A no-op when the owner hasn't changed.
  Future<void> setOwner(String newOwner) async {
    if (owner == newOwner) return;
    await clear();
    await _prefs.setString(_ownerKey, newOwner);
  }

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

  Future<void> clear() async {
    await _prefs.remove(_key);
    await _prefs.remove(_ownerKey);
  }
}
