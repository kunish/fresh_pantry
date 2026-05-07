# AI 录入：食谱 URL / 食材 拍照 / 食材 文本 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 Fresh Pantry 加上「OpenAI 兼容 AI 服务」+ 三个 AI 录入入口（食谱 URL 解析、食材拍照识别、食材文本拆条），并提供独立草稿审核页。

**Architecture:** 单一 `AiClient` 走 OpenAI `/chat/completions` 协议；三个 service 在其上构 prompt + 解析 JSON；草稿用 `DraftField<T>` 标记字段来源（AI 填 / 用户改）；审核页落库前转正式 `Recipe` / `Ingredient`。所有调用走 `aiSettingsProvider`，未配置抛 `AiNotConfiguredException`，UI 跳设置页。

**Tech Stack:** Flutter + Riverpod 3 + http + image_picker + shared_preferences；新依赖 `receive_sharing_intent`。配套 spec：`docs/superpowers/specs/2026-05-08-ai-recipe-ingredient-import-design.md`。

**File structure changes:**

| 类型 | 路径 | 说明 |
|---|---|---|
| 新建 | `lib/models/ai_settings.dart` | base URL / api key / model / timeout |
| 新建 | `lib/models/draft_field.dart` | `DraftField<T>` 通用包装 |
| 新建 | `lib/models/recipe_draft.dart` | 食谱草稿 |
| 新建 | `lib/models/ingredient_draft.dart` | 食材草稿 |
| 新建 | `lib/services/ai_client.dart` | OpenAI 兼容 chat 客户端 + AiMessage + AiException |
| 新建 | `lib/services/ai_recipe_parser.dart` | URL → RecipeDraft |
| 新建 | `lib/services/ai_ingredient_parser.dart` | 文本/图片 → List<IngredientDraft> |
| 新建 | `lib/services/share_intent_service.dart` | 剪贴板捕获 + 系统分享接收 |
| 新建 | `lib/providers/ai_settings_provider.dart` | 持久化 + isConfigured |
| 新建 | `lib/providers/ai_draft_provider.dart` | in-flight 草稿状态 + cancel |
| 新建 | `lib/screens/ai_settings_screen.dart` | 设置页 + 测试连接 |
| 新建 | `lib/screens/recipe_draft_review_screen.dart` | 食谱草稿审核 |
| 新建 | `lib/screens/ingredient_draft_review_screen.dart` | 食材草稿多项审核 |
| 新建 | `lib/widgets/shared/ai_draft_field.dart` | "AI 填" 字段视觉标记 |
| 改 | `lib/widgets/common/top_app_bar.dart` | 加齿轮入口 |
| 改 | `lib/screens/custom_recipe_form_screen.dart` | 顶部 banner + 剪贴板检测 |
| 改 | `lib/screens/add_ingredient_screen.dart` | 顶部「快速录入」三按钮 |
| 改 | `pubspec.yaml` | 加 `receive_sharing_intent` |
| 改 | `android/app/src/main/AndroidManifest.xml` | intent-filter |
| 改（iOS） | `ios/Runner/Info.plist` + Share Extension | iOS 分享 |

**Task 总数：** 17

---

## Task 1: `AiSettings` 模型

**Files:**
- Create: `lib/models/ai_settings.dart`
- Test: `test/ai_settings_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/ai_settings_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ai_settings.dart';

void main() {
  group('AiSettings', () {
    test('isConfigured is false when any required field is empty', () {
      expect(const AiSettings(baseUrl: '', apiKey: '', model: '').isConfigured, false);
      expect(const AiSettings(baseUrl: 'https://x', apiKey: '', model: 'm').isConfigured, false);
      expect(const AiSettings(baseUrl: 'https://x', apiKey: 'k', model: '').isConfigured, false);
    });

    test('isConfigured is true when baseUrl, apiKey, model all non-empty', () {
      const s = AiSettings(baseUrl: 'https://api.openai.com/v1', apiKey: 'sk-x', model: 'gpt-4o');
      expect(s.isConfigured, true);
    });

    test('toJson / fromJson round-trip preserves all fields', () {
      const original = AiSettings(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        timeout: Duration(seconds: 90),
      );
      final round = AiSettings.fromJson(original.toJson());
      expect(round, original);
    });

    test('copyWith replaces only specified fields', () {
      const s = AiSettings(baseUrl: 'a', apiKey: 'b', model: 'c');
      expect(s.copyWith(model: 'd').model, 'd');
      expect(s.copyWith(model: 'd').apiKey, 'b');
    });

    test('default timeout is 60 seconds', () {
      expect(const AiSettings(baseUrl: 'a', apiKey: 'b', model: 'c').timeout, const Duration(seconds: 60));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/ai_settings_test.dart
```

Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Implement minimum**

```dart
// lib/models/ai_settings.dart
import 'package:flutter/foundation.dart';

@immutable
class AiSettings {
  const AiSettings({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.timeout = const Duration(seconds: 60),
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final Duration timeout;

  bool get isConfigured =>
      baseUrl.isNotEmpty && apiKey.isNotEmpty && model.isNotEmpty;

  AiSettings copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    Duration? timeout,
  }) =>
      AiSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        timeout: timeout ?? this.timeout,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'timeoutSeconds': timeout.inSeconds,
      };

  factory AiSettings.fromJson(Map<String, dynamic> json) => AiSettings(
        baseUrl: (json['baseUrl'] as String?) ?? '',
        apiKey: (json['apiKey'] as String?) ?? '',
        model: (json['model'] as String?) ?? '',
        timeout: Duration(seconds: (json['timeoutSeconds'] as int?) ?? 60),
      );

  static const empty = AiSettings(baseUrl: '', apiKey: '', model: '');

  @override
  bool operator ==(Object other) =>
      other is AiSettings &&
      other.baseUrl == baseUrl &&
      other.apiKey == apiKey &&
      other.model == model &&
      other.timeout == timeout;

  @override
  int get hashCode => Object.hash(baseUrl, apiKey, model, timeout);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/ai_settings_test.dart
```

Expected: All 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/ai_settings.dart test/ai_settings_test.dart
git commit -m "feat(ai): add AiSettings model with JSON round-trip"
```

---

## Task 2: `aiSettingsProvider`

**Files:**
- Create: `lib/providers/ai_settings_provider.dart`
- Test: `test/ai_settings_provider_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/ai_settings_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ai_settings.dart';
import 'package:fresh_pantry/providers/ai_settings_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _buildContainer({Map<String, Object> initial = const {}}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  return container;
}

void main() {
  group('aiSettingsProvider', () {
    test('returns AiSettings.empty when nothing saved', () async {
      final container = await _buildContainer();
      addTearDown(container.dispose);
      expect(container.read(aiSettingsProvider), AiSettings.empty);
    });

    test('save persists settings and updates state', () async {
      final container = await _buildContainer();
      addTearDown(container.dispose);

      const next = AiSettings(baseUrl: 'https://x/v1', apiKey: 'k', model: 'gpt-4o');
      await container.read(aiSettingsProvider.notifier).save(next);

      expect(container.read(aiSettingsProvider), next);
    });

    test('state survives a fresh container with same prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c1 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      const next = AiSettings(baseUrl: 'https://x/v1', apiKey: 'k', model: 'gpt-4o');
      await c1.read(aiSettingsProvider.notifier).save(next);
      c1.dispose();

      final c2 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c2.dispose);
      expect(c2.read(aiSettingsProvider), next);
    });
  });
}
```

- [ ] **Step 2: Run test (FAIL: provider doesn't exist)**

```bash
flutter test test/ai_settings_provider_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/providers/ai_settings_provider.dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_settings.dart';
import 'storage_service_provider.dart';

const aiSettingsStorageKey = 'ai_settings_v1';

class AiSettingsNotifier extends Notifier<AiSettings> {
  late SharedPreferences _prefs;

  @override
  AiSettings build() {
    _prefs = ref.read(sharedPreferencesProvider);
    final raw = _prefs.getString(aiSettingsStorageKey);
    if (raw == null || raw.isEmpty) return AiSettings.empty;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AiSettings.fromJson(map);
    } catch (_) {
      return AiSettings.empty;
    }
  }

  Future<void> save(AiSettings next) async {
    final ok = await _prefs.setString(
      aiSettingsStorageKey,
      jsonEncode(next.toJson()),
    );
    if (!ok) {
      throw StateError('Failed to save AiSettings');
    }
    state = next;
  }
}

final aiSettingsProvider =
    NotifierProvider<AiSettingsNotifier, AiSettings>(AiSettingsNotifier.new);
```

- [ ] **Step 4: Run test (PASS)**

```bash
flutter test test/ai_settings_provider_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/providers/ai_settings_provider.dart test/ai_settings_provider_test.dart
git commit -m "feat(ai): persist AiSettings via Riverpod notifier"
```

---

## Task 3: `AiClient` + `AiMessage` + `AiException` (HTTP layer)

**Files:**
- Create: `lib/services/ai_client.dart` (contains `AiClient`, `AiMessage`, `AiContent`, `AiException` hierarchy)
- Test: `test/ai_client_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/ai_client_test.dart
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
```

- [ ] **Step 2: Run test (FAIL — file doesn't exist)**

```bash
flutter test test/ai_client_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/services/ai_client.dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_settings.dart';

sealed class AiException implements Exception {
  const AiException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class AiNotConfiguredException extends AiException {
  const AiNotConfiguredException() : super('AI 服务未配置');
}

class AiNetworkException extends AiException {
  const AiNetworkException(super.message);
}

class AiAuthException extends AiException {
  const AiAuthException(super.message);
}

class AiParseException extends AiException {
  const AiParseException(super.message);
}

class AiCancelledException extends AiException {
  const AiCancelledException() : super('已取消');
}

class AiContent {
  const AiContent.text(this.text) : imageDataUrl = null, type = 'text';
  const AiContent.imageDataUrl(this.imageDataUrl) : text = null, type = 'image_url';

  final String type;
  final String? text;
  final String? imageDataUrl;

  Map<String, dynamic> toJson() => switch (type) {
        'text' => {'type': 'text', 'text': text},
        'image_url' => {'type': 'image_url', 'image_url': {'url': imageDataUrl}},
        _ => throw StateError('unsupported content type: $type'),
      };
}

class AiMessage {
  AiMessage._({required this.role, required this.content});

  final String role;
  final List<AiContent> content;

  factory AiMessage.text(String role, String text) =>
      AiMessage._(role: role, content: [AiContent.text(text)]);

  factory AiMessage.userWithImage(String text, String dataUrl) => AiMessage._(
        role: 'user',
        content: [AiContent.text(text), AiContent.imageDataUrl(dataUrl)],
      );

