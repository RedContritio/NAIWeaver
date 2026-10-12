import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

enum AugmentTool {
  bgRemoval('bg-removal', Icons.content_cut),
  lineart('lineart', Icons.draw),
  sketch('sketch', Icons.gesture),
  colorize('colorize', Icons.color_lens),
  emotion('emotion', Icons.mood),
  declutter('declutter', Icons.cleaning_services);

  final String apiValue;
  final IconData icon;
  const AugmentTool(this.apiValue, this.icon);

  bool get hasDefry => this == colorize || this == emotion;
  bool get hasPrompt => this == colorize || this == emotion;

  /// The tool's name in the user's language.
  String label(AppLocalizations l) => switch (this) {
    bgRemoval => l.directorToolBgRemoval,
    lineart => l.directorToolLineart,
    sketch => l.directorToolSketch,
    colorize => l.directorToolColorize,
    emotion => l.directorToolEmotion,
    declutter => l.directorToolDeclutter,
  };
}

enum EmotionMood {
  neutral('neutral'),
  happy('happy'),
  sad('sad'),
  angry('angry'),
  scared('scared'),
  surprised('surprised'),
  tired('tired'),
  excited('excited'),
  nervous('nervous'),
  thinking('thinking'),
  confused('confused'),
  shy('shy'),
  disgusted('disgusted'),
  smug('smug'),
  bored('bored'),
  laughing('laughing'),
  irritated('irritated'),
  aroused('aroused'),
  embarrassed('embarrassed'),
  worried('worried'),
  love('love'),
  determined('determined'),
  hurt('hurt'),
  playful('playful');

  final String apiValue;
  const EmotionMood(this.apiValue);

  /// The mood's name in the user's language.
  String label(AppLocalizations l) => switch (this) {
    neutral => l.moodNeutral,
    happy => l.moodHappy,
    sad => l.moodSad,
    angry => l.moodAngry,
    scared => l.moodScared,
    surprised => l.moodSurprised,
    tired => l.moodTired,
    excited => l.moodExcited,
    nervous => l.moodNervous,
    thinking => l.moodThinking,
    confused => l.moodConfused,
    shy => l.moodShy,
    disgusted => l.moodDisgusted,
    smug => l.moodSmug,
    bored => l.moodBored,
    laughing => l.moodLaughing,
    irritated => l.moodIrritated,
    aroused => l.moodAroused,
    embarrassed => l.moodEmbarrassed,
    worried => l.moodWorried,
    love => l.moodLove,
    determined => l.moodDetermined,
    hurt => l.moodHurt,
    playful => l.moodPlayful,
  };
}
