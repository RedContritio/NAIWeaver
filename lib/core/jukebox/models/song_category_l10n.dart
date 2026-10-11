import '../../../l10n/app_localizations.dart';
import 'jukebox_song.dart';

extension SongCategoryL10n on SongCategory {
  String label(AppLocalizations l) => switch (this) {
        SongCategory.classical => l.jukeboxCategoryClassical,
        SongCategory.anime => l.jukeboxCategoryAnime,
        SongCategory.game => l.jukeboxCategoryGame,
        SongCategory.jazz => l.jukeboxCategoryJazz,
        SongCategory.ambient => l.jukeboxCategoryAmbient,
        SongCategory.holiday => l.jukeboxCategoryHoliday,
        SongCategory.meme => l.jukeboxCategoryMeme,
        SongCategory.rock => l.jukeboxCategoryRock,
        SongCategory.custom => l.jukeboxCategoryCustom,
      };
}
