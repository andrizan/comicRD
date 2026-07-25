import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/update_checker.dart';

enum UpdateStatus { idle, checking, available, upToDate, error }

class UpdateState {
  const UpdateState({this.status = UpdateStatus.idle, this.info});

  final UpdateStatus status;
  final UpdateInfo? info;

  UpdateState copyWith({UpdateStatus? status, UpdateInfo? info}) =>
      UpdateState(status: status ?? this.status, info: info ?? this.info);
}

class UpdateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateState();

  Future<void> checkForUpdates() async {
    state = state.copyWith(status: UpdateStatus.checking);
    final info = await UpdateChecker.check();
    if (!ref.mounted) return;
    if (info != null) {
      state = state.copyWith(status: UpdateStatus.available, info: info);
    } else {
      state = state.copyWith(status: UpdateStatus.upToDate);
    }
  }

  void dismiss() {
    state = const UpdateState(status: UpdateStatus.idle);
  }
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);