  Map<String, dynamic> toJson() {
    if (content.length == 1 && content.first.type == 'text') {
      return {'role': role, 'content': content.first.text};
    }
    return {
      'role': role,
      'content': content.map((c) => c.toJson()).toList(),
    };
  }
}

class AiClient {
  static Future<String> chat({
    required AiSettings settings,
    required List<AiMessage> messages,
    Map<String, dynamic>? responseFormat,
    http.Client? client,
  }) async {
    if (!settings.isConfigured) {
      throw const AiNotConfiguredException();
    }

    final uri = Uri.parse(_join(settings.baseUrl, '/chat/completions'));
    final ownClient = client == null;
    final c = client ?? http.Client();
    try {
      final body = <String, dynamic>{
        'model': settings.model,
        'messages': messages.map((m) => m.toJson()).toList(),
        'temperature': 0.2,
        if (responseFormat != null) 'response_format': responseFormat,
      };

      late http.Response res;
      try {
        res = await c
            .post(
              uri,
              headers: {
                'authorization': 'Bearer ${settings.apiKey}',
                'content-type': 'application/json; charset=utf-8',
              },
              body: jsonEncode(body),
            )
            .timeout(settings.timeout);
      } on TimeoutException {
        throw const AiNetworkException('请求超时');
      } on http.ClientException catch (e) {
        throw AiNetworkException('网络错误：${e.message}');
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        throw AiAuthException('认证失败 (${res.statusCode})');
      }
      if (res.statusCode == 429) {
        throw const AiNetworkException('服务繁忙 (429)');
      }
      if (res.statusCode >= 500) {
        throw AiNetworkException('服务错误 (${res.statusCode})');
      }
      if (res.statusCode != 200) {
        throw AiNetworkException('意外状态 (${res.statusCode})');
      }

      try {
        final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) {
          throw const AiParseException('响应中无 choices');
        }
        final msg = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
        final content = msg?['content'];
        if (content is! String) {
          throw const AiParseException('响应中无 content');
        }
        return content;
      } on AiException {
        rethrow;
      } catch (e) {
        throw AiParseException('解析响应失败: $e');
      }
    } finally {
      if (ownClient) c.close();
    }
  }

  static String _join(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    return '$b$p';
  }
}
```

- [ ] **Step 4: Run test (PASS)**

```bash
flutter test test/ai_client_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/services/ai_client.dart test/ai_client_test.dart
git commit -m "feat(ai): add AiClient with OpenAI-compatible chat + exception types"
```

---

## Task 4: `AiSettingsScreen` + 测试连接

**Files:**
- Create: `lib/screens/ai_settings_screen.dart`
- Test: `test/ai_settings_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

```dart
// test/ai_settings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ai_settings.dart';
import 'package:fresh_pantry/providers/ai_settings_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/ai_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _harness({Map<String, Object> initial = const {}}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const MaterialApp(home: AiSettingsScreen()),
  );
}

void main() {
  testWidgets('shows three required text fields and timeout', (tester) async {
    await tester.pumpWidget(await _harness());
    expect(find.byKey(const Key('ai_base_url')), findsOneWidget);
    expect(find.byKey(const Key('ai_api_key')), findsOneWidget);
    expect(find.byKey(const Key('ai_model')), findsOneWidget);
    expect(find.byKey(const Key('ai_timeout')), findsOneWidget);
  });

  testWidgets('save button persists to provider', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AiSettingsScreen()),
    ));

    await tester.enterText(find.byKey(const Key('ai_base_url')), 'https://api.example.com/v1');
    await tester.enterText(find.byKey(const Key('ai_api_key')), 'sk-x');
    await tester.enterText(find.byKey(const Key('ai_model')), 'gpt-4o');
    await tester.tap(find.byKey(const Key('ai_save')));
    await tester.pumpAndSettle();

    final saved = container.read(aiSettingsProvider);
    expect(saved.baseUrl, 'https://api.example.com/v1');
    expect(saved.apiKey, 'sk-x');
    expect(saved.model, 'gpt-4o');
  });

  testWidgets('test connection shows result via injected callback', (tester) async {
    var called = false;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: AiSettingsScreen(
          testConnection: (_) async {
            called = true;
            return const ConnectionTestResult.ok();
          },
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('ai_base_url')), 'https://x/v1');
    await tester.enterText(find.byKey(const Key('ai_api_key')), 'sk');
    await tester.enterText(find.byKey(const Key('ai_model')), 'm');
    await tester.tap(find.byKey(const Key('ai_test_connection')));
    await tester.pumpAndSettle();

    expect(called, true);
    expect(find.text('连接成功'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run (FAIL)**

```bash
flutter test test/ai_settings_screen_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/screens/ai_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_settings.dart';
import '../providers/ai_settings_provider.dart';
import '../services/ai_client.dart';

class ConnectionTestResult {
  const ConnectionTestResult.ok() : success = true, message = '连接成功';
  const ConnectionTestResult.error(this.message) : success = false;
  final bool success;
  final String message;
}

typedef ConnectionTestFn = Future<ConnectionTestResult> Function(AiSettings settings);

Future<ConnectionTestResult> defaultTestConnection(AiSettings settings) async {
  try {
    final probeSettings = settings.copyWith(timeout: const Duration(seconds: 2));
    await AiClient.chat(
      settings: probeSettings,
      messages: [AiMessage.text('user', 'reply with: ok')],
    );
    return const ConnectionTestResult.ok();
  } on AiException catch (e) {
    return ConnectionTestResult.error(e.message);
  } catch (e) {
    return ConnectionTestResult.error('未知错误: $e');
  }
}

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key, this.testConnection});

  final ConnectionTestFn? testConnection;

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _timeout;

  bool _testing = false;
  ConnectionTestResult? _testResult;

  @override
  void initState() {
    super.initState();
    final s = ref.read(aiSettingsProvider);
    _baseUrl = TextEditingController(text: s.baseUrl);
    _apiKey = TextEditingController(text: s.apiKey);
    _model = TextEditingController(text: s.model);
    _timeout = TextEditingController(text: s.timeout.inSeconds.toString());
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _timeout.dispose();
    super.dispose();
  }

  AiSettings _currentInputs() => AiSettings(
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text.trim(),
        model: _model.text.trim(),
        timeout: Duration(seconds: int.tryParse(_timeout.text.trim()) ?? 60),
      );

  Future<void> _save() async {
    final next = _currentInputs();
    await ref.read(aiSettingsProvider.notifier).save(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final fn = widget.testConnection ?? defaultTestConnection;
    final result = await fn(_currentInputs());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('ai_base_url'),
            controller: _baseUrl,
            decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://api.openai.com/v1'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('ai_api_key'),
            controller: _apiKey,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API Key'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('ai_model'),
            controller: _model,
            decoration: const InputDecoration(labelText: 'Model', hintText: 'gpt-4o'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('ai_timeout'),
            controller: _timeout,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Timeout (秒)'),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            key: const Key('ai_test_connection'),
            onPressed: _testing ? null : _runTest,
            child: _testing
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('测试连接'),
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _testResult!.message,
              style: TextStyle(
                color: _testResult!.success ? Colors.green : Colors.red,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('ai_save'),
            onPressed: _save,
            child: const Text('保存'),
          ),
          const SizedBox(height: 12),
          const Text(
            '明文存于本机 SharedPreferences。',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests (PASS)**

```bash
flutter test test/ai_settings_screen_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/ai_settings_screen.dart test/ai_settings_screen_test.dart
git commit -m "feat(ai): add AiSettingsScreen with test connection action"
```

---

## Task 5: `TopAppBar` 加齿轮入口

**Files:**
- Modify: `lib/widgets/common/top_app_bar.dart`
- Test: `test/top_app_bar_settings_test.dart`

- [ ] **Step 1: Write failing widget test**

```dart
// test/top_app_bar_settings_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/ai_settings_screen.dart';
import 'package:fresh_pantry/widgets/common/top_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings icon pushes AiSettingsScreen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: Scaffold(body: TopAppBar())),
    ));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(AiSettingsScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run (FAIL — no settings icon)**

```bash
flutter test test/top_app_bar_settings_test.dart
```

- [ ] **Step 3: Modify**

Replace the right-side `Container` (the one wrapping the search `IconButton` at lines 43-54 of `top_app_bar.dart`) with a `Row` containing both settings and search:

```dart
// lib/widgets/common/top_app_bar.dart  (replace lines 43-54)
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: AppColors.primary),
                tooltip: 'AI 设置',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.search, color: AppColors.primary),
                tooltip: '搜索',
                onPressed: () {
                  ref.read(searchActiveProvider.notifier).state = true;
                },
              ),
            ],
          ),
```

Add import at top of `top_app_bar.dart`:

```dart
import '../../screens/ai_settings_screen.dart';
```

- [ ] **Step 4: Run (PASS)**

```bash
flutter test test/top_app_bar_settings_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/common/top_app_bar.dart test/top_app_bar_settings_test.dart
git commit -m "feat(ai): add settings gear icon to TopAppBar"
```

---

## Task 6: `DraftField<T>` generic

**Files:**
- Create: `lib/models/draft_field.dart`
- Test: `test/draft_field_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/draft_field_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';

void main() {
  group('DraftField', () {
    test('ai factory marks source ai', () {
      final f = DraftField<String>.ai('番茄');
      expect(f.value, '番茄');
      expect(f.source, DraftSource.ai);
    });

    test('user factory marks source user', () {
      final f = DraftField<int>.user(3);
      expect(f.source, DraftSource.user);
    });

    test('editedTo replaces value and flips source to user', () {
      final original = DraftField<String>.ai('番茄');
      final edited = original.editedTo('西红柿');
      expect(edited.value, '西红柿');
      expect(edited.source, DraftSource.user);
      expect(original.source, DraftSource.ai); // immutable
    });

    test('equality compares value + source', () {
      expect(DraftField<int>.ai(1), DraftField<int>.ai(1));
      expect(DraftField<int>.ai(1) == DraftField<int>.user(1), false);
    });
  });
}
```

- [ ] **Step 2: Run (FAIL)**

```bash
flutter test test/draft_field_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/models/draft_field.dart
import 'package:flutter/foundation.dart';

enum DraftSource { ai, user, hybrid }

@immutable
class DraftField<T> {
  const DraftField({required this.value, required this.source});

  final T value;
  final DraftSource source;

  factory DraftField.ai(T value) => DraftField(value: value, source: DraftSource.ai);
  factory DraftField.user(T value) => DraftField(value: value, source: DraftSource.user);

  DraftField<T> editedTo(T next) =>
      DraftField(value: next, source: DraftSource.user);

  @override
  bool operator ==(Object other) =>
      other is DraftField<T> && other.value == value && other.source == source;

  @override
  int get hashCode => Object.hash(value, source);
}
```

- [ ] **Step 4: Run (PASS)**

```bash
flutter test test/draft_field_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/models/draft_field.dart test/draft_field_test.dart
git commit -m "feat(ai): add DraftField<T> wrapper for AI/user provenance"
```

---

## Task 7: `RecipeDraft` + `IngredientDraft` models

**Files:**
- Create: `lib/models/recipe_draft.dart`, `lib/models/ingredient_draft.dart`
- Test: `test/recipe_draft_test.dart`, `test/ingredient_draft_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// test/recipe_draft_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/recipe_draft.dart';

void main() {
  test('toRecipe preserves all values', () {
    final draft = RecipeDraft(
      sourceUrl: 'https://lanfanapp.com/recipe/15978',
      name: DraftField.ai('番茄牛腩面'),
      category: DraftField.ai('家常'),
      cookingMinutes: DraftField.ai(60),
      difficulty: DraftField.ai(3),
      description: DraftField.ai('家常做法'),
      imageUrl: DraftField.ai('https://example.com/img.jpg'),
      ingredients: [
        RecipeIngredientDraft(name: DraftField.ai('番茄'), amount: DraftField.ai('2 个')),
      ],
      steps: [DraftField.ai('番茄切块')],
    );

    final recipe = draft.toRecipe(idGenerator: () => 'r-test');
    expect(recipe.id, 'r-test');
    expect(recipe.name, '番茄牛腩面');
    expect(recipe.cookingMinutes, 60);
    expect(recipe.ingredients.single.name, '番茄');
    expect(recipe.steps.single, '番茄切块');
  });
}
```

```dart
// test/ingredient_draft_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/ingredient_draft.dart';
import 'package:fresh_pantry/models/storage_area.dart';

