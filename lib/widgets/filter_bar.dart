import 'package:flutter/material.dart';

import '../models/filters.dart';

class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.filters,
    required this.onChanged,
    required this.onOpenSheet,
  });

  final AlarmFilters filters;
  final ValueChanged<AlarmFilters> onChanged;
  final VoidCallback onOpenSheet;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Hide cleared'),
            selected: filters.hideCleared,
            onSelected: (v) => onChanged(filters.copyWith(hideCleared: v)),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Unacked only'),
            selected: filters.unackedOnly,
            onSelected: (v) => onChanged(filters.copyWith(unackedOnly: v)),
          ),
          const SizedBox(width: 8),
          _MenuChip<SortMode>(
            label: 'Sort: ${filters.sort.label}',
            values: SortMode.values,
            nameOf: (s) => s.label,
            onSelected: (s) => onChanged(filters.copyWith(sort: s)),
          ),
          const SizedBox(width: 8),
          _MenuChip<GroupBy>(
            label: 'Group: ${filters.groupBy.label}',
            values: GroupBy.values,
            nameOf: (s) => s.label,
            onSelected: (s) => onChanged(filters.copyWith(groupBy: s)),
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.tune, size: 18),
            label: const Text('Filters'),
            onPressed: onOpenSheet,
          ),
        ],
      ),
    );
  }
}

class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({
    required this.label,
    required this.values,
    required this.nameOf,
    required this.onSelected,
  });

  final String label;
  final List<T> values;
  final String Function(T) nameOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final v in values)
          PopupMenuItem(value: v, child: Text(nameOf(v))),
      ],
      child: Chip(
        label: Text(label),
        avatar: const Icon(Icons.expand_more, size: 18),
      ),
    );
  }
}

Future<AlarmFilters?> showFilterSheet({
  required BuildContext context,
  required AlarmFilters current,
}) {
  return showModalBottomSheet<AlarmFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      var draft = current;
      final site = TextEditingController(text: current.siteContains);
      final device = TextEditingController(text: current.deviceContains);
      final search = TextEditingController(text: current.search);
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Filter & search',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    labelText: 'Search site, device, or description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: site,
                  decoration: const InputDecoration(
                    labelText: 'Site contains',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: device,
                  decoration: const InputDecoration(
                    labelText: 'Device contains',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hide cleared'),
                  value: draft.hideCleared,
                  onChanged: (v) => setState(() {
                    draft = draft.copyWith(hideCleared: v);
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Unacked only'),
                  value: draft.unackedOnly,
                  onChanged: (v) => setState(() {
                    draft = draft.copyWith(unackedOnly: v);
                  }),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      draft.copyWith(
                        search: search.text,
                        siteContains: site.text,
                        deviceContains: device.text,
                      ),
                    );
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}
