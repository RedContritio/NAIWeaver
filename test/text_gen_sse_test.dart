import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/text_gen_service.dart';

/// Collects tokens from a parser the way [NaiTextService] does: stop on the
/// first `final` / `[DONE]`, and (optionally) truncate at a client-side stop
/// string.
List<String> drain(SseTextParser parser, List<String> chunks,
    {List<String>? stopStrings}) {
  final tokens = <String>[];
  final acc = StringBuffer();
  var done = false;

  void handle(SseEvent ev) {
    if (done) return;
    if (ev.isDone) {
      done = true;
      return;
    }
    if (ev.token.isNotEmpty) {
      final before = acc.toString();
      final candidate = before + ev.token;
      if (stopStrings != null) {
        int best = -1;
        for (final s in stopStrings) {
          if (s.isEmpty) continue;
          final idx = candidate.indexOf(s);
          if (idx >= 0 && (best == -1 || idx < best)) best = idx;
        }
        if (best >= 0) {
          final keep = candidate.substring(before.length, best);
          if (keep.isNotEmpty) {
            acc.write(keep);
            tokens.add(keep);
          }
          done = true;
          return;
        }
      }
      acc.write(ev.token);
      tokens.add(ev.token);
    }
    if (ev.isFinal) done = true;
  }

  for (final chunk in chunks) {
    for (final ev in parser.addChunk(chunk)) {
      handle(ev);
      if (done) break;
    }
    if (done) break;
  }
  if (!done) {
    final ev = parser.finish();
    if (ev != null) handle(ev);
  }
  return tokens;
}

void main() {
  group('SseTextParser', () {
    test('parses standard token events terminated by blank lines', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"token":"Hello","ptr":0,"final":false}\n\n',
        'data: {"token":" there","ptr":5,"final":false}\n\n',
        'data: {"token":"!","ptr":11,"final":true}\n\n',
      ];
      expect(drain(p, chunks), ['Hello', ' there', '!']);
    });

    test('handles data: with no space after the colon', () {
      final p = SseTextParser();
      final chunks = [
        'data:{"token":"a","final":false}\n\n',
        'data:{"token":"b","final":true}\n\n',
      ];
      expect(drain(p, chunks), ['a', 'b']);
    });

    test('stops at final:true even with trailing events', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"token":"one","final":false}\n\n',
        'data: {"token":"two","final":true}\n\n',
        'data: {"token":"three","final":false}\n\n',
      ];
      expect(drain(p, chunks), ['one', 'two']);
    });

    test('stops at a [DONE] sentinel', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"token":"x","final":false}\n\n',
        'data: [DONE]\n\n',
        'data: {"token":"y","final":false}\n\n',
      ];
      expect(drain(p, chunks), ['x']);
    });

    test('handles a bare [DONE] line without the data: prefix', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"token":"x","final":false}\n\n',
        '[DONE]\n',
      ];
      expect(drain(p, chunks), ['x']);
    });

    test('events split across chunk boundaries are reassembled', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"tok',
        'en":"split","fi',
        'nal":false}\n',
        '\n',
        'data: {"token":"!","final":true}\n\n',
      ];
      expect(drain(p, chunks), ['split', '!']);
    });

    test('ignores comment / event / id lines', () {
      final p = SseTextParser();
      final chunks = [
        ': keepalive\n',
        'event: newToken\n',
        'id: 1\n',
        'data: {"token":"ok","final":true}\n\n',
      ];
      expect(drain(p, chunks), ['ok']);
    });

    test('multi-line data values are concatenated before JSON parse', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"token":\n',
        'data: "joined","final":true}\n\n',
      ];
      expect(drain(p, chunks), ['joined']);
    });

    test('flushes a final event with no trailing blank line', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"token":"tail","final":true}\n',
      ];
      expect(drain(p, chunks), ['tail']);
    });

    test('a plain {"output":...} event is treated as a single final token', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"output":"the whole thing"}\n\n',
        'data: {"token":"ignored","final":false}\n\n',
      ];
      expect(drain(p, chunks), ['the whole thing']);
    });

    test('non-JSON garbage events are skipped, not fatal', () {
      final p = SseTextParser();
      final chunks = [
        'data: not json at all\n\n',
        'data: {"token":"good","final":true}\n\n',
      ];
      expect(drain(p, chunks), ['good']);
    });

    test('parses chat-completions delta chunks', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n',
        'data: {"choices":[{"delta":{"content":" there"}}]}\n\n',
        'data: {"choices":[{"delta":{"content":"!"},"finish_reason":"stop"}]}\n\n',
      ];
      expect(drain(p, chunks), ['Hello', ' there', '!']);
    });

    test('parses chat chunks that carry "text" instead of "delta"', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"choices":[{"text":"a"}]}\n\n',
        'data: {"choices":[{"text":"b","finish_reason":"length"}]}\n\n',
      ];
      expect(drain(p, chunks), ['a', 'b']);
    });

    test('chat stream terminated by [DONE]', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"choices":[{"delta":{"content":"x"}}]}\n\n',
        'data: [DONE]\n\n',
        'data: {"choices":[{"delta":{"content":"y"}}]}\n\n',
      ];
      expect(drain(p, chunks), ['x']);
    });

    test('an error-only event ends the stream', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"token":"partial","final":false}\n\n',
        'data: {"error":"end of stream"}\n\n',
        'data: {"token":"never","final":false}\n\n',
      ];
      expect(drain(p, chunks), ['partial']);
    });
  });

  group('client-side stop strings', () {
    test('truncates the yielded token at the first stop string', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"token":"Hello world","final":false}\n\n',
        'data: {"token":". And more.","final":false}\n\n',
        'data: {"token":"never","final":true}\n\n',
      ];
      // Stop at "." -> first token kept whole, second truncated to "".
      expect(drain(p, chunks, stopStrings: ['.']), ['Hello world']);
    });

    test('truncates mid-token when the stop string lands inside a token', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"token":"abcENDxyz","final":false}\n\n',
      ];
      expect(drain(p, chunks, stopStrings: ['END']), ['abc']);
    });

    test('no stop string => everything passes through', () {
      final p = SseTextParser();
      final chunks = [
        'data: {"token":"a.","final":false}\n\n',
        'data: {"token":"b.","final":true}\n\n',
      ];
      expect(drain(p, chunks, stopStrings: const []), ['a.', 'b.']);
    });
  });
}