void main() {
  test('IngredientDraft.selected defaults to true', () {
    final d = IngredientDraft(
      id: 'd1',
      name: DraftField.ai('番茄'),
      quantity: DraftField.ai('3'),
      unit: DraftField.ai('个'),
      category: DraftField.ai('蔬菜'),
      storage: DraftField.ai(IconType.fridge),
      shelfLifeDays: DraftField.ai(7),
    );
    expect(d.selected, true);
  });

  test('toIngredient preserves the captured fields', () {
    final d = IngredientDraft(
      id: 'd1',
      name: DraftField.ai('番茄'),
      quantity: DraftField.ai('3'),
      unit: DraftField.ai('个'),
      category: DraftField.ai('蔬菜'),
      storage: DraftField.ai(IconType.fridge),
      shelfLifeDays: DraftField.ai(7),
    );
    final ing = d.toIngredient();
    expect(ing.name, '番茄');
    expect(ing.quantity, '3');
    expect(ing.unit, '个');
    expect(ing.storage, IconType.fridge);
    expect(ing.shelfLifeDays, 7);
  });
}
```

- [ ] **Step 2: Run (FAIL)**

```bash
flutter test test/recipe_draft_test.dart test/ingredient_draft_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/models/recipe_draft.dart
import 'package:flutter/foundation.dart';

import 'draft_field.dart';
import 'recipe.dart';

@immutable
class RecipeIngredientDraft {
  const RecipeIngredientDraft({required this.name, required this.amount});
  final DraftField<String> name;
  final DraftField<String> amount;

  RecipeIngredient toIngredient() => RecipeIngredient(name: name.value, amount: amount.value);
}

@immutable
class RecipeDraft {
  const RecipeDraft({
    required this.sourceUrl,
    required this.name,
    required this.category,
    required this.cookingMinutes,
    required this.difficulty,
    required this.description,
    required this.imageUrl,
    required this.ingredients,
    required this.steps,
  });

  final String? sourceUrl;
  final DraftField<String> name;
  final DraftField<String> category;
  final DraftField<int> cookingMinutes;
  final DraftField<int> difficulty;
  final DraftField<String> description;
  final DraftField<String?> imageUrl;
  final List<RecipeIngredientDraft> ingredients;
  final List<DraftField<String>> steps;

  Recipe toRecipe({String Function()? idGenerator}) {
    final id = idGenerator?.call() ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';
    return Recipe(
      id: id,
      name: name.value,
      category: category.value,
      difficulty: difficulty.value,
      cookingMinutes: cookingMinutes.value,
      description: description.value,
      imageUrl: imageUrl.value,
      ingredients: ingredients.map((i) => i.toIngredient()).toList(),
      steps: steps.map((s) => s.value).toList(),
      tags: const [],
    );
  }
}
```

```dart
// lib/models/ingredient_draft.dart
import 'package:flutter/foundation.dart';

import '../utils/expiry_calculator.dart';
import 'draft_field.dart';
import 'ingredient.dart';
import 'storage_area.dart';

class IngredientDraft {
  IngredientDraft({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    required this.storage,
    required this.shelfLifeDays,
    this.selected = true,
  });

  final String id;
  DraftField<String> name;
  DraftField<String> quantity;
  DraftField<String> unit;
  DraftField<String?> category;
  DraftField<IconType?> storage;
  DraftField<int?> shelfLifeDays;
  bool selected;

  Ingredient toIngredient() {
    final days = shelfLifeDays.value;
    final today = DateTime.now();
    final expiry = days == null ? null : today.add(Duration(days: days));
    final freshness = expiry == null
        ? 0.85
        : expiryFreshness(expiryDate: expiry, totalShelfLifeDays: days ?? 7);
    return Ingredient(
      name: name.value,
      quantity: quantity.value,
      unit: unit.value,
      imageUrl: '',
      freshnessPercent: freshness,
      state: freshnessStateForExpiry(freshness: freshness, expiryDate: expiry),
      category: category.value,
      storage: storage.value ?? IconType.fridge,
      expiryDate: expiry,
      expiryLabel: expiry == null ? '新鲜' : expiryLabelFor(expiry),
      shelfLifeDays: days,
    );
  }
}
```

> Note: `Recipe`, `RecipeIngredient`, `Ingredient`, `IconType`, `expiryFreshness`, `freshnessStateForExpiry`, `expiryLabelFor` exist already (see `lib/models/recipe.dart`, `ingredient.dart`, `storage_area.dart`, `lib/utils/expiry_calculator.dart`). Match their constructor signatures exactly when implementing.

- [ ] **Step 4: Run (PASS)**

```bash
flutter test test/recipe_draft_test.dart test/ingredient_draft_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/models/recipe_draft.dart lib/models/ingredient_draft.dart \
        test/recipe_draft_test.dart test/ingredient_draft_test.dart
git commit -m "feat(ai): add RecipeDraft and IngredientDraft models"
```

---

## Task 8: `AiDraftField` widget (visual marker)

**Files:**
- Create: `lib/widgets/shared/ai_draft_field.dart`
- Test: `test/ai_draft_field_test.dart`

- [ ] **Step 1: Write failing widget test**

```dart
// test/ai_draft_field_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/widgets/shared/ai_draft_field.dart';

