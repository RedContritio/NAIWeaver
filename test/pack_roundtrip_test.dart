import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/pack_service.dart';
import 'package:naiweaver/core/services/presets.dart';
import 'package:naiweaver/core/services/styles.dart';
import 'package:naiweaver/features/director_ref/models/director_reference.dart';
import 'package:naiweaver/features/generation/models/nai_character.dart';

GenerationPreset _preset(
  String name, {
  List<NaiCharacter> characters = const [],
  List<DirectorReference> refs = const [],
}) => GenerationPreset(
  name: name,
  prompt: '1girl, __hair__, {{masterpiece}}',
  negativePrompt: 'lowres, bad anatomy',
  width: 832,
  height: 1216,
  scale: 5.5,
  steps: 28,
  sampler: 'k_euler_ancestral',
  smea: true,
  smeaDyn: false,
  decrisper: true,
  characters: characters,
  directorReferences: refs,
);

Uint8List _archiveWith(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  group('styles', () {
    test('every field survives, including the default flag', () {
      final bytes = PackService.exportPack(
        name: 'p',
        styles: [
          PromptStyle(
            name: 'Anime',
            prefix: 'masterpiece, ',
            suffix: ', best quality',
            negativeContent: 'lowres',
            isDefault: true,
          ),
          PromptStyle(name: 'Plain'),
        ],
      );
      final imported = PackService.importPack(bytes);

      expect(imported.manifest.styleCount, 2);
      final byName = {for (final s in imported.styles) s.name: s};
      expect(byName.keys, {'Anime', 'Plain'});
      expect(byName['Anime']!.prefix, 'masterpiece, ');
      expect(byName['Anime']!.suffix, ', best quality');
      expect(byName['Anime']!.negativeContent, 'lowres');
      expect(byName['Anime']!.isDefault, isTrue);
      expect(byName['Plain']!.prefix, '');
      expect(byName['Plain']!.isDefault, isFalse);
    });

    test('a style whose name has path characters still round-trips', () {
      final bytes = PackService.exportPack(
        name: 'p',
        styles: [PromptStyle(name: r'a/b\c:d?', prefix: 'x')],
      );
      final imported = PackService.importPack(bytes);
      expect(imported.styles.single.name, r'a/b\c:d?');
      expect(imported.styles.single.prefix, 'x');
    });

    test('a malformed style file is skipped without losing the others', () {
      final bytes = _archiveWith({
        'styles/good.json': jsonEncode(PromptStyle(name: 'Good').toJson()),
        'styles/bad.json': '{not json',
        'styles/nameless.json': '{"prefix": "x"}',
      });
      final imported = PackService.importPack(bytes);
      expect(imported.styles.map((s) => s.name), ['Good']);
    });
  });

  group('wildcards', () {
    test('file names and multi-line unicode content are preserved exactly', () {
      const wildcards = {
        'hair.txt': 'blonde hair\nsilver hair\n\n  indented  \n',
        '服装.txt': '水手服\n女仆装',
        'weighted.txt': '3::red\n1::blue',
      };
      final imported = PackService.importPack(
        PackService.exportPack(name: 'p', wildcards: wildcards),
      );

      expect(imported.manifest.wildcardCount, 3);
      expect(imported.wildcards, wildcards);
    });

    test('entries that try to leave the wildcard folder are dropped', () {
      final bytes = _archiveWith({
        'wildcards/ok.txt': 'fine',
        'wildcards/../escape.txt': 'bad',
        'wildcards/..\\escape2.txt': 'bad',
        'wildcards/C:evil.txt': 'bad',
      });
      expect(PackService.importPack(bytes).wildcards, {'ok.txt': 'fine'});
    });
  });

  group('generation presets', () {
    test('settings, characters and manifest count survive', () {
      final original = _preset(
        'Portrait',
        characters: [
          NaiCharacter(
            name: 'Alice',
            prompt: 'girl, blonde hair',
            uc: 'bad hands',
            center: NaiCoordinate(x: 0.3, y: 0.7),
          ),
        ],
      );
      final imported = PackService.importPack(
        PackService.exportPack(name: 'p', presets: [original]),
      );

      expect(imported.manifest.presetCount, 1);
      final back = imported.presets.single;
      expect(back.name, 'Portrait');
      expect(back.prompt, original.prompt);
      expect(back.negativePrompt, original.negativePrompt);
      expect(
        [back.width, back.height, back.scale, back.steps],
        [832.0, 1216.0, 5.5, 28.0],
      );
      expect(back.sampler, 'k_euler_ancestral');
      expect([back.smea, back.smeaDyn, back.decrisper], [true, false, true]);
      expect(back.characters.single.name, 'Alice');
      expect(back.characters.single.uc, 'bad hands');
      expect(back.characters.single.center.x, 0.3);
      expect(back.characters.single.center.y, 0.7);
    });

    test(
      'director reference images move to references/ and come back intact',
      () {
        final png = Uint8List.fromList(List.generate(300, (i) => i % 256));
        final jpg = Uint8List.fromList([255, 216, 255, 0, 1, 2, 3]);
        DirectorReference ref(String id, Uint8List bytes) => DirectorReference(
          id: id,
          originalImageBytes: bytes,
          processedBase64: 'derived-at-load',
          type: DirectorReferenceType.style,
          strength: 0.42,
          fidelity: 0.71,
          enabled: false,
        );

        final bytes = PackService.exportPack(
          name: 'p',
          presets: [
            _preset('A', refs: [ref('r1', png), ref('r2', jpg)]),
            _preset('B', refs: [ref('r3', jpg)]),
          ],
        );

        // The preset JSON must not carry the image inline.
        final archive = ZipDecoder().decodeBytes(bytes);
        expect(
          archive.files.where((f) => f.name.startsWith('references/')).length,
          3,
        );
        final presetJson = utf8.decode(
          archive.findFile('presets/A.json')!.content as List<int>,
        );
        expect(presetJson, contains('@ref:'));
        expect(presetJson, isNot(contains(base64Encode(png).substring(0, 40))));

        final imported = PackService.importPack(bytes);
        final byName = {for (final p in imported.presets) p.name: p};
        final a = byName['A']!.directorReferences;
        expect(a.map((r) => r.id), ['r1', 'r2']);
        expect(a[0].originalImageBytes, png);
        expect(a[1].originalImageBytes, jpg);
        expect(a[0].type, DirectorReferenceType.style);
        expect(
          [a[0].strength, a[0].fidelity, a[0].enabled],
          [0.42, 0.71, false],
        );
        expect(byName['B']!.directorReferences.single.originalImageBytes, jpg);
      },
    );

    test('a pointer to a missing reference file drops that preset only', () {
      final broken = _preset('Broken').toJson()
        ..['directorReferences'] = [
          {'id': 'x', 'originalImageBytes': '@ref:gone.png'},
        ];
      final bytes = _archiveWith({
        'presets/Broken.json': jsonEncode(broken),
        'presets/Fine.json': jsonEncode(_preset('Fine').toJson()),
      });
      final imported = PackService.importPack(bytes);
      expect(imported.presets.map((p) => p.name), ['Fine']);
    });
  });

  test('all three categories travel together in one pack', () {
    final bytes = PackService.exportPack(
      name: 'combo',
      description: 'd',
      presets: [_preset('P')],
      styles: [PromptStyle(name: 'S', prefix: 'x')],
      wildcards: {'w.txt': 'a\nb'},
    );
    final imported = PackService.importPack(bytes);
    expect(imported.manifest.name, 'combo');
    expect(imported.manifest.description, 'd');
    expect(
      [
        imported.manifest.presetCount,
        imported.manifest.styleCount,
        imported.manifest.wildcardCount,
      ],
      [1, 1, 1],
    );
    expect(imported.presets.single.name, 'P');
    expect(imported.styles.single.name, 'S');
    expect(imported.wildcards, {'w.txt': 'a\nb'});
  });
}
