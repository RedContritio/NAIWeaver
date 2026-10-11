import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../features/auth/backend_auth_notifier.dart';
import '../l10n/l10n_extensions.dart';
import 'backend_gateway.dart';

class BackendPermission {
  static const imageGenerateFree = 'image.generate.free';
  static const imageGeneratePaid = 'image.generate.paid';
  static const imageUpscale = 'image.upscale';
  static const imageAugment = 'image.augment';
  static const imageEncodeVibe = 'image.encode_vibe';
  static const textGenerate = 'text.generate';
  static const historyRead = 'history.read';
  static const historyAll = 'history.all';
  static const adminUsers = 'admin.users';
  static const adminConfig = 'admin.config';
}

bool hasBackendPermission(BuildContext context, String permission) {
  if (!useBackendGateway) return true;
  final auth = context.watch<BackendAuthNotifier>();
  final user = auth.user;
  if (user == null) return false;
  return user.permissions.contains(permission);
}

bool hasAnyBackendPermission(
  BuildContext context,
  Iterable<String> permissions,
) {
  if (!useBackendGateway) return true;
  final auth = context.watch<BackendAuthNotifier>();
  final user = auth.user;
  if (user == null) return false;
  return permissions.any(user.permissions.contains);
}

bool canGenerateImage(BuildContext context) =>
    hasAnyBackendPermission(context, const [
      BackendPermission.imageGenerateFree,
      BackendPermission.imageGeneratePaid,
    ]);

/// Whether the account can pay red points for inputs that only a paid
/// request carries (precise references, vibes).
enum PaidImageAccess { allowed, noPermission, noRedPoints }

/// What the account may do with image generation.
class GenerationAccess {
  const GenerationAccess({required this.canFree, required this.paid});

  /// No gateway: NovelAI itself decides.
  static const unrestricted = GenerationAccess(
    canFree: true,
    paid: PaidImageAccess.allowed,
  );

  factory GenerationAccess.of(BackendAuthNotifier auth) {
    final permissions = auth.user?.permissions ?? const <String>[];
    return GenerationAccess(
      canFree: permissions.contains(BackendPermission.imageGenerateFree),
      paid: !permissions.contains(BackendPermission.imageGeneratePaid)
          ? PaidImageAccess.noPermission
          : (auth.quota?.paid.hasRemaining ?? false)
          ? PaidImageAccess.allowed
          : PaidImageAccess.noRedPoints,
    );
  }

  final bool canFree;
  final PaidImageAccess paid;

  bool get canPay => paid == PaidImageAccess.allowed;

  /// May submit a generation at all (the gateway checks the balance).
  bool get canGenerate => canFree || paid != PaidImageAccess.noPermission;

  /// Only free generations are possible.
  bool get freeOnly => canFree && !canPay;
}

GenerationAccess generationAccessOf(BackendAuthNotifier auth) =>
    useBackendGateway
    ? GenerationAccess.of(auth)
    : GenerationAccess.unrestricted;

bool canUsePaidImageFeatures(BuildContext context) {
  if (!useBackendGateway) return true;
  return GenerationAccess.of(context.watch<BackendAuthNotifier>()).canPay;
}

bool isFreeOnlyImageUser(BuildContext context) {
  if (!useBackendGateway) return false;
  return GenerationAccess.of(context.watch<BackendAuthNotifier>()).freeOnly;
}

/// The NovelAI tools that are charged a fixed number of red points.
enum PaidTool { upscale, augment, encodeVibe }

/// The most red points [count] runs of [tool] can cost this user
/// (`rules.tool_caps`), shown where the tool is started; null outside the
/// gateway.
String? paidToolCapLabel(BuildContext context, PaidTool tool, {int count = 1}) {
  if (!useBackendGateway) return null;
  final caps = context.watch<BackendAuthNotifier>().rules?.toolCaps;
  if (caps == null) return null;
  return context.l.toolMaxRedPoints(
    count *
        switch (tool) {
          PaidTool.upscale => caps.upscale,
          PaidTool.augment => caps.augment,
          PaidTool.encodeVibe => caps.encodeVibe,
        },
  );
}

int backendImageBatchLimit(BuildContext context) {
  if (!useBackendGateway) return 10;
  // The gateway resolves the limit per user (docs/GATEWAY_CONTRACT.md §2).
  // GenerationNotifier.clampBatchCount caps every batch at 10, so the UI does
  // too.
  final limit = context.watch<BackendAuthNotifier>().rules?.batchLimit ?? 1;
  return limit > 10 ? 10 : limit;
}