void main() {
  testWidgets('renders AI badge when source is ai', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiDraftFieldChip<String>(
          label: '名称',
          field: DraftField.ai('番茄'),
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('AI 填'), findsOneWidget);
    expect(find.text('番茄'), findsOneWidget);
  });

  testWidgets('hides AI badge after edit (source becomes user)', (tester) async {
    DraftField<String> current = DraftField.ai('番茄');
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => MaterialApp(
        home: Scaffold(
          body: AiDraftFieldChip<String>(
            label: '名称',
            field: current,
            onChanged: (next) => setState(() => current = next),
            editorBuilder: (initial, save) => TextButton(
              key: const Key('apply_user_edit'),
              onPressed: () => save('西红柿'),
              child: const Text('apply'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('番茄'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply_user_edit')));
    await tester.pumpAndSettle();
    expect(find.text('西红柿'), findsOneWidget);
    expect(find.text('AI 填'), findsNothing);
  });
}
```

- [ ] **Step 2: Run (FAIL)**

```bash
flutter test test/ai_draft_field_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/widgets/shared/ai_draft_field.dart
import 'package:flutter/material.dart';

import '../../models/draft_field.dart';

typedef DraftEditorBuilder<T> = Widget Function(T initial, void Function(T) save);

class AiDraftFieldChip<T> extends StatelessWidget {
  const AiDraftFieldChip({
    super.key,
    required this.label,
    required this.field,
    required this.onChanged,
    this.formatter,
    this.editorBuilder,
  });

  final String label;
  final DraftField<T> field;
  final ValueChanged<DraftField<T>> onChanged;
  final String Function(T value)? formatter;
  final DraftEditorBuilder<T>? editorBuilder;

  @override
  Widget build(BuildContext context) {
    final isAi = field.source == DraftSource.ai;
    final accent = isAi ? const Color(0xFF0EA5E9) : const Color(0xFF64748B);
    final display = formatter?.call(field.value) ?? '${field.value}';

    return InkWell(
      onTap: () => _openEditor(context),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.06),
          border: Border(left: BorderSide(color: accent, width: 3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: accent, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (isAi)
                  Text('AI 填', style: TextStyle(fontSize: 10, color: accent, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 4),
            Text(display, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    if (editorBuilder == null) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: editorBuilder!(field.value, (next) {
          onChanged(field.editedTo(next));
          Navigator.of(ctx).pop();
        }),
      ),
    );
  }
}
```

- [ ] **Step 4: Run (PASS)**

```bash
flutter test test/ai_draft_field_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/shared/ai_draft_field.dart test/ai_draft_field_test.dart
git commit -m "feat(ai): add AiDraftFieldChip with AI/user provenance markers"
```

---

## Task 9: `aiDraftProvider` (in-flight state + cancel)

**Files:**
- Create: `lib/providers/ai_draft_provider.dart`
- Test: `test/ai_draft_provider_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/ai_draft_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/recipe_draft.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';

RecipeDraft _stubRecipeDraft(String url) => RecipeDraft(
      sourceUrl: url,
      name: DraftField.ai('Test'),
      category: DraftField.ai('家常'),
      cookingMinutes: DraftField.ai(30),
      difficulty: DraftField.ai(2),
      description: DraftField.ai(''),
      imageUrl: const DraftField(value: null, source: DraftSource.ai),
      ingredients: const [],
      steps: const [],
    );

void main() {
  test('starts as idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(aiDraftProvider), const AiDraftState.idle());
  });

  test('runRecipeFromUrl sets running then complete on success', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(aiDraftProvider.notifier);
    final future = notifier.runRecipeFromUrl(
      'https://x',
      parser: (url) async => _stubRecipeDraft(url),
    );
    expect(container.read(aiDraftProvider).isRunning, true);
    await future;
    final state = container.read(aiDraftProvider);
    expect(state.isRunning, false);
    expect(state.recipeDraft?.sourceUrl, 'https://x');
  });

  test('runRecipeFromUrl sets error on parser exception', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiDraftProvider.notifier).runRecipeFromUrl(
          'https://x',
          parser: (_) async => throw Exception('boom'),
        );
    final state = container.read(aiDraftProvider);
    expect(state.error, isNotNull);
  });

  test('clear resets to idle', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(aiDraftProvider.notifier);
    await n.runRecipeFromUrl('https://x', parser: (u) async => _stubRecipeDraft(u));
    n.clear();
    expect(container.read(aiDraftProvider), const AiDraftState.idle());
  });
}
```

- [ ] **Step 2: Run (FAIL)**

```bash
flutter test test/ai_draft_provider_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/providers/ai_draft_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient_draft.dart';
import '../models/recipe_draft.dart';
import '../services/ai_client.dart';

@immutable
class AiDraftState {
  const AiDraftState({
    this.isRunning = false,
    this.recipeDraft,
    this.ingredientDrafts,
    this.error,
    this.recipeSourceUrl,
    this.ingredientSourceText,
  });

  const AiDraftState.idle() : this();

  final bool isRunning;
  final RecipeDraft? recipeDraft;
  final List<IngredientDraft>? ingredientDrafts;
  final AiException? error;

  // Source preserved for "重新生成 / 重新识别"
  final String? recipeSourceUrl;
  final String? ingredientSourceText;
  // Image bytes are kept on the notifier (not in state) — large payload, not for equality.

  AiDraftState copyWith({
    bool? isRunning,
    RecipeDraft? recipeDraft,
    List<IngredientDraft>? ingredientDrafts,
    AiException? error,
    String? recipeSourceUrl,
    String? ingredientSourceText,
  }) =>
      AiDraftState(
        isRunning: isRunning ?? this.isRunning,
        recipeDraft: recipeDraft ?? this.recipeDraft,
        ingredientDrafts: ingredientDrafts ?? this.ingredientDrafts,
        error: error,
        recipeSourceUrl: recipeSourceUrl ?? this.recipeSourceUrl,
        ingredientSourceText: ingredientSourceText ?? this.ingredientSourceText,
      );

  @override
  bool operator ==(Object o) =>
      o is AiDraftState &&
      o.isRunning == isRunning &&
      o.recipeDraft == recipeDraft &&
      identical(o.ingredientDrafts, ingredientDrafts) &&
      o.error == error;

  @override
  int get hashCode => Object.hash(isRunning, recipeDraft, ingredientDrafts, error);
}

typedef RecipeUrlParser = Future<RecipeDraft> Function(String url);
typedef IngredientTextParser = Future<List<IngredientDraft>> Function(String text);
typedef IngredientImageParser = Future<List<IngredientDraft>> Function(Uint8List bytes);

class AiDraftNotifier extends Notifier<AiDraftState> {
  Uint8List? _lastImageBytes;

  @override
  AiDraftState build() => const AiDraftState.idle();

  void clear() {
    _lastImageBytes = null;
    state = const AiDraftState.idle();
  }

  Future<void> runRecipeFromUrl(String url, {required RecipeUrlParser parser}) async {
    state = AiDraftState(isRunning: true, recipeSourceUrl: url);
    try {
      final draft = await parser(url);
      state = state.copyWith(isRunning: false, recipeDraft: draft);
    } on AiException catch (e) {
      state = state.copyWith(isRunning: false, error: e);
    } catch (e) {
      state = state.copyWith(isRunning: false, error: AiParseException('$e'));
    }
  }

  Future<void> runIngredientsFromText(String text, {required IngredientTextParser parser}) async {
    state = AiDraftState(isRunning: true, ingredientSourceText: text);
    try {
      final drafts = await parser(text);
      state = state.copyWith(isRunning: false, ingredientDrafts: drafts);
    } on AiException catch (e) {
      state = state.copyWith(isRunning: false, error: e);
    } catch (e) {
      state = state.copyWith(isRunning: false, error: AiParseException('$e'));
    }
  }

  Future<void> runIngredientsFromImage(Uint8List bytes, {required IngredientImageParser parser}) async {
    _lastImageBytes = bytes;
    state = const AiDraftState(isRunning: true);
    try {
      final drafts = await parser(bytes);
      state = state.copyWith(isRunning: false, ingredientDrafts: drafts);
    } on AiException catch (e) {
      state = state.copyWith(isRunning: false, error: e);
    } catch (e) {
      state = state.copyWith(isRunning: false, error: AiParseException('$e'));
    }
  }

  Uint8List? get lastImageBytes => _lastImageBytes;

  void updateRecipeDraft(RecipeDraft updated) =>
      state = state.copyWith(recipeDraft: updated);

  void updateIngredientDrafts(List<IngredientDraft> updated) =>
      state = state.copyWith(ingredientDrafts: updated);
}

final aiDraftProvider =
    NotifierProvider<AiDraftNotifier, AiDraftState>(AiDraftNotifier.new);
```

- [ ] **Step 4: Run (PASS)**

```bash
flutter test test/ai_draft_provider_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/providers/ai_draft_provider.dart test/ai_draft_provider_test.dart
git commit -m "feat(ai): add aiDraftProvider for in-flight state + source replay"
```

---

## Task 10: `AiRecipeParser` service

**Files:**
- Create: `lib/services/ai_recipe_parser.dart`
- Create: `test/fixtures/ai_responses/recipe_lanfan_15978.json`
- Create: `test/fixtures/ai_responses/recipe_partial_fields.json`
- Create: `test/fixtures/ai_responses/recipe_invalid.txt`
- Test: `test/ai_recipe_parser_test.dart`

- [ ] **Step 1: Create fixtures**

```jsonc
// test/fixtures/ai_responses/recipe_lanfan_15978.json
{
  "name": "番茄牛腩面",
  "category": "家常",
  "cookingMinutes": 60,
  "difficulty": 3,
  "description": "经典家常做法",
  "imageUrl": "https://example.com/cover.jpg",
  "ingredients": [
    {"name": "番茄", "amount": "2 个"},
    {"name": "牛腩", "amount": "500 g"},
    {"name": "面条", "amount": "200 g"}
  ],
  "steps": [
    "牛腩切块焯水",
    "番茄切块炒出沙",
    "加水炖煮 40 分钟",
    "下面条煮熟"
  ]
}
```

```jsonc
// test/fixtures/ai_responses/recipe_partial_fields.json
{
  "name": "汤面",
  "ingredients": [{"name": "面", "amount": "1 把"}]
}
```

```text
// test/fixtures/ai_responses/recipe_invalid.txt
Sure! Here is the recipe:

```json
{ "name": "番茄牛腩面", "cookingMinutes": 60, "difficulty": 3, "category": "家常", "description": "", "ingredients": [{"name":"番茄","amount":"2 个"}], "steps": ["切块"] }
```

Hope you enjoy!
```

- [ ] **Step 2: Write failing test**

```dart
// test/ai_recipe_parser_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/services/ai_client.dart';
import 'package:fresh_pantry/services/ai_recipe_parser.dart';

String _readFixture(String name) =>
    File('test/fixtures/ai_responses/$name').readAsStringSync();

void main() {
  group('AiRecipeParser.fromUrl', () {
    test('parses well-formed JSON into RecipeDraft', () async {
      final draft = await AiRecipeParser.fromUrl(
        'https://lanfanapp.com/recipe/15978',
        chatFn: (_) async => _readFixture('recipe_lanfan_15978.json'),
      );
      expect(draft.name.value, '番茄牛腩面');
      expect(draft.cookingMinutes.value, 60);
      expect(draft.ingredients.length, 3);
      expect(draft.steps.length, 4);
      expect(draft.name.source, DraftSource.ai);
      expect(draft.sourceUrl, 'https://lanfanapp.com/recipe/15978');
    });

    test('extracts JSON from markdown code block when AI replies with prose', () async {
      final draft = await AiRecipeParser.fromUrl(
        'https://x',
        chatFn: (_) async => _readFixture('recipe_invalid.txt'),
      );
      expect(draft.name.value, '番茄牛腩面');
    });

    test('throws AiParseException on partial fields', () async {
      expect(
        () => AiRecipeParser.fromUrl(
          'https://x',
          chatFn: (_) async => _readFixture('recipe_partial_fields.json'),
        ),
        throwsA(isA<AiParseException>()),
      );
    });

    test('rethrows AiAuthException from chatFn', () async {
      expect(
        () => AiRecipeParser.fromUrl(
          'https://x',
          chatFn: (_) async => throw const AiAuthException('401'),
        ),
        throwsA(isA<AiAuthException>()),
      );
    });
  });
}
```

- [ ] **Step 3: Run (FAIL)**

```bash
flutter test test/ai_recipe_parser_test.dart
```

- [ ] **Step 4: Implement**

```dart
// lib/services/ai_recipe_parser.dart
import 'dart:convert';

import '../models/draft_field.dart';
import '../models/recipe_draft.dart';
import 'ai_client.dart';

typedef AiChatFn = Future<String> Function(List<AiMessage> messages);

class AiRecipeParser {
  static Future<RecipeDraft> fromUrl(
    String url, {
    required AiChatFn chatFn,
  }) async {
    final messages = [
      AiMessage.text(
        'system',
        '你是食谱抽取助手。访问用户提供的 URL（你具备访问网页的能力），从中抽取结构化食谱。'
            '只返回 JSON，不要前后文。如果无法访问，返回 {"error":"..."}。'
            'JSON 字段：name, category, cookingMinutes (int 分钟), difficulty (int 1-5), '
            'description, imageUrl (可空), ingredients ([{name, amount}]), steps (string array)。',
      ),
      AiMessage.text('user', '请抽取这个食谱：$url'),
    ];

    final raw = await chatFn(messages);
    final json = _extractJsonObject(raw);
    if (json == null) {
      throw const AiParseException('AI 返回不是合法 JSON');
    }
    if (json.containsKey('error')) {
      throw AiParseException('AI 报告：${json['error']}');
    }

    try {
      return RecipeDraft(
        sourceUrl: url,
        name: DraftField.ai(_requireString(json, 'name')),
        category: DraftField.ai(_requireString(json, 'category')),
        cookingMinutes: DraftField.ai(_requireInt(json, 'cookingMinutes')),
        difficulty: DraftField.ai(_requireInt(json, 'difficulty')),
        description: DraftField.ai((json['description'] as String?) ?? ''),
        imageUrl: DraftField<String?>(value: json['imageUrl'] as String?, source: DraftSource.ai),
        ingredients: ((json['ingredients'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((e) => RecipeIngredientDraft(
                  name: DraftField.ai(_requireString(e, 'name')),
                  amount: DraftField.ai(_requireString(e, 'amount')),
                ))
            .toList(),
        steps: ((json['steps'] as List<dynamic>?) ?? const [])
            .whereType<String>()
            .map(DraftField<String>.ai)
            .toList(),
      );
    } on AiParseException {
      rethrow;
    } catch (e) {
      throw AiParseException('字段缺失或类型不符: $e');
    }
  }

  static String _requireString(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is! String || v.isEmpty) {
      throw AiParseException('字段 $key 缺失或非字符串');
    }
    return v;
  }

  static int _requireInt(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is int) return v;
    if (v is num) return v.round();
    throw AiParseException('字段 $key 缺失或非整数');
  }

  static Map<String, dynamic>? _extractJsonObject(String input) {
    try {
      final v = jsonDecode(input);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}

    final fenceMatch = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```').firstMatch(input);
    if (fenceMatch != null) {
      try {
        final v = jsonDecode(fenceMatch.group(1)!);
        if (v is Map<String, dynamic>) return v;
      } catch (_) {}
    }

    final braceMatch = RegExp(r'\{[\s\S]*\}').firstMatch(input);
    if (braceMatch != null) {
      try {
        final v = jsonDecode(braceMatch.group(0)!);
        if (v is Map<String, dynamic>) return v;
      } catch (_) {}
    }
    return null;
  }
}
```

- [ ] **Step 5: Run (PASS)**

```bash
flutter test test/ai_recipe_parser_test.dart
```

- [ ] **Step 6: Commit**

```bash
git add lib/services/ai_recipe_parser.dart test/ai_recipe_parser_test.dart \
        test/fixtures/ai_responses/recipe_lanfan_15978.json \
        test/fixtures/ai_responses/recipe_partial_fields.json \
        test/fixtures/ai_responses/recipe_invalid.txt
git commit -m "feat(ai): add AiRecipeParser with JSON-in-markdown fallback"
```

---

## Task 11: `RecipeDraftReviewScreen`

**Files:**
- Create: `lib/screens/recipe_draft_review_screen.dart`
- Test: `test/recipe_draft_review_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

```dart
// test/recipe_draft_review_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/recipe_draft.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/custom_recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/recipe_draft_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecipeDraft _stub() => RecipeDraft(
      sourceUrl: 'https://x',
      name: DraftField.ai('番茄牛腩面'),
      category: DraftField.ai('家常'),
      cookingMinutes: DraftField.ai(60),
      difficulty: DraftField.ai(3),
      description: DraftField.ai(''),
      imageUrl: const DraftField(value: null, source: DraftSource.ai),
      ingredients: [
        RecipeIngredientDraft(name: DraftField.ai('番茄'), amount: DraftField.ai('2')),
      ],
      steps: [DraftField.ai('切块')],
    );

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  testWidgets('shows AI-filled name and ingredients', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateRecipeDraft(_stub());

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: RecipeDraftReviewScreen()),
    ));
    expect(find.text('番茄牛腩面'), findsOneWidget);
    expect(find.text('番茄'), findsOneWidget);
  });

  testWidgets('confirm button writes to customRecipesProvider', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateRecipeDraft(_stub());

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: RecipeDraftReviewScreen()),
    ));
    await tester.tap(find.byKey(const Key('recipe_review_confirm')));
    await tester.pumpAndSettle();

    expect(container.read(customRecipesProvider).single.name, '番茄牛腩面');
  });

  testWidgets('discard clears aiDraftProvider', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateRecipeDraft(_stub());

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: RecipeDraftReviewScreen()),
    ));
    await tester.tap(find.byKey(const Key('recipe_review_discard')));
    await tester.pumpAndSettle();
    expect(container.read(aiDraftProvider).recipeDraft, isNull);
  });
}
```

- [ ] **Step 2: Run (FAIL)**

```bash
flutter test test/recipe_draft_review_screen_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/screens/recipe_draft_review_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/draft_field.dart';
import '../models/recipe_draft.dart';
import '../providers/ai_draft_provider.dart';
import '../providers/custom_recipe_provider.dart';
import '../widgets/shared/ai_draft_field.dart';

