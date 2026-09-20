import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/update_provider.dart';

class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateProvider);
    if (!state.visible || state.offer == null) return const SizedBox.shrink();
    final offer = state.offer!;
    final actionLabel = Platform.isIOS ? 'Open TestFlight' : 'Update';
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              Icons.system_update_alt,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                offer.message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(updateProvider.notifier).install(),
              child: Text(actionLabel),
            ),
            if (!offer.force)
              IconButton(
                tooltip: 'Later',
                onPressed: () => ref.read(updateProvider.notifier).dismiss(),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}
