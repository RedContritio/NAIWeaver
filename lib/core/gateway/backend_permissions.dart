import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../features/auth/backend_auth_notifier.dart';
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

bool canUsePaidImageFeatures(BuildContext context) {
  if (!useBackendGateway) return true;
  final auth = context.watch<BackendAuthNotifier>();
  final user = auth.user;
  if (user == null) return false;
  if (!user.permissions.contains(BackendPermission.imageGeneratePaid)) {
    return false;
  }
  return auth.quota?.paid.hasRemaining ?? false;
}

bool isFreeOnlyImageUser(BuildContext context) {
  if (!useBackendGateway) return false;
  final auth = context.watch<BackendAuthNotifier>();
  final user = auth.user;
  if (user == null) return false;
  return user.permissions.contains(BackendPermission.imageGenerateFree) &&
      !canUsePaidImageFeatures(context);
}

int backendImageBatchLimit(BuildContext context) {
  if (!useBackendGateway) return 10;
  final auth = context.watch<BackendAuthNotifier>();
  final user = auth.user;
  if (user == null) return 1;
  if (user.isAdmin) return 10;
  if (canUsePaidImageFeatures(context)) return 8;
  if (user.permissions.contains(BackendPermission.imageGenerateFree)) return 4;
  return 1;
}
