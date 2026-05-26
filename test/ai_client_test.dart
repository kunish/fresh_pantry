import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ai_settings.dart';
import 'package:fresh_pantry/services/ai_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _settings = AiSettings(
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'sk-test',
  model: 'gpt-4o',
  timeout: Duration(milliseconds: 200),
);

http.Client _mockOk(String content) => MockClient((req) async {
      expect(req.url.toString(), 'https://api.example.com/v1/chat/completions');
      expect(req.headers['authorization'], 'Bearer sk-test');
      expect(req.headers['content-type'], contains('application/json'));
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o');
      expect(body['messages'], isA<List>());
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': {'role': 'assistant', 'content': content}}
          ]
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

void main() {
  group('AiClient.chat', () {
    test('returns assistant content on 200', () async {
      final out = await AiClient.chat(
        settings: _settings,
        messages: [AiMessage.text('user', 'hi')],
        client: _mockOk('hello!'),
      );
      expect(out, 'hello!');
    });

    test('throws AiAuthException on 401', () async {
      final client = MockClient((_) async => http.Response('{}', 401));
      expect(
        () => AiClient.chat(settings: _settings, messages: [AiMessage.text('user', 'hi')], client: client),
        throwsA(isA<AiAuthException>()),
      );
    });

    test('throws AiNetworkException on 404 with guidance', () async {
      final client = MockClient((_) async => http.Response('404 page not found', 404));
      expect(
        () => AiClient.chat(settings: _settings, messages: [AiMessage.text('user', 'hi')], client: client),
        throwsA(
          predicate<AiNetworkException>(
            (e) => e.message.contains('404') && e.message.contains('/v1'),
          ),
        ),
      );
    });

    test('throws AiNetworkException on 5xx', () async {
      final client = MockClient((_) async => http.Response('{}', 503));
      expect(
        () => AiClient.chat(settings: _settings, messages: [AiMessage.text('user', 'hi')], client: client),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('throws AiNetworkException on timeout', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return http.Response('{}', 200);
      });
      expect(
        () => AiClient.chat(settings: _settings, messages: [AiMessage.text('user', 'hi')], client: client),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('user-with-image messages encode image_url content part', () async {
      final client = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        final content = (messages.first as Map<String, dynamic>)['content'] as List<dynamic>;
        expect(content.length, 2);
        expect((content[1] as Map)['type'], 'image_url');
        expect(((content[1] as Map)['image_url'] as Map)['url'], startsWith('data:image/jpeg;base64,'));
        return http.Response(
          jsonEncode({'choices': [{'message': {'content': 'ok'}}]}),
          200,
        );
      });
      await AiClient.chat(
        settings: _settings,
        messages: [AiMessage.userWithImage('what is this?', 'data:image/jpeg;base64,AAAA')],
        client: client,
      );
    });
  });
}
