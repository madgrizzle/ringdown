import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _timer;
  bool _showRetry = false;

  @override
  void initState() {
    super.initState();
    // Session restore normally resolves in well under this. If it hasn't,
    // something is stuck (a hung platform channel, a slow/absent network)
    // and the user was previously left staring at a spinner forever with
    // no way out.
    _timer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _showRetry = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Image(
              image: AssetImage('assets/icon/ringdown_icon_1024.png'),
              width: 96,
              height: 96,
            ),
            const SizedBox(height: 16),
            const Text(
              'Ringdown',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            if (_showRetry) ...[
              const SizedBox(height: 24),
              const Text(
                'This is taking longer than expected.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () {
                  setState(() => _showRetry = false);
                  _timer?.cancel();
                  _timer = Timer(const Duration(seconds: 10), () {
                    if (mounted) setState(() => _showRetry = true);
                  });
                  ref.read(authProvider.notifier).restore();
                },
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
