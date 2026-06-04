import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';

void main() {
  group('sanitizePromptForNai', () {
    test('returns empty string for null', () {
      expect(sanitizePromptForNai(null), '');
    });

    test('leaves a clean prompt untouched', () {
      const prompt = '1girl, blue hair, {{masterpiece}}, best quality';
      expect(sanitizePromptForNai(prompt), prompt);
    });

    test('strips a single backslash', () {
      expect(sanitizePromptForNai('1girl, blue\\ hair'), '1girl, blue hair');
    });

    test('strips multiple and consecutive backslashes', () {
      expect(
        sanitizePromptForNai('a\\\\b\\c\\'),
        'abc',
      );
    });

    test('preserves NovelAI weighting syntax', () {
      // Braces, parens, colons and commas must survive — only `\` is removed.
      const prompt = '{{{1girl}}}, (blue hair:1.2), [low quality]';
      expect(sanitizePromptForNai(prompt), prompt);
    });

    test('strips backslash that precedes a brace (no escaping in NAI)', () {
      expect(sanitizePromptForNai('\\{not escaped\\}'), '{not escaped}');
    });
  });
}
