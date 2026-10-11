import '../../../l10n/app_localizations.dart';
import 'jukebox_soundfont.dart';

extension JukeboxSoundFontL10n on JukeboxSoundFont {
  /// The soundfont's one-line description in the UI language. Falls back to
  /// the registry's English text for ids without a translation.
  String localizedDescription(AppLocalizations l) => switch (id) {
        'nes_chiptune' => l.soundfontDescNes,
        'generaluser_gs' => l.soundfontDescGeneralUser,
        'cat_screams' => l.soundfontDescCat,
        'snes_expressive' => l.soundfontDescSnes,
        'genesis_ym2612' => l.soundfontDescGenesis,
        'n64_roxie' => l.soundfontDescN64Roxie,
        'n64_sdk' => l.soundfontDescN64Sdk,
        _ => description,
      };
}
