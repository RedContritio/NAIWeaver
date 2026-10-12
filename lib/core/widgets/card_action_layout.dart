import 'package:flutter/material.dart';

import 'ui/overlay_action_button.dart';

/// Fixed slots keep a card's action mounted while its content or badge updates.
/// Callers provide the menu; this component owns its positioning and frame.
class CardActionLayout extends StatelessWidget {
  const CardActionLayout({
    super.key,
    required this.content,
    this.badge,
    this.action,
  });

  final Widget content;
  final Widget? badge;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(key: const ValueKey('card-content'), child: content),
        Positioned(
          key: const ValueKey('card-badge'),
          left: 7,
          bottom: 7,
          child: IgnorePointer(child: badge ?? const SizedBox.shrink()),
        ),
        Positioned(
          key: const ValueKey('card-action'),
          top: 5,
          right: 5,
          child: action == null
              ? const SizedBox.shrink()
              : CardActionFrame(child: action!),
        ),
      ],
    );
  }
}

/// The same menu frame can also be used in a viewer's toolbar.
class CardActionFrame extends StatelessWidget {
  const CardActionFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => OverlayActionFrame(child: child);
}