class RecipeDraftReviewScreen extends ConsumerWidget {
  const RecipeDraftReviewScreen({super.key, this.regenerate});

  /// Optional callback used when "重新生成" is tapped.
  /// Called with the original `sourceUrl`. If null, button is hidden.
  final Future<void> Function(String url)? regenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiDraftProvider);
    final draft = state.recipeDraft;
    if (draft == null) {
      return const Scaffold(body: Center(child: Text('草稿已丢失')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('审核 AI 草稿')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (draft.sourceUrl != null) ...[
            Text('来源: ${draft.sourceUrl}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 12),
          ],
          AiDraftFieldChip<String>(
            label: '名称',
            field: draft.name,
            onChanged: (next) => _patch(ref, draft.copyWith(name: next)),
            editorBuilder: _stringEditor,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AiDraftFieldChip<String>(
                  label: '分类',
                  field: draft.category,
                  onChanged: (next) => _patch(ref, draft.copyWith(category: next)),
                  editorBuilder: _stringEditor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AiDraftFieldChip<int>(
                  label: '时长 (分钟)',
                  field: draft.cookingMinutes,
                  onChanged: (next) => _patch(ref, draft.copyWith(cookingMinutes: next)),
                  formatter: (v) => '$v 分钟',
                  editorBuilder: _intEditor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AiDraftFieldChip<int>(
                  label: '难度',
                  field: draft.difficulty,
                  onChanged: (next) => _patch(ref, draft.copyWith(difficulty: next)),
                  formatter: (v) => '⭐' * v,
                  editorBuilder: _intEditor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('食材 · ${draft.ingredients.length} 项', style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final ing in draft.ingredients)
            ListTile(
              dense: true,
              title: Text('${ing.name.value} · ${ing.amount.value}'),
            ),
          const SizedBox(height: 12),
          Text('步骤 · ${draft.steps.length} 步', style: const TextStyle(fontWeight: FontWeight.w700)),
          for (var i = 0; i < draft.steps.length; i++)
            ListTile(dense: true, title: Text('${i + 1}. ${draft.steps[i].value}')),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (regenerate != null && draft.sourceUrl != null)
              Expanded(
                child: OutlinedButton(
                  key: const Key('recipe_review_regenerate'),
                  onPressed: state.isRunning ? null : () => regenerate!(draft.sourceUrl!),
                  child: const Text('重新生成'),
                ),
              ),
            if (regenerate != null) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const Key('recipe_review_discard'),
                onPressed: () {
                  ref.read(aiDraftProvider.notifier).clear();
                  Navigator.of(context).maybePop();
                },
                child: const Text('丢弃'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const Key('recipe_review_confirm'),
                onPressed: () async {
                  await ref.read(customRecipesProvider.notifier).add(draft.toRecipe());
                  if (!context.mounted) return;
                  ref.read(aiDraftProvider.notifier).clear();
                  Navigator.of(context).maybePop();
                },
                child: const Text('确认入库'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _patch(WidgetRef ref, RecipeDraft next) =>
      ref.read(aiDraftProvider.notifier).updateRecipeDraft(next);

  static Widget _stringEditor(String initial, void Function(String) save) {
    final controller = TextEditingController(text: initial);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(controller: controller, autofocus: true),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => save(controller.text.trim()), child: const Text('保存')),
      ],
    );
  }

  static Widget _intEditor(int initial, void Function(int) save) {
    final controller = TextEditingController(text: initial.toString());
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(controller: controller, keyboardType: TextInputType.number, autofocus: true),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => save(int.tryParse(controller.text.trim()) ?? initial),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

extension on RecipeDraft {
  RecipeDraft copyWith({
    DraftField<String>? name,
    DraftField<String>? category,
    DraftField<int>? cookingMinutes,
    DraftField<int>? difficulty,
    DraftField<String>? description,
    DraftField<String?>? imageUrl,
    List<RecipeIngredientDraft>? ingredients,
    List<DraftField<String>>? steps,
  }) =>
      RecipeDraft(
        sourceUrl: sourceUrl,
        name: name ?? this.name,
        category: category ?? this.category,
        cookingMinutes: cookingMinutes ?? this.cookingMinutes,
        difficulty: difficulty ?? this.difficulty,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        ingredients: ingredients ?? this.ingredients,
        steps: steps ?? this.steps,
      );
}
```

- [ ] **Step 4: Run (PASS)**

```bash
flutter test test/recipe_draft_review_screen_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/recipe_draft_review_screen.dart test/recipe_draft_review_screen_test.dart
git commit -m "feat(ai): add RecipeDraftReviewScreen with field-level editing"
```

---

## Task 12: `CustomRecipeFormScreen` 顶部 banner（粘贴 URL 入口）

**Files:**
- Modify: `lib/screens/custom_recipe_form_screen.dart`
- Test: `test/custom_recipe_form_url_banner_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/custom_recipe_form_url_banner_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/recipe_draft.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/custom_recipe_form_screen.dart';
import 'package:fresh_pantry/screens/recipe_draft_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('paste banner appears at top of recipe form', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: CustomRecipeFormScreen()),
    ));
    expect(find.byKey(const Key('recipe_url_input')), findsOneWidget);
    expect(find.byKey(const Key('recipe_url_parse')), findsOneWidget);
  });

  testWidgets('parse button with valid URL pushes RecipeDraftReviewScreen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: CustomRecipeFormScreen(
          urlParserOverride: (url) async => _stubDraft(url),
        ),
      ),
    ));
    await tester.enterText(find.byKey(const Key('recipe_url_input')), 'https://lanfanapp.com/recipe/15978');
    await tester.tap(find.byKey(const Key('recipe_url_parse')));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeDraftReviewScreen), findsOneWidget);
  });
}

RecipeDraft _stubDraft(String url) => RecipeDraft(
      sourceUrl: url,
      name: DraftField.ai('Test'),
      category: DraftField.ai('家常'),
      cookingMinutes: DraftField.ai(30),
      difficulty: DraftField.ai(2),
      description: DraftField.ai(''),
      imageUrl: const DraftField(value: null, source: DraftSource.ai),
      ingredients: const [],
      steps: const [],
    );
```

- [ ] **Step 2: Run (FAIL)**

```bash
flutter test test/custom_recipe_form_url_banner_test.dart
```

- [ ] **Step 3: Modify**

In `custom_recipe_form_screen.dart`:

1. Add field to `CustomRecipeFormScreen`:

```dart
final Future<RecipeDraft> Function(String url)? urlParserOverride;

const CustomRecipeFormScreen({super.key, this.recipe, this.pickCoverImage, this.urlParserOverride});
```

2. In `_CustomRecipeFormScreenState.build`, prepend the banner before `_CoverImageHero`:

```dart
// At top of column, before _CoverImageHero(...)
_AiUrlBanner(
  controller: _urlController,
  onParse: _onParseUrl,
),
```

3. Add `_urlController` and `_onParseUrl`:

```dart
late final TextEditingController _urlController;

@override
void initState() {
  super.initState();
  _urlController = TextEditingController();
  // ... existing init
}

@override
void dispose() {
  _urlController.dispose();
  // ... existing dispose
  super.dispose();
}

Future<void> _onParseUrl() async {
  final url = _urlController.text.trim();
  if (!url.startsWith('http')) {
    _showError('请填入合法的 http(s) 链接');
    return;
  }
  final notifier = ref.read(aiDraftProvider.notifier);
  final parser = widget.urlParserOverride ??
      (u) => AiRecipeParser.fromUrl(
            u,
            chatFn: (msgs) => AiClient.chat(
              settings: ref.read(aiSettingsProvider),
              messages: msgs,
              responseFormat: const {'type': 'json_object'},
            ),
          );
  await notifier.runRecipeFromUrl(url, parser: parser);
  final state = ref.read(aiDraftProvider);
  if (state.error is AiNotConfiguredException) {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
    return;
  }
  if (state.error != null) {
    _showError(state.error!.message);
    return;
  }
  if (state.recipeDraft == null) return;
  if (!mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RecipeDraftReviewScreen(
        regenerate: (sourceUrl) => notifier.runRecipeFromUrl(sourceUrl, parser: parser),
      ),
    ),
  );
}
```

4. Add the `_AiUrlBanner` widget at the bottom of the file:

```dart
class _AiUrlBanner extends StatelessWidget {
  const _AiUrlBanner({required this.controller, required this.onParse});
  final TextEditingController controller;
  final VoidCallback onParse;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF0EA5E9)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✨ 用 AI 一键导入',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            key: const Key('recipe_url_input'),
            controller: controller,
            decoration: const InputDecoration(
              hintText: '粘贴食谱链接 (懒饭 / 小红书…)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('recipe_url_parse'),
            onPressed: onParse,
            child: const Text('解析为草稿'),
          ),
        ],
      ),
    );
  }
}
```

5. Add imports at top of file:

```dart
import '../providers/ai_draft_provider.dart';
import '../providers/ai_settings_provider.dart';
import '../models/recipe_draft.dart';
import '../models/draft_field.dart';
import '../services/ai_client.dart';
import '../services/ai_recipe_parser.dart';
import 'ai_settings_screen.dart';
import 'recipe_draft_review_screen.dart';
```

- [ ] **Step 4: Run (PASS)**

```bash
flutter test test/custom_recipe_form_url_banner_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/custom_recipe_form_screen.dart test/custom_recipe_form_url_banner_test.dart
git commit -m "feat(ai): add paste-URL banner to CustomRecipeFormScreen"
```

---

## Task 13: 剪贴板检测（进入食谱表单时）

**Files:**
- Create: `lib/services/share_intent_service.dart` (clipboard half only — system share added in Task 17)
- Modify: `lib/screens/custom_recipe_form_screen.dart` (call detector on init)
- Test: `test/clipboard_url_detector_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/clipboard_url_detector_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';

