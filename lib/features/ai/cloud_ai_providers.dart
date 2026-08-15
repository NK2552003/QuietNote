import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A built-in preset for a cloud AI provider that speaks the OpenAI
/// `chat/completions` wire format — which covers NVIDIA's NIM catalog,
/// Google's OpenAI-compatible Gemini endpoint, Groq, OpenRouter and most
/// other providers with a free tier, so one client implementation (see
/// [CloudAiClient]) works for all of them.
class CloudAiProviderPreset {
  const CloudAiProviderPreset({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.description,
    required this.suggestedFreeModels,
    required this.keyHelpUrl,
    this.requiresKey = true,
  });

  final String id;
  final String label;

  /// Base URL up to and including `/v1`; the client appends
  /// `/chat/completions`. Empty for the 'custom' preset, where the person
  /// supplies their own.
  final String baseUrl;
  final String description;

  /// A few example model IDs known to work (and mostly to have a free tier)
  /// on this provider, so the settings screen can offer them as quick picks.
  /// Not exhaustive — any model ID the provider supports can be typed in.
  final List<String> suggestedFreeModels;
  final String keyHelpUrl;

  /// Local servers such as Ollama or LM Studio accept requests without a key.
  final bool requiresKey;

  bool get isCustom => id == 'custom' || id == 'ollama' || id == 'lmstudio';
}

/// Providers offered out of the box. Everything here speaks the OpenAI
/// `chat/completions` format, so a key plus a model ID is all that is needed.
const List<CloudAiProviderPreset> kCloudAiProviders = <CloudAiProviderPreset>[
  CloudAiProviderPreset(
    id: 'nvidia',
    label: 'NVIDIA NIM',
    baseUrl: 'https://integrate.api.nvidia.com/v1',
    description:
        'NVIDIA\'s hosted model catalog. Free API keys are available for '
        'personal/dev use with generous rate limits.',
    suggestedFreeModels: <String>[
      'meta/llama-3.1-8b-instruct',
      'meta/llama-3.3-70b-instruct',
      'mistralai/mixtral-8x7b-instruct-v0.1',
    ],
    keyHelpUrl: 'https://build.nvidia.com',
  ),
  CloudAiProviderPreset(
    id: 'openrouter',
    label: 'OpenRouter (free models)',
    baseUrl: 'https://openrouter.ai/api/v1',
    description:
        'A router in front of many hosted models; several are free '
        '(model IDs ending in ":free").',
    suggestedFreeModels: <String>[
      'meta-llama/llama-3.3-70b-instruct:free',
      'google/gemma-2-9b-it:free',
      'mistralai/mistral-7b-instruct:free',
    ],
    keyHelpUrl: 'https://openrouter.ai/keys',
  ),
  CloudAiProviderPreset(
    id: 'groq',
    label: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1',
    description: 'Free-tier hosted inference, notably fast.',
    suggestedFreeModels: <String>[
      'llama-3.1-8b-instant',
      'llama-3.3-70b-versatile',
    ],
    keyHelpUrl: 'https://console.groq.com/keys',
  ),
  CloudAiProviderPreset(
    id: 'gemini',
    label: 'Google Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    description:
        'Google AI Studio keys work here through Gemini\'s '
        'OpenAI-compatible endpoint. Free tier available.',
    suggestedFreeModels: <String>[
      'gemini-2.0-flash',
      'gemini-2.5-flash',
      'gemini-2.5-flash-lite',
    ],
    keyHelpUrl: 'https://aistudio.google.com/apikey',
  ),
  CloudAiProviderPreset(
    id: 'mistral',
    label: 'Mistral AI',
    baseUrl: 'https://api.mistral.ai/v1',
    description: 'Mistral\'s hosted models, with a free experimental tier.',
    suggestedFreeModels: <String>[
      'mistral-small-latest',
      'open-mistral-nemo',
    ],
    keyHelpUrl: 'https://console.mistral.ai/api-keys',
  ),
  CloudAiProviderPreset(
    id: 'cerebras',
    label: 'Cerebras',
    baseUrl: 'https://api.cerebras.ai/v1',
    description: 'Very fast free-tier inference for Llama models.',
    suggestedFreeModels: <String>[
      'llama3.1-8b',
      'llama-3.3-70b',
    ],
    keyHelpUrl: 'https://cloud.cerebras.ai',
  ),
  CloudAiProviderPreset(
    id: 'together',
    label: 'Together AI',
    baseUrl: 'https://api.together.xyz/v1',
    description: 'Large open-model catalog with free starter credit.',
    suggestedFreeModels: <String>[
      'meta-llama/Llama-3.3-70B-Instruct-Turbo-Free',
    ],
    keyHelpUrl: 'https://api.together.xyz/settings/api-keys',
  ),
  CloudAiProviderPreset(
    id: 'openai',
    label: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    description: 'Paid, but the most predictable quality.',
    suggestedFreeModels: <String>['gpt-4o-mini', 'gpt-4.1-mini'],
    keyHelpUrl: 'https://platform.openai.com/api-keys',
  ),
  CloudAiProviderPreset(
    id: 'deepseek',
    label: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    description: 'Low-cost hosted DeepSeek models.',
    suggestedFreeModels: <String>['deepseek-chat'],
    keyHelpUrl: 'https://platform.deepseek.com/api_keys',
  ),
  CloudAiProviderPreset(
    id: 'ollama',
    label: 'Ollama (your own machine)',
    baseUrl: '',
    description:
        'Run models on your computer with Ollama and point the phone at it, '
        'e.g. http://192.168.1.20:11434/v1 — no API key needed.',
    suggestedFreeModels: <String>['llama3.2', 'qwen2.5', 'gemma2'],
    keyHelpUrl: 'https://ollama.com',
    requiresKey: false,
  ),
  CloudAiProviderPreset(
    id: 'lmstudio',
    label: 'LM Studio (your own machine)',
    baseUrl: '',
    description:
        'LM Studio\'s local server, e.g. http://192.168.1.20:1234/v1 — '
        'no API key needed.',
    suggestedFreeModels: <String>[],
    keyHelpUrl: 'https://lmstudio.ai',
    requiresKey: false,
  ),
  CloudAiProviderPreset(
    id: 'custom',
    label: 'Custom (OpenAI-compatible)',
    baseUrl: '',
    description:
        'Any other server that implements the OpenAI chat/completions API '
        '— point it at your own base URL.',
    suggestedFreeModels: <String>[],
    keyHelpUrl: '',
    requiresKey: false,
  ),
];

