/// Run [fn] over [items] with at most [limit] in flight at once.
Future<List<T>> mapLimited<E, T>(
  Iterable<E> items,
  int limit,
  Future<T> Function(E item) fn,
) async {
  final list = items.toList();
  if (list.isEmpty) return const [];
  final workers = limit.clamp(1, list.length);
  final results = List<T?>.filled(list.length, null);
  var cursor = 0;
  Future<void> worker() async {
    while (true) {
      final i = cursor++;
      if (i >= list.length) return;
      results[i] = await fn(list[i]);
    }
  }

  await Future.wait(List.generate(workers, (_) => worker()));
  return results.cast<T>();
}