void main() {
  group('ClipboardUrlDetector', () {
    test('returns null when clipboard does not contain http(s) URL', () async {
      final d = ClipboardUrlDetector(
        ignoreCooldown: const Duration(minutes: 30),
        clipboardReader: () async => 'just plain text, no link',
      );
      expect(await d.peek(), isNull);
    });

    test('extracts first http(s) URL from text', () async {
      final d = ClipboardUrlDetector(
        ignoreCooldown: const Duration(minutes: 30),
        clipboardReader: () async => '看看这个: https://lanfanapp.com/recipe/15978 很赞',
      );
      expect(await d.peek(), 'https://lanfanapp.com/recipe/15978');
    });

    test('ignored URL is suppressed within cooldown window', () async {
      var now = DateTime(2026, 5, 8, 12, 0, 0);
      final d = ClipboardUrlDetector(
        ignoreCooldown: const Duration(minutes: 30),
        clipboardReader: () async => 'https://x/r/1',
        clock: () => now,
      );
      d.markIgnored('https://x/r/1');
      expect(await d.peek(), isNull);

      now = now.add(const Duration(minutes: 31));
      expect(await d.peek(), 'https://x/r/1');
    });
  });
}
```

- [ ] **Step 2: Run (FAIL)**

```bash
flutter test test/clipboard_url_detector_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/services/share_intent_service.dart
import 'package:flutter/services.dart';

typedef ClipboardReader = Future<String?> Function();
typedef Clock = DateTime Function();

Future<String?> _defaultClipboardRead() async {
  final data = await Clipboard.getData('text/plain');
  return data?.text;
}

class ClipboardUrlDetector {
  ClipboardUrlDetector({
    this.ignoreCooldown = const Duration(minutes: 30),
    ClipboardReader? clipboardReader,
    Clock? clock,
  })  : _read = clipboardReader ?? _defaultClipboardRead,
        _clock = clock ?? DateTime.now;

  final Duration ignoreCooldown;
  final ClipboardReader _read;
  final Clock _clock;

  String? _ignoredUrl;
  DateTime? _ignoredAt;

  /// Returns the first http(s) URL in the clipboard, or null when missing /
  /// suppressed by the cooldown window.
  Future<String?> peek() async {
    final text = await _read();
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'https?://[^\s)\]"]+').firstMatch(text);
    final url = match?.group(0);
    if (url == null) return null;
    if (_ignoredUrl == url && _ignoredAt != null) {
      final elapsed = _clock().difference(_ignoredAt!);
      if (elapsed < ignoreCooldown) return null;
    }
    return url;
  }

  void markIgnored(String url) {
    _ignoredUrl = url;
    _ignoredAt = _clock();
  }
}
```

- [ ] **Step 4: Run (PASS)**

```bash
flutter test test/clipboard_url_detector_test.dart
```

- [ ] **Step 5: Wire into `CustomRecipeFormScreen`**

In `_CustomRecipeFormScreenState`:

```dart
final _clipboardDetector = ClipboardUrlDetector();

@override
void initState() {
  super.initState();
  // ... existing init
  if (!_isEditing) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferClipboardUrl());
  }
}

Future<void> _maybeOfferClipboardUrl() async {
  final url = await _clipboardDetector.peek();
  if (url == null || !mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 8),
      content: Text('检测到食谱链接: $url'),
      action: SnackBarAction(
        label: '导入',
        onPressed: () {
          _urlController.text = url;
          _onParseUrl();
        },
      ),
      onVisible: () {},
    ),
  );
  // If user dismisses without tapping, mark as ignored after a delay.
  Future<void>.delayed(const Duration(seconds: 9), () {
    if (mounted && _urlController.text != url) {
      _clipboardDetector.markIgnored(url);
    }
  });
}
```

Add import:

```dart
import '../services/share_intent_service.dart';
```

- [ ] **Step 6: Manual smoke check (no test for this UI wiring — covered by integration-level review)**

Run app, copy a URL to clipboard, open new-recipe screen → SnackBar visible.

- [ ] **Step 7: Commit**

```bash
git add lib/services/share_intent_service.dart \
        lib/screens/custom_recipe_form_screen.dart \
        test/clipboard_url_detector_test.dart
git commit -m "feat(ai): detect recipe URL in clipboard on entering recipe form"
```

---

## Task 14: `AiIngredientParser.fromText`

**Files:**
- Create: `lib/services/ai_ingredient_parser.dart`
- Create: `test/fixtures/ai_responses/ingredient_text_simple.json`
- Create: `test/fixtures/ai_responses/ingredient_text_complex.json`
- Test: `test/ai_ingredient_parser_text_test.dart`

- [ ] **Step 1: Create fixtures**

```jsonc
// test/fixtures/ai_responses/ingredient_text_simple.json
[
  {"name": "番茄", "quantity": "3", "unit": "个", "category": "蔬菜", "storage": "fridge", "shelfLifeDays": 7}
]
```

```jsonc
// test/fixtures/ai_responses/ingredient_text_complex.json
[
  {"name": "番茄", "quantity": "3", "unit": "个", "category": "蔬菜", "storage": "fridge", "shelfLifeDays": 7},
  {"name": "鸡蛋", "quantity": "6", "unit": "颗", "category": "蛋奶", "storage": "fridge", "shelfLifeDays": 30},
  {"name": "面条", "quantity": "1", "unit": "把", "category": "主食", "storage": "pantry", "shelfLifeDays": 365}
]
```

- [ ] **Step 2: Write failing test**

```dart
// test/ai_ingredient_parser_text_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/services/ai_ingredient_parser.dart';

String _f(String name) => File('test/fixtures/ai_responses/$name').readAsStringSync();

void main() {
  test('fromText returns single ingredient', () async {
    final list = await AiIngredientParser.fromText(
      '番茄 3 个',
      chatFn: (_) async => _f('ingredient_text_simple.json'),
    );
    expect(list.single.name.value, '番茄');
    expect(list.single.quantity.value, '3');
    expect(list.single.storage.value, IconType.fridge);
    expect(list.single.shelfLifeDays.value, 7);
  });

  test('fromText returns multiple ingredients', () async {
    final list = await AiIngredientParser.fromText(
      '番茄 3 个 鸡蛋 6 颗 面条 1 把',
      chatFn: (_) async => _f('ingredient_text_complex.json'),
    );
    expect(list.length, 3);
    expect(list.last.storage.value, IconType.pantry);
  });

  test('fromText with empty input throws ArgumentError', () async {
    expect(
      () => AiIngredientParser.fromText('', chatFn: (_) async => '[]'),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 3: Run (FAIL)**

```bash
flutter test test/ai_ingredient_parser_text_test.dart
```

- [ ] **Step 4: Implement**

```dart
// lib/services/ai_ingredient_parser.dart
import 'dart:convert';
import 'dart:typed_data';

import '../data/food_categories.dart';
import '../models/draft_field.dart';
import '../models/ingredient_draft.dart';
import '../models/storage_area.dart';
import 'ai_client.dart';
import 'ai_recipe_parser.dart';

const _maxTextLength = 5000;

class AiIngredientParser {
  static Future<List<IngredientDraft>> fromText(
    String text, {
    required AiChatFn chatFn,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('文本不能为空');
    }
    final input = trimmed.length > _maxTextLength
        ? trimmed.substring(0, _maxTextLength)
        : trimmed;

    final messages = [
      AiMessage.text(
        'system',
        '你是食材清单解析助手。把用户输入的食材文本拆为多条结构化条目。'
            '只返回 JSON 数组，每条 {name, quantity, unit, category, storage (fridge/freezer/pantry), shelfLifeDays}。'
            '估算合理的数量、单位、分类、存储、保质期。',
      ),
      AiMessage.text('user', input),
    ];
    final raw = await chatFn(messages);
    return _parseList(raw);
  }

  static Future<List<IngredientDraft>> fromImage(
    Uint8List imageBytes, {
    required AiChatFn chatFn,
  }) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError('图片为空');
    }
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(imageBytes)}';
    final messages = [
      AiMessage.text(
        'system',
        '你是食材识别助手。识别图中所有可入库的食材，返回 JSON 数组：'
            '{name, quantity, unit, category, storage (fridge/freezer/pantry), shelfLifeDays}。',
      ),
      AiMessage.userWithImage('请识别图中食材', dataUrl),
    ];
    final raw = await chatFn(messages);
    return _parseList(raw);
  }

  static List<IngredientDraft> _parseList(String raw) {
    final list = _extractJsonArray(raw);
    if (list == null) {
      throw const AiParseException('AI 返回不是合法 JSON 数组');
    }
    final items = <IngredientDraft>[];
    var idCounter = 0;
    for (final entry in list.whereType<Map<String, dynamic>>()) {
      try {
        final name = (entry['name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        items.add(IngredientDraft(
          id: 'ai_${DateTime.now().millisecondsSinceEpoch}_${idCounter++}',
          name: DraftField.ai(name),
          quantity: DraftField.ai((entry['quantity'] ?? '1').toString()),
          unit: DraftField.ai((entry['unit'] as String?) ?? '个'),
          category: DraftField.ai((entry['category'] as String?) ?? FoodCategories.other),
          storage: DraftField.ai(_parseStorage(entry['storage'] as String?)),
          shelfLifeDays: DraftField.ai(_parseInt(entry['shelfLifeDays'])),
        ));
      } catch (_) {
        // Skip malformed entries — keep partial results.
      }
    }
    return items;
  }

  static List<dynamic>? _extractJsonArray(String input) {
    try {
      final v = jsonDecode(input);
      if (v is List) return v;
    } catch (_) {}
    final fence = RegExp(r'```(?:json)?\s*(\[[\s\S]*?\])\s*```').firstMatch(input);
    if (fence != null) {
      try {
        final v = jsonDecode(fence.group(1)!);
        if (v is List) return v;
      } catch (_) {}
    }
    final bracket = RegExp(r'\[[\s\S]*\]').firstMatch(input);
    if (bracket != null) {
      try {
        final v = jsonDecode(bracket.group(0)!);
        if (v is List) return v;
      } catch (_) {}
    }
    return null;
  }

  static IconType? _parseStorage(String? raw) {
    switch (raw) {
      case 'fridge':
        return IconType.fridge;
      case 'freezer':
        return IconType.freezer;
      case 'pantry':
        return IconType.pantry;
      default:
        return null;
    }
  }

  static int? _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
```

- [ ] **Step 5: Run (PASS)**

```bash
flutter test test/ai_ingredient_parser_text_test.dart
```

- [ ] **Step 6: Commit**

```bash
git add lib/services/ai_ingredient_parser.dart test/ai_ingredient_parser_text_test.dart \
        test/fixtures/ai_responses/ingredient_text_simple.json \
        test/fixtures/ai_responses/ingredient_text_complex.json
git commit -m "feat(ai): add AiIngredientParser.fromText (and stub for fromImage)"
```

---

## Task 15: `IngredientDraftReviewScreen` (multi-item review)

**Files:**
- Create: `lib/screens/ingredient_draft_review_screen.dart`
- Test: `test/ingredient_draft_review_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

```dart
// test/ingredient_draft_review_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/ingredient_draft.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/ingredient_draft_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<IngredientDraft> _stubs() => [
      IngredientDraft(
        id: '1',
        name: DraftField.ai('番茄'),
        quantity: DraftField.ai('3'),
        unit: DraftField.ai('个'),
        category: DraftField.ai('蔬菜'),
        storage: DraftField.ai(IconType.fridge),
        shelfLifeDays: DraftField.ai(7),
      ),
      IngredientDraft(
        id: '2',
        name: DraftField.ai('鸡蛋'),
        quantity: DraftField.ai('6'),
        unit: DraftField.ai('颗'),
        category: DraftField.ai('蛋奶'),
        storage: DraftField.ai(IconType.fridge),
        shelfLifeDays: DraftField.ai(30),
      ),
    ];

void main() {
  testWidgets('shows N rows, all selected, button label "入库 (2 项)"', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateIngredientDrafts(_stubs());

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: IngredientDraftReviewScreen()),
    ));
    expect(find.text('番茄'), findsOneWidget);
    expect(find.text('鸡蛋'), findsOneWidget);
    expect(find.text('入库 (2 项)'), findsOneWidget);
  });

  testWidgets('toggling a row updates the button count', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateIngredientDrafts(_stubs());

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: IngredientDraftReviewScreen()),
    ));
    await tester.tap(find.byKey(const Key('ingredient_row_1')));
    await tester.pumpAndSettle();
    expect(find.text('入库 (1 项)'), findsOneWidget);
  });

  testWidgets('confirm writes selected to inventoryProvider and clears draft', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateIngredientDrafts(_stubs());

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: IngredientDraftReviewScreen()),
    ));
    await tester.tap(find.byKey(const Key('ingredient_review_confirm')));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider).length, 2);
    expect(container.read(aiDraftProvider).ingredientDrafts, isNull);
  });
}
```

- [ ] **Step 2: Run (FAIL)**

```bash
flutter test test/ingredient_draft_review_screen_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/screens/ingredient_draft_review_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient_draft.dart';
import '../providers/ai_draft_provider.dart';
import '../providers/inventory_provider.dart';
import '../utils/storage_labels.dart';

