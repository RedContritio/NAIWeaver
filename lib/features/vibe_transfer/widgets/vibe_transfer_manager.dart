import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/reference_library_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../director_ref/widgets/reference_add_actions.dart';
import '../../director_ref/widgets/reference_fields.dart';
import '../../director_ref/widgets/reference_library_manager.dart';
import '../models/vibe_transfer.dart';
import '../providers/vibe_transfer_notifier.dart';

/// Tools → References → Vibe transfer.
class VibeTransferManager extends StatelessWidget {
  const VibeTransferManager({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<VibeTransferNotifier>();
    final t = context.t;
    final l = context.l;
    final vibes = notifier.vibes;
    final accent = t.accentVibeTransfer;
    final canEncode = hasBackendPermission(
      context,
      BackendPermission.imageEncodeVibe,
    );

    return ReferenceLibraryManager<VibeTransfer, SavedVibeTransfer>(
      items: vibes,
      itemBuilder: (context, vibe, onSave) => ReferenceItemCard(
        key: ValueKey(vibe.id),
        image: vibe.originalImageBytes,
        accent: accent,
        enabled: vibe.enabled,
        onToggleEnabled: () => notifier.toggleEnabled(vibe.id),
        saveTooltip: l.refSaveVibe,
        onSave: onSave,
        onRemove: () => notifier.removeVibe(vibe.id),
        children: [
          ReferenceSliderField(
            label: l.refStrength,
            value: vibe.strength,
            accent: accent,
            onChanged: (v) => notifier.updateStrength(vibe.id, v),
          ),
          const SizedBox(height: 8),
          ReferenceSliderField(
            label: l.refInfoExtracted,
            value: vibe.infoExtracted,
            accent: accent,
            onChanged: (v) => notifier.updateInfoExtracted(vibe.id, v),
          ),
        ],
      ),
      countLabel: l.refVibeCount(vibes.length),
      onClearAll: vibes.isEmpty ? null : notifier.clearAll,
      emptyIcon: Icons.music_note_outlined,
      emptyTitle: l.refNoVibesAdded,
      emptyDescription: l.refVibeEmptyDescription,
      addLabel: l.refAddVibe,
      onAdd: () => pickAndAddVibes(context),
      // Encoding is a paid gateway call; saved vibes can still be loaded.
      addDisabledReason: canEncode ? null : l.refVibeNoPermission,
      isProcessing: notifier.isProcessing,
      slot: ReferenceLibrarySlot.vibeTransfers,
      saveTitle: l.refSaveVibe,
      toSaved: (vibe, name) =>
          SavedVibeTransfer(name: name, vibe: vibe, savedAt: DateTime.now()),
      onLoadSaved: (saved) async => notifier.addFromSaved(saved),
      savedName: (saved) => saved.name,
      savedImage: (saved) => saved.vibe.originalImageBytes,
      savedSummary: (saved) =>
          '${l.refStrengthShort} ${saved.vibe.strength.toStringAsFixed(2)}  '
          '${l.refInfoExtractedShort} ${saved.vibe.infoExtracted.toStringAsFixed(2)}',
      accent: accent,
    );
  }
}
