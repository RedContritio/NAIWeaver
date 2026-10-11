import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/utils/resizable_lines.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PreferencesService> makeService(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    return PreferencesService(prefs, const FlutterSecureStorage());
  }

  test('main prompt keeps responsive default until first resize', () async {
    final prefs = await makeService({});
    expect(prefs.uiMainPromptLines, isNull);
  });

  test('main prompt line count persists and clamps to its bounds', () async {
    final prefs = await makeService({});

    await prefs.setUiMainPromptLines(11);
    expect(prefs.uiMainPromptLines, 11);

    await prefs.setUiMainPromptLines(999);
    expect(prefs.uiMainPromptLines, kMainPromptMaxLines);

    await prefs.setUiMainPromptLines(-1);
    expect(prefs.uiMainPromptLines, kMainPromptMinLines);
  });

  test('out-of-range stored values are clamped when read', () async {
    final prefs = await makeService({'ui_main_prompt_lines': 999});
    expect(prefs.uiMainPromptLines, kMainPromptMaxLines);
  });
}
