import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/reference_library_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../models/director_reference.dart';
import '../providers/director_ref_notifier.dart';
import '../../generation/widgets/billing_text.dart';
import 'reference_add_actions.dart';
import 'reference_fields.dart';
import 'reference_library_manager.dart';

/// Tools → References → Precise references.
class DirectorRefManager extends StatelessWidget {
  const DirectorRefManager({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DirectorRefNotifier>();
    final t = context.t;
    final l = context.l;
    final refs = notifier.references;

    return ReferenceLibraryManager<DirectorReference, SavedDirectorRef>(
      items: refs,
      itemBuilder: (context, ref, onSave) {
        final accent = refTypeColor(t, ref.type);
        return ReferenceItemCard(
          key: ValueKey(ref.id),
          image: ref.originalImageBytes,
          accent: accent,
          enabled: ref.enabled,
          onToggleEnabled: () => notifier.toggleEnabled(ref.id),
          saveTooltip: l.refSaveReference,
          onSave: onSave,
          onRemove: () => notifier.removeReference(ref.id),
          pausedReason: notifier.isPaused(ref)
              ? pausedReasonText(l, notifier.access)
              : null,
          children: [
            DirectorRefTypeSelector(
              type: ref.type,
              onChanged: (type) => notifier.updateType(ref.id, type),
            ),
            const SizedBox(height: 12),
            ReferenceSliderField(
              label: l.refStrength,
              value: ref.strength,
              accent: accent,
              onChanged: (v) => notifier.updateStrength(ref.id, v),
            ),
            const SizedBox(height: 8),
            ReferenceSliderField(
              label: l.refFidelity,
              value: ref.fidelity,
              accent: accent,
              onChanged: (v) => notifier.updateFidelity(ref.id, v),
            ),
          ],
        );
      },
      countLabel: l.refReferenceCount(refs.length),
      onClearAll: refs.isEmpty ? null : notifier.clearAll,
      emptyIcon: Icons.photo_library_outlined,
      emptyTitle: l.refNoReferencesAdded,
      emptyDescription: l.refEmptyDescription,
      addLabel: l.refAddReference,
      onAdd: () => pickAndAddReferences(context),
      isProcessing: notifier.isProcessing,
      slot: ReferenceLibrarySlot.directorRefs,
      saveTitle: l.refSaveReference,
      toSaved: (ref, name) =>
          SavedDirectorRef(name: name, reference: ref, savedAt: DateTime.now()),
      onLoadSaved: (saved) => addSavedReference(context, saved),
      savedName: (saved) => saved.name,
      savedImage: (saved) => saved.reference.originalImageBytes,
      savedSummary: (saved) {
        final ref = saved.reference;
        return '${localizedRefType(l, ref.type)}  '
            '${l.refStrengthShort} ${ref.strength.toStringAsFixed(2)}  '
            '${l.refFidelityShort} ${ref.fidelity.toStringAsFixed(2)}';
      },
      accent: t.accentRefCharacter,
    );
  }
}
