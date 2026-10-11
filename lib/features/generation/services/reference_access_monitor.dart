import 'package:flutter/foundation.dart';

import '../../../core/gateway/backend_permissions.dart';
import '../../director_ref/providers/director_ref_notifier.dart';
import '../../vibe_transfer/providers/vibe_transfer_notifier.dart';

/// Tells the user, once, that references and vibes were paused or resumed.
class ReferenceAccessNotice {
  const ReferenceAccessNotice({
    required this.access,
    required this.references,
    required this.vibes,
  });

  /// Access after the change; [PaidImageAccess.allowed] means they resumed.
  final PaidImageAccess access;

  /// How many references and vibes the change affects.
  final int references;
  final int vibes;

  bool get resumed => access == PaidImageAccess.allowed;
}

/// Hands the account's paid-input access to the reference and vibe lists
/// (which pause their items while it is missing, never deleting them) and
/// reports each change of that access once through [notice].
class ReferenceAccessMonitor extends ChangeNotifier {
  ReferenceAccessMonitor({required this.references, required this.vibes});

  final DirectorRefNotifier references;
  final VibeTransferNotifier vibes;

  PaidImageAccess? _access;
  ReferenceAccessNotice? _notice;

  /// The change nobody has been told about yet.
  ReferenceAccessNotice? get notice => _notice;

  void update(PaidImageAccess access) {
    final previous = _access;
    _access = access;
    references.updateAccess(access);
    vibes.updateAccess(access);
    if (previous == null) return;
    final wasAllowed = previous == PaidImageAccess.allowed;
    final isAllowed = access == PaidImageAccess.allowed;
    if (wasAllowed == isAllowed) return;
    final enabledReferences = references.references
        .where((r) => r.enabled)
        .length;
    final enabledVibes = vibes.vibes.where((v) => v.enabled).length;
    if (enabledReferences + enabledVibes == 0) return;
    _notice = ReferenceAccessNotice(
      access: access,
      references: enabledReferences,
      vibes: enabledVibes,
    );
    notifyListeners();
  }

  /// The notice was shown.
  void acknowledge() {
    if (_notice == null) return;
    _notice = null;
  }
}
