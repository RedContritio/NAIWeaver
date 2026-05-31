import 'models/jukebox_song.dart';
import 'models/jukebox_soundfont.dart';

/// Static catalog of all bundled songs and soundfonts.
class JukeboxRegistry {
  JukeboxRegistry._();

  // ──────────────────────────────────────────
  // SoundFonts
  // ──────────────────────────────────────────

  static const _sfBaseUrl =
      'https://github.com/ststoryweaver/NAIWeaver/releases/download/soundfonts-v1';

  static const List<JukeboxSoundFont> allSoundFonts = [
    // Bundled default — always available
    JukeboxSoundFont(
      id: 'nes_chiptune',
      name: 'NES Chiptune',
      description: '8-bit retro NES sounds',
      assetPath: 'assets/soundfonts/NES_Chiptune.sf2',
      filename: 'NES_Chiptune.sf2',
      fileSizeBytes: 6744228, // ~6.4 MB
    ),
    // Downloadable soundfonts
    JukeboxSoundFont(
      id: 'generaluser_gs',
      name: 'GeneralUser GS',
      description: 'High quality General MIDI soundfont',
      downloadUrl: '$_sfBaseUrl/GeneralUser_GS.sf2',
      filename: 'GeneralUser_GS.sf2',
      fileSizeBytes: 32322864, // ~30.8 MB
      sha256: 'c278464b823daf9c52106c0957f752817da0e52964817ff682fe3a8d2f8446ce',
    ),
    JukeboxSoundFont(
      id: 'cat_screams',
      name: 'Cat Meows',
      description: 'Every instrument is a meowing cat',
      downloadUrl: '$_sfBaseUrl/Cat_Screams.sf2',
      filename: 'Cat_Screams.sf2',
      fileSizeBytes: 18420, // ~18 KB
      isGag: true,
      sha256: '7e102d9b8a72da08e331e37f679f9dff3a3cb0923225cd62d3c461a0fbc34d87',
    ),
    // SNES — ExpressiveSNES (CC BY 3.0)
    JukeboxSoundFont(
      id: 'snes_expressive',
      name: 'SNES',
      description: '16-bit Super Nintendo sounds',
      downloadUrl: '$_sfBaseUrl/ExpressiveSNES.sf2',
      filename: 'ExpressiveSNES.sf2',
      fileSizeBytes: 3910878, // ~3.7 MB
      sha256: '089f7974f7049237a2521a2aa0d12215693bc2ccca5bf4882e7499d0fa8aec4a',
    ),
    // Genesis — YM2612 FM synth
    JukeboxSoundFont(
      id: 'genesis_ym2612',
      name: 'Genesis',
      description: 'Sega Genesis YM2612 FM synth',
      downloadUrl: '$_sfBaseUrl/YM2612.sf2',
      filename: 'YM2612.sf2',
      fileSizeBytes: 36940352, // ~35.2 MB
      sha256: '7cd96e44c53dca1d1b3551d47ce225c50251e92f27d54f0f1df28fe7c4c3e20e',
    ),
    // N64 — Roxie's GM Soundfont
    JukeboxSoundFont(
      id: 'n64_roxie',
      name: 'N64',
      description: 'Nintendo 64 game samples',
      downloadUrl: '$_sfBaseUrl/N64_Roxie.sf2',
      filename: 'N64_Roxie.sf2',
      fileSizeBytes: 12763946, // ~12.2 MB
      sha256: '914db339d64abdfca2f0dc9e4791de6e38130fb87dc9cc273656b94a63acaa20',
    ),
    // N64 SDK — official SDK samples
    JukeboxSoundFont(
      id: 'n64_sdk',
      name: 'N64 SDK',
      description: 'Nintendo 64 SDK default samples',
      downloadUrl: '$_sfBaseUrl/N64_SDK_Soundfont.sf2',
      filename: 'N64_SDK_Soundfont.sf2',
      fileSizeBytes: 19665110, // ~18.8 MB
      sha256: '877e7980b7094f3f95822d1aae89cc68b81fd589f38c9747d73ad5bbdcc70961',
    ),
  ];

  static JukeboxSoundFont get defaultSoundFont => allSoundFonts.first;

  static List<JukeboxSoundFont> get downloadableSoundFonts =>
      allSoundFonts.where((sf) => sf.isDownloadable).toList();

  static JukeboxSoundFont? findSoundFontById(String id) {
    for (final sf in allSoundFonts) {
      if (sf.id == id) return sf;
    }
    return null;
  }

  // ──────────────────────────────────────────
  // Songs
  // ──────────────────────────────────────────

