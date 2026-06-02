import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/features/generation/models/nai_character.dart';
import 'package:naiweaver/features/generation/services/character_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PreferencesService> makeService(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    return PreferencesService(prefs, const FlutterSecureStorage());
  }

  // ── Insert-target preference ─────────────────────────────────────────────
  group('charInsertTarget preference', () {
    test('defaults to "editor" (new behavior is opt-out)', () async {
      final prefs = await makeService({});
      expect(prefs.charInsertTarget, 'editor');
    });

    test('round-trips a stored value', () async {
      final prefs = await makeService({'char_insert_target': 'main'});
      expect(prefs.charInsertTarget, 'main');
      await prefs.setCharInsertTarget('editor');
      expect(prefs.charInsertTarget, 'editor');
    });

    test('is included in the backup/export allowlist', () async {
      final prefs = await makeService({'char_insert_target': 'main'});
      expect(prefs.exportableSettings().containsKey('char_insert_target'), isTrue);
    });
  });

  // ── CharacterManager: populated add + cap ────────────────────────────────
  group('CharacterManager.addCharacter (populated)', () {
    late CharacterManager manager;

    setUp(() async {
      final prefs = await makeService({});
      manager = CharacterManager(prefs: prefs);
    });

    test('passes name/prompt/uc through to the new card', () {
      final result = manager.addCharacter(
        const [],
        name: 'Sarah',
        prompt: '1girl, blonde hair',
        uc: 'bad hands',
      );
      expect(result, isNotNull);
      expect(result!.length, 1);
      expect(result.last.name, 'Sarah');
      expect(result.last.prompt, '1girl, blonde hair');
      expect(result.last.uc, 'bad hands');
    });

    test('appends without disturbing existing characters', () {
      final existing = [
        NaiCharacter(name: 'A', prompt: 'a', uc: '', center: NaiCoordinate(x: 0.5, y: 0.5)),
      ];
      final result = manager.addCharacter(existing, name: 'B', prompt: 'b');
      expect(result, isNotNull);
      expect(result!.map((c) => c.name), ['A', 'B']);
      // Original list is not mutated.
      expect(existing.length, 1);
    });

    test('returns null at the 6-character maximum', () {
      final full = List.generate(
        CharacterManager.maxCharacters,
        (i) => NaiCharacter(name: 'C$i', prompt: '', uc: '', center: NaiCoordinate(x: 0.5, y: 0.5)),
      );
      expect(manager.addCharacter(full, name: 'Overflow', prompt: 'x'), isNull);
    });
  });
}
