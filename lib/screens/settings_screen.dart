import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../acknowledgements.dart';
import '../models/filters.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/update_provider.dart';
import '../services/api_client.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    });
  }

  Future<void> _editServer() async {
    final current = ref.read(authProvider).serverUrl ?? '';
    final controller = TextEditingController(text: current);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server URL'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://api.phionalerter.com',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Check & save'),
          ),
        ],
      ),
    );
    if (next == null || next.trim().isEmpty) return;
    try {
      await ref.read(authProvider.notifier).saveServerUrl(next);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server URL saved. Sign in again.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Signed in as'),
            subtitle: Text(auth.username ?? auth.lastUsername ?? '—'),
          ),
          ListTile(
            title: const Text('Inbox'),
            subtitle: Text(auth.inboxEmail ?? '—'),
          ),
          ListTile(
            title: const Text('Server URL'),
            subtitle: Text(auth.serverUrl ?? '—'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editServer,
          ),
          const Divider(),
          const ListTile(title: Text('Theme')),
          RadioGroup<ThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (mode) {
              if (mode != null) {
                ref.read(settingsProvider.notifier).setThemeMode(mode);
              }
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text('Dark'),
                  value: ThemeMode.dark,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Light'),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('System'),
                  value: ThemeMode.system,
                ),
              ],
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Hide cleared by default'),
            subtitle: const Text(
              'When you open the alarm list, skip alarms that have already returned to normal. Turn this off if you still want to see those until you hide them yourself.',
            ),
            isThreeLine: true,
            value: settings.filters.hideCleared,
            onChanged: (v) {
              ref.read(settingsProvider.notifier).setFilters(
                    settings.filters.copyWith(hideCleared: v),
                  );
            },
          ),
          if (kShowAcknowledgements)
            SwitchListTile(
              title: const Text('Unacked only by default'),
              subtitle: const Text(
                'When you open the alarm list, show only alarms that still need an ACK. Acknowledged alarms stay off the list until you turn this off.',
              ),
              isThreeLine: true,
              value: settings.filters.unackedOnly,
              onChanged: (v) {
                ref.read(settingsProvider.notifier).setFilters(
                      settings.filters.copyWith(unackedOnly: v),
                    );
              },
            ),
          ListTile(
            title: const Text('Default sort'),
            subtitle: Text(settings.filters.sort.userFacingLabel),
            onTap: () async {
              final modes = [
                for (final mode in SortMode.values)
                  if (kShowAcknowledgements || !mode.isAcknowledgementSort)
                    mode,
              ];
              final next = await showModalBottomSheet<SortMode>(
                context: context,
                builder: (context) => ListView(
                  children: [
                    for (final s in modes)
                      ListTile(
                        title: Text(s.label),
                        onTap: () => Navigator.pop(context, s),
                      ),
                  ],
                ),
              );
              if (next != null) {
                await ref.read(settingsProvider.notifier).setFilters(
                      settings.filters.copyWith(sort: next),
                    );
              }
            },
          ),
          ListTile(
            title: const Text('Notification sound & vibration'),
            subtitle: const Text(
              'Enable notifications, then set sound and vibration',
            ),
            onTap: () =>
                ref.read(notificationServiceProvider).openNotificationSettings(),
          ),
          const Divider(),
          ListTile(
            title: const Text('Sign out'),
            leading: const Icon(Icons.logout),
            onTap: () => ref.read(authProvider.notifier).logout(),
          ),
          ListTile(
            title: const Text('App version'),
            subtitle: Text(_version.isEmpty ? '…' : _version),
          ),
          ListTile(
            title: const Text('Check for updates'),
            subtitle: const Text(
              'Android opens the Play Store or an in-app update. iOS opens TestFlight.',
            ),
            onTap: () async {
              await ref.read(updateProvider.notifier).check();
              if (!context.mounted) return;
              final offer = ref.read(updateProvider).offer;
              if (offer == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('You are on the latest version')),
                );
                return;
              }
              await ref.read(updateProvider.notifier).install();
            },
          ),
        ],
      ),
    );
  }
}
