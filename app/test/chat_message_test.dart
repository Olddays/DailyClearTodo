import 'package:flutter_test/flutter_test.dart';

import 'package:dailyclear/domain/chat_message.dart';

void main() {
  group('ChatMessage', () {
    test('fromRow parses role and concatenates text blocks', () {
      final msg = ChatMessage.fromRow({
        'id': 1,
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': '早安，'},
          {'type': 'tool_use', 'id': 'x', 'name': 'get_today_tasks', 'input': {}},
          {'type': 'text', 'text': '今天要做什么？'},
        ],
        'created_at': '2026-07-26T00:00:00Z',
      });

      expect(msg.role, ChatRole.assistant);
      expect(msg.text, '早安，今天要做什么？');
    });

    test('unknown role strings fall back to tool', () {
      final msg = ChatMessage.fromRow({
        'id': 2,
        'role': 'tool',
        'content': <dynamic>[],
        'created_at': '2026-07-26T00:00:00Z',
      });
      expect(msg.role, ChatRole.tool);
    });

    test('local() wraps plain text as a single text block', () {
      final msg = ChatMessage.local(role: ChatRole.user, text: '早安');
      expect(msg.text, '早安');
      expect(msg.id, isNull);
    });
  });
}