class IngredientDraftReviewScreen extends ConsumerWidget {
  const IngredientDraftReviewScreen({super.key, this.regenerate});

  /// Optional callback for "重新识别".
  final Future<void> Function()? regenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(aiDraftProvider).ingredientDrafts;
    if (drafts == null) {
      return const Scaffold(body: Center(child: Text('草稿已丢失')));
    }
    final selectedCount = drafts.where((d) => d.selected).length;

    return Scaffold(
      appBar: AppBar(title: const Text('审核识别结果')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: drafts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final d = drafts[i];
          final accent = d.selected ? const Color(0xFF0EA5E9) : Colors.grey;
          return InkWell(
            key: Key('ingredient_row_${d.id}'),
            onTap: () => ref.read(aiDraftProvider.notifier).updateIngredientDrafts([
              for (final e in drafts) e.id == d.id ? (e..selected = !e.selected) : e,
            ]),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: d.selected ? accent.withValues(alpha: 0.06) : Colors.grey.shade100,
                border: Border(left: BorderSide(color: accent, width: 3)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    d.selected ? Icons.check_box : Icons.check_box_outline_blank,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name.value, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          '${d.quantity.value} ${d.unit.value} · '
                          '${d.category.value ?? ''} · '
                          '${storageLabelFor(d.storage.value ?? IconType.fridge)} · '
                          '${d.shelfLifeDays.value ?? '-'} 天',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (regenerate != null)
              Expanded(
                child: OutlinedButton(
                  key: const Key('ingredient_review_regenerate'),
                  onPressed: () => regenerate!(),
                  child: const Text('重新识别'),
                ),
              ),
            if (regenerate != null) const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const Key('ingredient_review_confirm'),
                onPressed: selectedCount == 0
                    ? null
                    : () async {
                        final notifier = ref.read(inventoryProvider.notifier);
                        for (final d in drafts.where((d) => d.selected)) {
                          notifier.add(d.toIngredient());
                        }
                        ref.read(aiDraftProvider.notifier).clear();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已添加 $selectedCount 项')),
                        );
                        Navigator.of(context).maybePop();
                      },
                child: Text('入库 ($selectedCount 项)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

> Note: `inventoryProvider.notifier.add()` exists — verify in `lib/providers/inventory_provider.dart` and use the same async / sync signature when wiring tests.

- [ ] **Step 4: Run (PASS)**

```bash
flutter test test/ingredient_draft_review_screen_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/ingredient_draft_review_screen.dart test/ingredient_draft_review_screen_test.dart
git commit -m "feat(ai): add IngredientDraftReviewScreen with toggle + bulk save"
```

---

## Task 16: `AddIngredientScreen` 顶部「快速录入」三按钮 + 路由

**Files:**
- Modify: `lib/screens/add_ingredient_screen.dart`
- Test: `test/add_ingredient_quick_entry_test.dart`

- [ ] **Step 1: Write failing widget test**

```dart
// test/add_ingredient_quick_entry_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/ingredient_draft.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/add_ingredient_screen.dart';
import 'package:fresh_pantry/screens/ingredient_draft_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('three quick-entry buttons render', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: Scaffold(body: AddIngredientScreen())),
    ));
    expect(find.byKey(const Key('quick_camera')), findsOneWidget);
    expect(find.byKey(const Key('quick_text')), findsOneWidget);
    expect(find.byKey(const Key('quick_manual')), findsOneWidget);
  });

  testWidgets('text quick-entry with N≥2 results pushes review screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Scaffold(
          body: AddIngredientScreen(
            textParserOverride: (_) async => [
              IngredientDraft(
                id: 'a',
                name: DraftField.ai('番茄'),
                quantity: DraftField.ai('3'),
                unit: DraftField.ai('个'),
                category: DraftField.ai('蔬菜'),
                storage: DraftField.ai(IconType.fridge),
                shelfLifeDays: DraftField.ai(7),
              ),
              IngredientDraft(
                id: 'b',
                name: DraftField.ai('鸡蛋'),
                quantity: DraftField.ai('6'),
                unit: DraftField.ai('颗'),
                category: DraftField.ai('蛋奶'),
                storage: DraftField.ai(IconType.fridge),
                shelfLifeDays: DraftField.ai(30),
              ),
            ],
          ),
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('quick_text')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quick_text_input')), '番茄 3 个 鸡蛋 6 颗');
    await tester.tap(find.byKey(const Key('quick_text_parse')));
    await tester.pumpAndSettle();
    expect(find.byType(IngredientDraftReviewScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run (FAIL)**

```bash
flutter test test/add_ingredient_quick_entry_test.dart
```

- [ ] **Step 3: Modify**

In `add_ingredient_screen.dart`:

1. Extend constructor (add `prefillOnly` flag instead of using an `inventoryIndex: -1` sentinel):

```dart
const AddIngredientScreen({
  super.key,
  this.initialIngredient,
  this.inventoryIndex,
  this.prefillOnly = false,
  this.textParserOverride,
  this.imageParserOverride,
  this.imagePicker,
}) : assert(prefillOnly || initialIngredient == null || inventoryIndex != null);

final bool prefillOnly;
final Future<List<IngredientDraft>> Function(String text)? textParserOverride;
final Future<List<IngredientDraft>> Function(Uint8List bytes)? imageParserOverride;
final Future<Uint8List?> Function(ImageSource source)? imagePicker;
```

Update the `_isEditing` getter (line ~61 in the current file) to:

```dart
bool get _isEditing => widget.initialIngredient != null && !widget.prefillOnly;
```

2. Add the quick-entry row before the existing 「常购食材」 block in `build`:

```dart
// In build(), before the frequent-items block:
if (!_isEditing) ...[
  _buildQuickEntryRow(),
  const SizedBox(height: 24),
],
```

3. Add the helper widgets/methods:

```dart
Widget _buildQuickEntryRow() => Row(
      children: [
        Expanded(child: _quickButton(
          key: const Key('quick_camera'),
          icon: Icons.camera_alt_outlined,
          label: '拍照识别',
          onTap: _runCamera,
        )),
        const SizedBox(width: 8),
        Expanded(child: _quickButton(
          key: const Key('quick_text'),
          icon: Icons.edit_note,
          label: '粘贴清单',
          onTap: _runTextDialog,
        )),
        const SizedBox(width: 8),
        Expanded(child: _quickButton(
          key: const Key('quick_manual'),
          icon: Icons.edit,
          label: '手填',
          onTap: () => FocusScope.of(context).requestFocus(FocusNode()),
        )),
      ],
    );

Widget _quickButton({
  required Key key,
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) =>
    InkWell(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primaryFixed,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      ),
    );

Future<void> _runTextDialog() async {
  final controller = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('粘贴食材清单'),
      content: TextField(
        key: const Key('quick_text_input'),
        controller: controller,
        maxLines: 6,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '例：番茄 3 个 鸡蛋 6 颗 面条 1 把',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          key: const Key('quick_text_parse'),
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('解析'),
        ),
      ],
    ),
  );
  if (text == null || text.trim().isEmpty) return;
  await _runIngredientFlow(
    runner: () => (widget.textParserOverride ??
        (t) => AiIngredientParser.fromText(
              t,
              chatFn: (msgs) => AiClient.chat(
                settings: ref.read(aiSettingsProvider),
                messages: msgs,
                responseFormat: const {'type': 'json_object'},
              ),
            ))(text.trim()),
  );
}

Future<void> _runCamera() async {
  final picker = widget.imagePicker ?? _defaultImagePicker;
  final bytes = await picker(ImageSource.camera);
  if (bytes == null) return;
  await _runIngredientFlow(
    runner: () => (widget.imageParserOverride ??
        (b) => AiIngredientParser.fromImage(
              b,
              chatFn: (msgs) => AiClient.chat(
                settings: ref.read(aiSettingsProvider),
                messages: msgs,
              ),
            ))(bytes),
  );
}

Future<Uint8List?> _defaultImagePicker(ImageSource source) async {
  final image = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 82);
  return image == null ? null : await image.readAsBytes();
}

Future<void> _runIngredientFlow({required Future<List<IngredientDraft>> Function() runner}) async {
  try {
    final drafts = await runner();
    if (!mounted) return;
    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未识别到食材')),
      );
      return;
    }
    if (drafts.length == 1) {
      final ingredient = drafts.first.toIngredient();
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AddIngredientScreen(
          initialIngredient: ingredient,
          prefillOnly: true,
        )),
      );
      return;
    }
    ref.read(aiDraftProvider.notifier).updateIngredientDrafts(drafts);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IngredientDraftReviewScreen(regenerate: () => runner().then(
          (next) => ref.read(aiDraftProvider.notifier).updateIngredientDrafts(next),
        )),
      ),
    );
  } on AiNotConfiguredException {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
    );
  } on AiException catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
