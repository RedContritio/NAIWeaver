import 'package:flutter_test/flutter_test.dart';

import 'test_harness.dart';

void main() {
  test('each layout remembers its own prompt height', () async {
    final prefs = await testPreferences();
    expect(prefs.uiMainPromptLinesFor('footer'), isNull);

    await prefs.setUiMainPromptLinesFor('footer', 24);
    expect(prefs.uiMainPromptLinesFor('footer'), 24);
    expect(prefs.uiMainPromptLinesFor('panel'), isNull);
    expect(prefs.uiMainPromptLinesFor('sidebar'), isNull);
  });

  test('a height saved before heights were per layout still applies', () async {
    final prefs = await testPreferences(initial: {'ui_main_prompt_lines': 9});
    expect(prefs.uiMainPromptLinesFor('sheet'), 9);

    await prefs.setUiMainPromptLinesFor('sheet', 5);
    expect(prefs.uiMainPromptLinesFor('sheet'), 5);
    expect(prefs.uiMainPromptLinesFor('footer'), 9);
  });
}
