import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/gateway/backend_exception.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';
import 'package:naiweaver/core/services/text_gen_service.dart';
import 'package:naiweaver/features/text_gen/text_gen_error_message.dart';
import 'package:naiweaver/features/tools/widgets/tool_workspace.dart';
import 'package:naiweaver/l10n/app_localizations.dart';

void main() {
  group('ToolRunShortcut', () {
    Future<int Function()> pump(
      WidgetTester tester, {
      bool enabled = true,
    }) async {
      var runs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolRunShortcut(
              onRun: enabled ? () => runs++ : null,
              child: const TextField(maxLines: null, autofocus: true),
            ),
          ),
        ),
      );
      await tester.pump();
      return () => runs;
    }

    testWidgets('Ctrl+Enter and Cmd+Enter run the action from a text field', (
      tester,
    ) async {
      final runs = await pump(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(runs(), 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(runs(), 2);
    });

    testWidgets('plain Enter and a disabled action do nothing', (tester) async {
      final runs = await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(runs(), 0);

      final disabledRuns = await pump(tester, enabled: false);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(disabledRuns(), 0);
    });
  });

  group('error text', () {
    final zh = lookupAppLocalizations(const Locale('zh'));

    test('tool errors are localized, never the exception text', () {
      const gateway = BackendException(
        statusCode: 402,
        code: BackendErrorCode.pointsInsufficient,
        message: 'raw server text',
      );
      expect(toolErrorMessage(zh, gateway), zh.gatewayErrPointsInsufficient);
      expect(
        toolErrorMessage(zh, UnauthorizedException()),
        zh.toolErrApiKeyRejected,
      );
      expect(toolErrorMessage(zh, StateError('boom')), zh.gatewayErrUnknown);
    });

    test('text generation failures map by cause', () {
      final gateway = TextGenException(
        'Text service error (rate_limited)',
        cause: const BackendException(
          statusCode: 429,
          code: BackendErrorCode.rateLimited,
        ),
      );
      expect(textGenErrorMessage(zh, gateway), zh.gatewayErrRateLimited);

      final noToken = TextGenException('x', cause: TextGenIssue.noToken);
      expect(textGenErrorMessage(zh, noToken), zh.textGenErrNoToken);

      final direct = TextGenException(
        'NovelAI rejected the token (401).',
        statusCode: 401,
        cause: DioException(
          requestOptions: RequestOptions(path: '/oa/v1/completions'),
          response: Response(
            requestOptions: RequestOptions(path: '/oa/v1/completions'),
            statusCode: 401,
          ),
        ),
      );
      expect(textGenErrorMessage(zh, direct), zh.toolErrApiKeyRejected);
      expect(
        textGenErrorMessage(zh, TextGenException('plain')),
        zh.gatewayErrUnknown,
      );
    });
  });
}