```

4. Add imports at top:

```dart
import 'dart:typed_data';
import '../models/ingredient_draft.dart';
import '../providers/ai_draft_provider.dart';
import '../providers/ai_settings_provider.dart';
import '../services/ai_client.dart';
import '../services/ai_ingredient_parser.dart';
import 'ai_settings_screen.dart';
import 'ingredient_draft_review_screen.dart';
import 'package:image_picker/image_picker.dart';
```

5. **No changes needed in `_save`**: with `prefillOnly: true`, `_isEditing` returns `false`, so the existing add-branch (`ref.read(inventoryProvider.notifier).add(ingredient)`) is taken naturally.

- [ ] **Step 4: Run (PASS)**

```bash
flutter test test/add_ingredient_quick_entry_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/add_ingredient_screen.dart test/add_ingredient_quick_entry_test.dart
git commit -m "feat(ai): add quick-entry row (camera / paste / manual) to AddIngredientScreen"
```

---

## Task 17: `AiIngredientParser.fromImage` integration test + 拍照入口验证

**Files:**
- Create: `test/fixtures/ai_responses/ingredient_image_fridge.json`
- Test: `test/ai_ingredient_parser_image_test.dart`

> Note: `fromImage` was already implemented in Task 14 alongside `fromText`. This task is the dedicated test pass for the image path.

- [ ] **Step 1: Create fixture**

```jsonc
// test/fixtures/ai_responses/ingredient_image_fridge.json
[
  {"name":"番茄","quantity":"4","unit":"个","category":"蔬菜","storage":"fridge","shelfLifeDays":7},
  {"name":"鸡蛋","quantity":"8","unit":"颗","category":"蛋奶","storage":"fridge","shelfLifeDays":30},
  {"name":"牛奶","quantity":"1","unit":"L","category":"蛋奶","storage":"fridge","shelfLifeDays":7}
]
```

- [ ] **Step 2: Write failing test**

```dart
// test/ai_ingredient_parser_image_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/ai_client.dart';
import 'package:fresh_pantry/services/ai_ingredient_parser.dart';

String _f(String name) => File('test/fixtures/ai_responses/$name').readAsStringSync();

void main() {
  test('fromImage encodes data URL and parses 3 items', () async {
    var capturedBody = '';
    final list = await AiIngredientParser.fromImage(
      Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
      chatFn: (messages) async {
        capturedBody = messages.last.toJson().toString();
        return _f('ingredient_image_fridge.json');
      },
    );
    expect(list.length, 3);
    expect(capturedBody, contains('image_url'));
    expect(capturedBody, contains('data:image/jpeg;base64,'));
  });

  test('fromImage with empty bytes throws ArgumentError', () async {
    expect(
      () => AiIngredientParser.fromImage(Uint8List(0), chatFn: (_) async => '[]'),
      throwsArgumentError,
    );
  });

  test('fromImage rethrows AiException from chatFn', () async {
    expect(
      () => AiIngredientParser.fromImage(
        Uint8List.fromList([0xFF]),
        chatFn: (_) async => throw const AiAuthException('401'),
      ),
      throwsA(isA<AiAuthException>()),
    );
  });
}
```

- [ ] **Step 3: Run (PASS — implementation already exists from Task 14)**

```bash
flutter test test/ai_ingredient_parser_image_test.dart
```

If any test fails, fix `fromImage` in `lib/services/ai_ingredient_parser.dart` accordingly (e.g., move the `if (imageBytes.isEmpty)` check before the `chatFn` call).

- [ ] **Step 4: Commit**

```bash
git add test/fixtures/ai_responses/ingredient_image_fridge.json test/ai_ingredient_parser_image_test.dart
git commit -m "test(ai): cover AiIngredientParser.fromImage with vision fixture"
```

---

## Task 18: Native plugin `receive_sharing_intent` + system share entry

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Modify: `lib/services/share_intent_service.dart` (add `SystemShareSource`)
- Modify: `lib/main.dart` (subscribe at boot)
- Modify: `lib/app.dart` (route to recipe form on inbound share)

> **Risk:** native integration is environment-sensitive; iOS Share Extension requires Xcode setup. Handle in this order: pubspec → wire pure Dart side with a stubbed `SystemShareSource` first, run, validate; then add Android intent-filter; iOS Share Extension last.

- [ ] **Step 1: Add dependency**

Edit `pubspec.yaml` under `dependencies:`:

```yaml
  receive_sharing_intent: ^1.8.1
```

Run:

```bash
flutter pub get
```

- [ ] **Step 2: Add Dart shim with injectable stream**

Append to `lib/services/share_intent_service.dart`:

```dart
import 'dart:async';

abstract class SystemShareSource {
  Stream<String> get incomingTextStream;  // each event = a piece of shared text (may contain a URL)
  Future<String?> consumeInitialText();    // text that opened the app, if any
}

/// In-memory source for tests; real impl wraps `receive_sharing_intent`.
class InMemoryShareSource implements SystemShareSource {
  final _ctrl = StreamController<String>.broadcast();
  String? _initial;

  void emit(String text) => _ctrl.add(text);
  set initial(String? v) => _initial = v;

  @override
  Stream<String> get incomingTextStream => _ctrl.stream;

  @override
  Future<String?> consumeInitialText() async {
    final t = _initial;
    _initial = null;
    return t;
  }

  void close() => _ctrl.close();
}

/// Extracts the first http(s) URL from arbitrary text. Reused for clipboard
/// + share intent.
String? extractUrl(String text) {
  final m = RegExp(r'https?://[^\s)\]"]+').firstMatch(text);
  return m?.group(0);
}
```

- [ ] **Step 3: Test the URL extraction shim**

Append to `test/clipboard_url_detector_test.dart`:

```dart
group('extractUrl', () {
  test('returns null for plain text', () {
    expect(extractUrl('no link here'), isNull);
  });
  test('grabs first URL from mixed text', () {
    expect(extractUrl('看 https://lanfanapp.com/recipe/15978 这个'),
        'https://lanfanapp.com/recipe/15978');
  });
});
```

(Add `import 'package:fresh_pantry/services/share_intent_service.dart';` if not already present.)

Run:

```bash
flutter test test/clipboard_url_detector_test.dart
```

Expected: PASS.

- [ ] **Step 4: Implement real `SystemShareSource` adapter**

Append to `share_intent_service.dart`:

```dart
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ReceiveSharingIntentSource implements SystemShareSource {
  @override
  Stream<String> get incomingTextStream =>
      ReceiveSharingIntent.instance.getMediaStream().map((items) =>
          items.map((e) => e.path).join(' '));  // path field carries text for shared text

  @override
  Future<String?> consumeInitialText() async {
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    final text = initial.map((e) => e.path).join(' ');
    ReceiveSharingIntent.instance.reset();
    return text.isEmpty ? null : text;
  }
}
```

> Validate the API surface against the installed version (`pub get` may pin a different one). The class names above match `receive_sharing_intent` 1.8.x. If the installed version differs, adjust accordingly.

- [ ] **Step 5: Subscribe in `main.dart` (handover to app shell)**

In `main.dart`, after creating prefs:

```dart
final shareSource = ReceiveSharingIntentSource();

runApp(
  ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      systemShareSourceProvider.overrideWithValue(shareSource),
    ],
    child: const FreshPantryApp(),
  ),
);
```

Add a provider near `aiSettingsProvider`:

```dart
// lib/providers/ai_draft_provider.dart  (append at end)
final systemShareSourceProvider = Provider<SystemShareSource>((_) {
  throw UnimplementedError('Override in main with a real SystemShareSource.');
});
```

Add the import at top of `ai_draft_provider.dart`:

```dart
import '../services/share_intent_service.dart';
```

- [ ] **Step 6: In `AppShell`, subscribe to incoming shares and route**

Modify `app.dart` `AppShell` to a `ConsumerStatefulWidget`. In `initState`:

```dart
@override
void initState() {
  super.initState();
  final source = ref.read(systemShareSourceProvider);
  source.consumeInitialText().then(_handleSharedText);
  source.incomingTextStream.listen(_handleSharedText);
}

void _handleSharedText(String? text) {
  if (text == null || text.isEmpty || !mounted) return;
  final url = extractUrl(text);
  if (url == null) return;
  ref.read(navigationProvider.notifier).state = 0; // dashboard
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CustomRecipeFormScreen(prefilledUrl: url)),
  );
}
```

Then add a `prefilledUrl` constructor param to `CustomRecipeFormScreen` (defaulting `_urlController.text` to that value in initState).

- [ ] **Step 7: Native Android intent filter**

Add inside `<activity>` in `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter>
  <action android:name="android.intent.action.SEND" />
  <category android:name="android.intent.category.DEFAULT" />
  <data android:mimeType="text/plain" />
</intent-filter>
```

- [ ] **Step 8: iOS Share Extension scaffold**

Follow the `receive_sharing_intent` README to add the iOS Share Extension target. Key steps (high-level — refer to plugin docs for current scripts):
1. In Xcode, add a new "Share Extension" target named `Share Extension` to `Runner.xcodeproj`.
2. Configure shared App Group on both `Runner` and `Share Extension`.
3. Update `Info.plist` of the extension to accept text URLs.
4. Wire the extension to write into shared user defaults using the plugin's helper.

This step is **out of scope of automated CI**; verify manually on a physical device.

- [ ] **Step 9: Manual smoke test**

- Long-press a URL in another app → "Share" → Fresh Pantry → CustomRecipeFormScreen opens with the URL pre-filled in the AI banner.
- App is running: same flow → SnackBar / form prefilled without restart.

- [ ] **Step 10: Commit**

```bash
git add pubspec.yaml pubspec.lock \
        android/app/src/main/AndroidManifest.xml \
        lib/services/share_intent_service.dart \
        lib/providers/ai_draft_provider.dart \
        lib/main.dart lib/app.dart \
        lib/screens/custom_recipe_form_screen.dart \
        test/clipboard_url_detector_test.dart
git commit -m "feat(ai): receive shared URLs via receive_sharing_intent"
```

(`ios/` Share Extension changes commit separately if/when the user has run the Xcode steps.)

---

## Self-Review Checklist (run before handing off)

After implementing, run all tests once:

```bash
flutter test
```

All green is the bar.

Then walk the spec → plan map:

| Spec ref | Task |
|---|---|
| §3.1 AiSettings | 1 |
| §3.2 DraftField, RecipeDraft | 6, 7 |
| §3.3 IngredientDraft | 7 |
| §4.1 AiClient interface | 3 |
| §4.2 prompts (3 services) | 10 (recipe), 14 (ingredient text), 14+17 (image) |
| §4.3 exceptions | 3 |
| §5.2 AiSettingsScreen + 测试连接 | 4 |
| §5.2 CustomRecipeFormScreen banner + clipboard | 12, 13 |
| §5.2 Recipe review | 11 |
| §5.2 AddIngredientScreen 三按钮 | 16 |
| §5.2 IngredientDraftReviewScreen | 15 |
| §5.3 路由 / 状态 | 11, 15, 16 |
| §6 错误矩阵 | 3 (types), 4 / 12 / 16 (UI dispatch) |
| §7 边界（0/1/≥2 分支） | 16 |
| §7 剪贴板 30 分钟去重 | 13 |
| §8.1 测试结构 | covered by per-task tests |
| §10 后续 spec 衔接 | informational |
| Settings 入口（齿轮 + 未配置跳转） | 5 (gear), 12 / 16 (unconfigured catch) |
| 系统分享 | 18 |

Any spec section without a row → add a task. Any task without a spec ref → likely scope creep, drop it.

---

## Manual verification checklist (post-implementation)

- [ ] Real OpenAI / custom service: 1 lanfan URL → review → save (food-detail page shows the new recipe)
- [ ] One fridge photo → ≥3 ingredients identified → bulk save → inventory contains them
- [ ] Single text "番茄 3 个" → goes directly to AddIngredientScreen prefilled (skips review)
- [ ] Network off → AI button shows network error, app does not crash
- [ ] Settings test connection: ✓ / 401 / 网络断 / 模型不存在 各显示对应文案
- [ ] Clipboard with URL → entering CustomRecipeFormScreen → prompt visible
- [ ] Long-press share from another app → Fresh Pantry opens with URL prefilled
- [ ] Discard a draft → state cleared, no orphan in `aiDraftProvider`