CloudAiProviderPreset cloudAiProviderById(String id) => kCloudAiProviders
    .firstWhere((CloudAiProviderPreset p) => p.id == id,
        orElse: () => kCloudAiProviders.first);

/// One turn of conversation handed to [CloudAiClient.chat].
class AiChatTurn {
  const AiChatTurn({required this.role, required this.content});
  const AiChatTurn.user(this.content) : role = 'user';
  const AiChatTurn.assistant(this.content) : role = 'assistant';

  final String role;
  final String content;

  Map<String, String> toJson() =>
      <String, String>{'role': role, 'content': content};
}

/// Raised for every failed cloud request, with a message that is safe and
/// useful to show directly in the UI.
class CloudAiException implements Exception {
  CloudAiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Thin client for the OpenAI-compatible `chat/completions` endpoint. The
/// API key never touches anything but this device and the provider's own
/// endpoint — QuietNote has no server of its own in between.
class CloudAiClient {
  CloudAiClient({
    required String baseUrl,
    required this.apiKey,
    required this.model,
    this.requiresKey = true,
    http.Client? httpClient,
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final bool requiresKey;
  final http.Client _http;

  /// Accepts what people actually paste: a bare host, a URL with a trailing
  /// slash, or a full `/chat/completions` URL, and normalises all of them to
  /// the API root the client can append paths to.
  static String normalizeBaseUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    url = url.replaceAll(RegExp(r'/chat/completions$'), '');
    url = url.replaceAll(RegExp(r'/+$'), '');
    // A bare host with no version segment: assume the conventional /v1.
    final Uri? parsed = Uri.tryParse(url);
    if (parsed != null && (parsed.path.isEmpty || parsed.path == '/')) {
      url = '$url/v1';
    }
    return url;
  }

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
        // OpenRouter asks callers to identify themselves; harmless elsewhere.
        'HTTP-Referer': 'https://quietnote.app',
        'X-Title': 'QuietNote',
      };

  void _validate() {
    if (baseUrl.isEmpty) {
      throw CloudAiException(
        'No base URL set for this provider. Add it in Settings > AI.',
      );
    }
    if (requiresKey && apiKey.trim().isEmpty) {
      throw CloudAiException(
        'No API key set. Paste your key in Settings > AI.',
      );
    }
    if (model.trim().isEmpty) {
      throw CloudAiException(
        'No model ID set. Pick or type one in Settings > AI.',
      );
    }
  }

