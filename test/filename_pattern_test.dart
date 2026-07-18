import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/utils/filename_pattern.dart';
import 'package:naiweaver/core/utils/nai_filename.dart';

void main() {
  // The reporter's example from issue #27.
  final ctx = FilenamePatternContext(
    prompt: '1girl, black hair, smile',
    seed: '12345678',
    savedAt: DateTime(2026, 6, 11, 10, 34, 15),
    albumName: 'Portraits',
    sequence: 1234,
  );

  FilenamePatternContext noAlbum({int sequence = 1}) => FilenamePatternContext(
        prompt: ctx.prompt,
        seed: ctx.seed,
        savedAt: ctx.savedAt,
        sequence: sequence,
      );

  group('single tokens', () {
    test('<prompt> sanitizes and truncates like the NAI default', () {
      expect(expandFilenamePattern('<prompt>', ctx), '1girl, black hair, smile');
      final longPrompt = 'a' * 500;
      expect(
        expandFilenamePattern(
            '<prompt>',
            FilenamePatternContext(
                prompt: longPrompt, seed: '1', savedAt: ctx.savedAt)),
        'a' * naiFilenamePromptMaxLength,
      );
      expect(
        expandFilenamePattern(
            '<prompt>',
            FilenamePatternContext(
                prompt: '2::1girl::, artist:test',
                seed: '1',
                savedAt: ctx.savedAt)),
        '2__1girl__, artist_test',
      );
    });

    test('<seed>', () {
      expect(expandFilenamePattern('<seed>', ctx), '12345678');
    });

    test('date and time parts are zero-padded', () {
      expect(expandFilenamePattern('<year>', ctx), '2026');
      expect(expandFilenamePattern('<month>', ctx), '06');
      expect(expandFilenamePattern('<day>', ctx), '11');
      expect(expandFilenamePattern('<hours>', ctx), '10');
      expect(expandFilenamePattern('<minutes>', ctx), '34');
      expect(expandFilenamePattern('<seconds>', ctx), '15');
    });

    test('<date> and <time> shorthands', () {
      expect(expandFilenamePattern('<date>', ctx), '2026-06-11');
      expect(expandFilenamePattern('<time>', ctx), '10-34-15');
    });

    test('midnight single-digit time pads fully', () {
      final midnight = FilenamePatternContext(
          prompt: 'p', seed: '1', savedAt: DateTime(2026, 1, 2, 3, 4, 5));
      expect(expandFilenamePattern('<date> <time>', midnight),
          '2026-01-02 03-04-05');
    });

    test('<digits> pads to the width of the zeros argument', () {
      expect(expandFilenamePattern('<digits:0000>', ctx), '1234');
      expect(expandFilenamePattern('<digits:000000>', ctx), '001234');
      expect(expandFilenamePattern('<digits:000>', noAlbum(sequence: 7)), '007');
      expect(expandFilenamePattern('<digits>', noAlbum(sequence: 7)), '7');
    });

    test('<digits:N> numeric width also works', () {
      expect(expandFilenamePattern('<digits:6>', ctx), '001234');
    });

    test('<digits> never truncates a sequence wider than the padding', () {
      expect(expandFilenamePattern('<digits:00>', ctx), '1234');
    });

    test('<album> uses the album name', () {
      expect(expandFilenamePattern('<album>', ctx), 'Portraits');
    });

    test('<album> is empty without an album, <album:fallback> substitutes', () {
      expect(expandFilenamePattern('x<album>x', noAlbum()), 'xx');
      expect(
          expandFilenamePattern('<album:Unsorted>', noAlbum()), 'Unsorted');
      expect(expandFilenamePattern('<album:Unsorted>', ctx), 'Portraits');
    });

    test('token names are case-insensitive', () {
      expect(expandFilenamePattern('<SEED>', ctx), '12345678');
      expect(expandFilenamePattern('<Date>', ctx), '2026-06-11');
    });
  });

  group('combined patterns', () {
    test('reproduces the exact target filename from issue #27', () {
      expect(
        expandFilenamePattern(
          '<digits:0000> <prompt> s-<seed> <year>-<month>-<day> <hours>-<minutes>-<seconds>',
          ctx,
        ),
        '1234 1girl, black hair, smile s-12345678 2026-06-11 10-34-15',
      );
    });

    test('default pattern matches naiFilenameBase for normal inputs', () {
      expect(
        expandFilenamePattern(kDefaultFilenamePattern, ctx),
        naiFilenameBase(ctx.prompt, ctx.seed),
      );
    });

    test('literal text passes through', () {
      expect(expandFilenamePattern('MyRun <seed> final', ctx),
          'MyRun 12345678 final');
    });

    test('unknown tokens stay visible (angle brackets sanitize to _)', () {
      expect(expandFilenamePattern('<sede>', ctx), '_sede_');
    });

    test('illegal characters in literals become underscores', () {
      expect(expandFilenamePattern('a:b*c<seed>', ctx), 'a_b_c12345678');
    });

    test('trailing dots and spaces are stripped', () {
      expect(expandFilenamePattern('<prompt>...', ctx),
          '1girl, black hair, smile');
    });

    test('empty expansion yields empty string for caller fallback', () {
      expect(expandFilenamePattern('', ctx), '');
      expect(
          expandFilenamePattern(
              '<album>',
              noAlbum()),
          '');
    });
  });

  group('save path patterns', () {
    test('builds the issue #27 target subfolder tree', () {
      expect(expandSavePathPattern('<year>/<month>/<day>', ctx), '2026/06/11');
    });

    test('accepts backslashes as separators', () {
      expect(expandSavePathPattern(r'<year>\<month>\<day>', ctx), '2026/06/11');
    });

    test('single-folder date pattern', () {
      expect(expandSavePathPattern('<date>', ctx), '2026-06-11');
    });

    test('empty <album> segment is dropped, not left as an empty folder', () {
      expect(expandSavePathPattern('<album>/<date>', noAlbum()), '2026-06-11');
      expect(expandSavePathPattern('<album>/<date>', ctx),
          'Portraits/2026-06-11');
    });

    test('<album:fallback> creates the fallback folder', () {
      expect(expandSavePathPattern('<album:_Assorted>/<date>', noAlbum()),
          '_Assorted/2026-06-11');
    });

    test('dot segments cannot escape the base directory', () {
      expect(expandSavePathPattern('../secret', ctx), 'secret');
      expect(expandSavePathPattern('..', ctx), '');
      expect(expandSavePathPattern('a/./b', ctx), 'a/b');
    });

    test('separators inside token values cannot create folders', () {
      final sneaky = FilenamePatternContext(
        prompt: ctx.prompt,
        seed: ctx.seed,
        savedAt: ctx.savedAt,
        albumName: r'..\..\evil',
      );
      // Backslashes in the value become underscores; the result is one odd
      // folder name, not a traversal.
      expect(expandSavePathPattern('<album>', sneaky), '.._.._evil');
    });

    test('empty pattern means no subfolder', () {
      expect(expandSavePathPattern('', ctx), '');
      expect(expandSavePathPattern('///', ctx), '');
    });

    test('illegal characters are sanitized per segment', () {
      expect(expandSavePathPattern('a:b/<seed>', ctx), 'a_b/12345678');
    });
  });
}
