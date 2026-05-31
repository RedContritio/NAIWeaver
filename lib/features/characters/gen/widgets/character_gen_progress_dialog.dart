import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/theme_extensions.dart';
import '../character_gen_service.dart';
import '../providers/character_gen_notifier.dart';

/// Modal progress view for a character-generation run. Kicks the run off in
/// [initState], shows the live step text + a Cancel button, and pops itself
/// when the run finishes (returning the new character's id, or null on
/// failure/cancel — the caller reads [CharacterGenNotifier.lastError]).
class CharacterGenProgressDialog extends StatefulWidget {
  final CharacterGenForm form;
  const CharacterGenProgressDialog({super.key, required this.form});

  /// Shows the dialog and runs the generation. Returns the new character id, or
  /// null if it failed or was cancelled.
  static Future<String?> run(BuildContext context, CharacterGenForm form) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CharacterGenProgressDialog(form: form),
    );
  }

  @override
  State<CharacterGenProgressDialog> createState() => _CharacterGenProgressDialogState();
}

class _CharacterGenProgressDialogState extends State<CharacterGenProgressDialog> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Defer one frame so the dialog is mounted before we start mutating state.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final notifier = context.read<CharacterGenNotifier>();
      final id = await notifier.generate(widget.form);
      if (!mounted) return;
      Navigator.of(context).pop(id);
    });
  }

  /// Maps the coarse step to a 0..1 fraction for the bar.
  double _fractionFor(CharacterGenProgress? p) {
    if (p == null) return 0;
    switch (p.step) {
      case CharacterGenStep.preparing:
        return 0.05;
      case CharacterGenStep.generating:
        return 0.35;
      case CharacterGenStep.wardrobe:
        if (p.total != null && p.total! > 0 && p.current != null) {
          return 0.55 + 0.35 * (p.current! / p.total!);
        }
        return 0.7;
      case CharacterGenStep.saving:
        return 0.95;
      case CharacterGenStep.done:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final notifier = context.watch<CharacterGenNotifier>();
    final p = notifier.progress;
    final frac = _fractionFor(p);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text('GENERATING CHARACTER',
            style: TextStyle(
                color: t.textSecondary,
                fontSize: t.titleSize(11),
                letterSpacing: 3,
                fontWeight: FontWeight.bold)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: frac,
                backgroundColor: t.borderSubtle,
                color: t.accent,
              ),
              const SizedBox(height: 14),
              Text(
                p?.text ?? 'Preparing…',
                style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(12)),
              ),
              const SizedBox(height: 6),
              Text(
                'This makes several model calls — on a free/Tablet-tier token a '
                'long personality may take a few continuation passes.',
                style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(8.5)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: notifier.isGenerating ? () => notifier.cancel() : null,
            child: Text('CANCEL',
                style: TextStyle(color: t.accentDanger, fontSize: t.fontSize(9), letterSpacing: 1)),
          ),
        ],
      ),
    );
  }
}
