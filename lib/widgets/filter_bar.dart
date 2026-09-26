import 'package:flutter/material.dart';

import '../acknowledgements.dart';
import '../models/filters.dart';
import '../priority_category.dart';

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
          if (kShowAcknowledgements) ...[
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Unacked only'),
              selected: filters.unackedOnly,
              onSelected: (v) => onChanged(filters.copyWith(unackedOnly: v)),
            ),
          ],
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Show hidden'),
            selected: filters.showHidden,
            onSelected: (v) => onChanged(filters.copyWith(showHidden: v)),
          ),
          const SizedBox(width: 8),
          ActionChip(
            label: Text(
              filters.sites.isEmpty
                  ? 'Sites: All'
                  : 'Sites: ${filters.sites.length}',
            ),
            avatar: const Icon(Icons.location_on_outlined, size: 18),
            onPressed: onOpenSheet,
          ),
          const SizedBox(width: 8),
          _MenuChip<PriorityFloor>(
            label: 'Priority: ${filters.priorityFloor.label}',
            values: PriorityFloor.values,
            nameOf: (floor) => floor.label,
            onSelected: (floor) =>
                onChanged(filters.copyWith(priorityFloor: floor)),
          ),
          const SizedBox(width: 8),
          _MenuChip<SortMode>(
            label: 'Sort: ${filters.sort.userFacingLabel}',
            values: [
              for (final mode in SortMode.values)
                if (kShowAcknowledgements || !mode.isAcknowledgementSort) mode,
            ],
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
  List<String> availableSites = const [],
}) {
  return showModalBottomSheet<AlarmFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      var draft = current;
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
                DropdownButtonFormField<PriorityFloor>(
                  initialValue: draft.priorityFloor,
                  decoration: const InputDecoration(
                    labelText: 'Minimum priority',
                    helperText: 'Shows this category and anything more urgent',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final floor in PriorityFloor.values)
                      DropdownMenuItem(
                        value: floor,
                        child: Text(floor.label),
                      ),
                  ],
                  onChanged: (floor) {
                    if (floor == null) return;
                    setState(() {
                      draft = draft.copyWith(priorityFloor: floor);
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (availableSites.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sites',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final site in availableSites)
                        FilterChip(
                          label: Text(site),
                          selected: draft.sites.contains(site),
                          onSelected: (selected) => setState(() {
                            final next = {...draft.sites};
                            if (selected) {
                              next.add(site);
                            } else {
                              next.remove(site);
                            }
                            draft = draft.copyWith(sites: next);
                          }),
                        ),
                    ],
                  ),
                  if (draft.sites.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() {
                          draft = draft.copyWith(sites: const {});
                        }),
                        child: const Text('Clear sites'),
                      ),
                    ),
                  const SizedBox(height: 4),
                ],
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
                if (kShowAcknowledgements)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Unacked only'),
                    value: draft.unackedOnly,
                    onChanged: (v) => setState(() {
                      draft = draft.copyWith(unackedOnly: v);
                    }),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show hidden'),
                  subtitle: kShowAcknowledgements
                      ? const Text('Alarms you hid still stay acknowledged')
                      : null,
                  value: draft.showHidden,
                  onChanged: (v) => setState(() {
                    draft = draft.copyWith(showHidden: v);
                  }),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      draft.copyWith(
                        search: search.text,
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