  /// Sends a chat completion request and returns the assistant text.
  Future<String> chat({
    String? systemPrompt,
    String? userMessage,
    List<AiChatTurn> history = const <AiChatTurn>[],
    double temperature = 0.4,
    int maxTokens = 512,
    bool jsonMode = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    _validate();

    final List<Map<String, String>> messages = <Map<String, String>>[
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
        <String, String>{'role': 'system', 'content': systemPrompt},
      for (final AiChatTurn turn in history) turn.toJson(),
      if (userMessage != null && userMessage.trim().isNotEmpty)
        <String, String>{'role': 'user', 'content': userMessage},
    ];
    if (messages.where((Map<String, String> m) => m['role'] != 'system').isEmpty) {
      throw CloudAiException('Nothing to send — the message was empty.');
    }

    final Map<String, dynamic> body = <String, dynamic>{
      'model': model.trim(),
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': false,
      if (jsonMode)
        'response_format': <String, String>{'type': 'json_object'},
    };

    http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw CloudAiException(
        'The provider took too long to answer. Check your connection and try '
        'again, or pick a smaller model.',
      );
    } catch (e) {
      throw CloudAiException(
        'Could not reach the provider. Check your internet connection and the '
        'base URL. ($e)',
      );
    }

    if (response.statusCode == 400 && jsonMode) {
      // Some providers reject response_format; retry once without it.
      return chat(
        systemPrompt: systemPrompt,
        userMessage: userMessage,
        history: history,
        temperature: temperature,
        maxTokens: maxTokens,
        jsonMode: false,
        timeout: timeout,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudAiException(
        _describeFailure(response.statusCode, response.body),
        statusCode: response.statusCode,
      );
    }

    return _extractContent(response.body);
  }

  /// Lists the model IDs the provider exposes, so people don't have to guess.
  Future<List<String>> listModels({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (baseUrl.isEmpty) {
      throw CloudAiException('Add a base URL first.');
    }
    if (requiresKey && apiKey.trim().isEmpty) {
      throw CloudAiException('Add an API key first.');
    }
    http.Response response;
    try {
      response = await _http
          .get(Uri.parse('$baseUrl/models'), headers: _headers)
          .timeout(timeout);
    } on TimeoutException {
      throw CloudAiException('Listing models timed out.');
    } catch (e) {
      throw CloudAiException('Could not reach the provider. ($e)');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudAiException(
        _describeFailure(response.statusCode, response.body),
        statusCode: response.statusCode,
      );
    }
    try {
      final dynamic decoded = jsonDecode(response.body);
      final List<dynamic> data = decoded is Map<String, dynamic>
          ? (decoded['data'] as List<dynamic>? ?? const <dynamic>[])
          : (decoded as List<dynamic>);
      final List<String> ids = <String>[
        for (final dynamic item in data)
          if (item is Map<String, dynamic>)
            (item['id'] ?? item['name'] ?? '').toString()
          else
            item.toString(),
      ]..removeWhere((String id) => id.trim().isEmpty);
      ids.sort();
      return ids;
    } catch (_) {
      throw CloudAiException('The provider returned an unexpected model list.');
    }
  }

  static String _extractContent(String rawBody) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(rawBody) as Map<String, dynamic>;
    } catch (_) {
      throw CloudAiException('The provider returned a malformed response.');
    }

    final Object? error = data['error'];
    if (error != null) {
      throw CloudAiException('Provider error: ${_errorText(error)}');
    }

    final List<dynamic>? choices = data['choices'] as List<dynamic>?;
    String? content;
    if (choices != null && choices.isNotEmpty) {
      final Map<String, dynamic> first = choices.first as Map<String, dynamic>;
      final Map<String, dynamic>? message =
          first['message'] as Map<String, dynamic>?;
      final Object? raw = message?['content'] ?? first['text'];
      if (raw is String) {
        content = raw;
      } else if (raw is List) {
        // Some providers return content as an array of typed parts.
        content = raw
            .map((dynamic part) => part is Map<String, dynamic>
                ? (part['text'] ?? '').toString()
                : part.toString())
            .join();
      }
      // Reasoning models sometimes put the answer in `reasoning_content`.
      if ((content == null || content.trim().isEmpty) && message != null) {
        content = (message['reasoning_content'] ?? '').toString();
      }
    }

    final String cleaned = stripReasoning(content ?? '');
    if (cleaned.isEmpty) {
      throw CloudAiException(
        'The provider returned an empty response. Try another model.',
      );
    }
    return cleaned;
  }

  /// Removes `<think>…</think>` blocks that reasoning models emit before the
  /// actual answer, so the UI never shows raw scratchpad text.
  static String stripReasoning(String text) => text
      .replaceAll(
        RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'<\|?(?:assistant|end|eot_id)\|?>', caseSensitive: false),
        '',
      )
      .trim();

  static String _errorText(Object? error) {
    if (error is Map) {
      final Object? message = error['message'] ?? error['detail'];
      if (message != null) return message.toString();
    }
    return error.toString();
  }

  static String _describeFailure(int status, String body) {
    final String detail = _shortBody(body);
    switch (status) {
      case 401:
        return 'The API key was rejected (401). Check that you pasted the '
            'whole key for the selected provider.';
      case 403:
        return 'Access denied (403). The key may not be allowed to use this '
            'model. $detail';
      case 404:
        return 'Not found (404). The model ID or base URL is probably wrong. '
            '$detail';
      case 413:
        return 'The request was too large (413). Try shorter text.';
      case 422:
        return 'The provider rejected the request (422). $detail';
      case 429:
        return 'Rate limit or quota reached (429). Wait a moment, or switch to '
            'another model/provider.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'The provider is having trouble ($status). Try again shortly.';
      default:
        return 'Request failed ($status): $detail';
    }
  }

  static String _shortBody(String body) {
    final String trimmed = body.trim();
    if (trimmed.isEmpty) return '';
    try {
      final dynamic decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic> && decoded['error'] != null) {
        return _errorText(decoded['error']);
      }
    } catch (_) {
      // Not JSON — fall through to the raw excerpt.
    }
    return trimmed.length > 240 ? '${trimmed.substring(0, 240)}…' : trimmed;
  }
}