  static const List<JukeboxSong> allSongs = [
    // --- Featured ---
    JukeboxSong(id: 'georgia_on_my_mind', title: 'Georgia on My Mind', artist: 'Ray Charles', category: SongCategory.jazz, assetPath: 'assets/midi/jazz/georgia_mind.kar', isKaraoke: true, durationSeconds: 156, isRecommended: true, recommendedProgram: 65),
    JukeboxSong(id: 'wonderful_world', title: 'What a Wonderful World', artist: 'Louis Armstrong', category: SongCategory.jazz, assetPath: 'assets/midi/jazz/wond_world.kar', isKaraoke: true, durationSeconds: 137, isRecommended: true, recommendedProgram: 65),

    // --- Rock ---
    JukeboxSong(id: 'dancing_queen', title: 'Dancing Queen', artist: 'ABBA', category: SongCategory.rock, assetPath: 'assets/midi/rock/danc_queen.kar', isKaraoke: true, durationSeconds: 237),
    JukeboxSong(id: 'redemption_song', title: 'Redemption Song', artist: 'Bob Marley', category: SongCategory.rock, assetPath: 'assets/midi/rock/redemp_sng.kar', isKaraoke: true, isRecommended: true, recommendedProgram: 85),

    // --- Jazz ---
    JukeboxSong(id: 'fly_me_to_the_moon', title: 'Fly Me to the Moon', artist: 'Frank Sinatra', category: SongCategory.jazz, assetPath: 'assets/midi/jazz/fly_moon.kar', isKaraoke: true),
    JukeboxSong(id: 'my_way', title: 'My Way', artist: 'Frank Sinatra', category: SongCategory.jazz, assetPath: 'assets/midi/jazz/my_way.kar', isKaraoke: true, durationSeconds: 206),

    // --- Meme ---
    JukeboxSong(id: 'rickroll', title: 'Never Gonna Give You Up', category: SongCategory.meme, assetPath: 'assets/midi/meme/rr.kar', isKaraoke: true, durationSeconds: 210),
    JukeboxSong(id: 'i_will_survive', title: 'I Will Survive', artist: 'Gloria Gaynor', category: SongCategory.meme, assetPath: 'assets/midi/meme/i_survive.kar', isKaraoke: true, durationSeconds: 301),
    JukeboxSong(id: 'gangstas_paradise', title: "Gangsta's Paradise", artist: 'Coolio', category: SongCategory.meme, assetPath: 'assets/midi/meme/gang_para.kar', isKaraoke: true, durationSeconds: 241),
    JukeboxSong(id: 'killing_me_softly', title: 'Killing Me Softly', artist: 'Fugees', category: SongCategory.meme, assetPath: 'assets/midi/meme/kill_soft.kar', isKaraoke: true, durationSeconds: 266),

    // --- Anime ---
    JukeboxSong(id: 'cruel_angel', title: "A Cruel Angel's Thesis", artist: 'Yoko Takahashi', category: SongCategory.anime, assetPath: 'assets/midi/anime/cruel_angel.mid', isRecommended: true),
    JukeboxSong(id: 'tank', title: 'Tank!', artist: 'Seatbelts', category: SongCategory.anime, assetPath: 'assets/midi/anime/tank.mid', isRecommended: true, recommendedProgram: 65),
    JukeboxSong(id: 'cha_la', title: 'Cha-La Head-Cha-La', artist: 'Hironobu Kageyama', category: SongCategory.anime, assetPath: 'assets/midi/anime/cha_la.mid'),
    JukeboxSong(id: 'moonlight_densetsu', title: 'Moonlight Densetsu', artist: 'DALI', category: SongCategory.anime, assetPath: 'assets/midi/anime/moonlight.mid'),
    JukeboxSong(id: 'we_are', title: 'We Are!', artist: 'Hiroshi Kitadani', category: SongCategory.anime, assetPath: 'assets/midi/anime/we_are.mid'),
    JukeboxSong(id: 'blue_bird', title: 'Blue Bird', artist: 'Ikimonogakari', category: SongCategory.anime, assetPath: 'assets/midi/anime/blue_bird.mid'),
    JukeboxSong(id: 'silhouette', title: 'Silhouette', artist: 'KANA-BOON', category: SongCategory.anime, assetPath: 'assets/midi/anime/silhouette.mid'),
    JukeboxSong(id: 'guren', title: 'Guren no Yumiya', artist: 'Linked Horizon', category: SongCategory.anime, assetPath: 'assets/midi/anime/guren.mid'),
    JukeboxSong(id: 'the_world', title: 'The WORLD', artist: 'Nightmare', category: SongCategory.anime, assetPath: 'assets/midi/anime/the_world.mid'),
    JukeboxSong(id: 'again_yui', title: 'Again', artist: 'YUI', category: SongCategory.anime, assetPath: 'assets/midi/anime/again_yui.mid'),
    JukeboxSong(id: 'change_the_world', title: 'Change the World', artist: 'V6', category: SongCategory.anime, assetPath: 'assets/midi/anime/change_wld.mid'),

    // --- Game ---
    JukeboxSong(id: 'planet_force_title', title: 'Title Theme', artist: 'Planet Force', category: SongCategory.game, assetPath: 'assets/midi/game/md_title.mid'),
    JukeboxSong(id: 'rpgmaker_field03', title: 'Field 03', artist: 'RPG Maker', category: SongCategory.game, assetPath: 'assets/midi/game/field03.mid'),
    JukeboxSong(id: 'tondemo_houki_2_obstacle', title: 'Obstacle', artist: 'Tondemo Houki 2', category: SongCategory.game, assetPath: 'assets/midi/game/obstacle.mid'),
  ];

  static List<JukeboxSong> songsByCategory(SongCategory category) {
    return allSongs.where((s) => s.category == category).toList();
  }

  static JukeboxSong? findSongById(String id) {
    for (final song in allSongs) {
      if (song.id == id) return song;
    }
    return null;
  }

  static String categoryDisplayName(SongCategory cat) {
    switch (cat) {
      case SongCategory.classical:
        return 'CLASSICAL';
      case SongCategory.anime:
        return 'ANIME';
      case SongCategory.game:
        return 'GAME';
      case SongCategory.jazz:
        return 'JAZZ';
      case SongCategory.ambient:
        return 'AMBIENT';
      case SongCategory.holiday:
        return 'HOLIDAY';
      case SongCategory.meme:
        return 'MEME';
      case SongCategory.rock:
        return 'ROCK';
      case SongCategory.custom:
        return 'CUSTOM';
    }
  }
}
