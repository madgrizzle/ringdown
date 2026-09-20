import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_update.dart';
import '../services/update_service.dart';
import 'auth_provider.dart';

class UpdateState {
  const UpdateState({this.offer, this.dismissed = false, this.checking = false});

  final AppUpdateOffer? offer;
  final bool dismissed;
  final bool checking;

  bool get visible => offer != null && (!dismissed || offer!.force);
}

class UpdateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateState();

  UpdateService get _svc => ref.read(updateServiceProvider);

  Future<void> check() async {
    if (state.checking) return;
    state = UpdateState(offer: state.offer, dismissed: state.dismissed, checking: true);
    try {
      final offer = await _svc.check();
      state = UpdateState(offer: offer, dismissed: false);
    } catch (_) {
      state = UpdateState(offer: state.offer, dismissed: state.dismissed);
    }
  }

  void dismiss() {
    if (state.offer?.force == true) return;
    state = UpdateState(offer: state.offer, dismissed: true);
  }

  Future<void> install() async {
    final offer = state.offer;
    if (offer == null) return;
    await _svc.install(offer);
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService(ref.watch(apiClientProvider));
});

final updateProvider =
    NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);
