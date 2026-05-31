// One-shot: re-audit the saved v3 wardrobe run JSONs against the updated
// audit (post-Task B). Gives a tightened v3 baseline for v3.1 to be compared
// against. Always passes; the value is the printed output.
//
// Run with:
//   flutter test test/lab/reaudit_v3_runs_test.dart --reporter=expanded

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lab/audit.dart';

void main() {
  test('re-audit v3 baseline wardrobe runs with updated audit', () {
    final files = [
      'lab/runs/modern_tokyo_mysterious_f_wardrobe_wardrobe.v3_2026-05-17T18-22-28-352614.json',
      'lab/runs/victorian_zenith_f_wardrobe_wardrobe.v3_2026-05-17T18-23-30-528103.json',
      'lab/runs/pax_romana_intimidating_m_wardrobe_wardrobe.v3_2026-05-17T18-24-20-015820.json',
    ];
    var totalBlocking = 0;
    var totalWarnings = 0;
    for (final f in files) {
      final file = File(f);
      if (!file.existsSync()) {
        print('SKIP $f (not found)');
        continue;
      }
      final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final outfits = (j['outfits'] as List).cast<Map<String, dynamic>>();
      final r = auditOutfits(outfits);
      print('=== ${j['scenario']} (re-audited under post-Task B audit) ===');
      print(r.formatted());
      print('');
      totalBlocking += r.blocking.length;
      totalWarnings += r.warnings.length;
    }
    print('TOTAL across v3 runs: $totalBlocking blocking, $totalWarnings warning(s)');
  });
}
