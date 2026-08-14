import 'dart:convert';

import 'package:http/http.dart' as http;

/// A built-in preset for a cloud AI provider that speaks the OpenAI
/// `chat/completions` wire format — which covers NVIDIA's NIM catalog and
/// most of the other providers with a free tier, so one client implementation
/// (see [CloudAiClient]) works for all of them.
class CloudAiProviderPreset {
  const CloudAiProviderPreset({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.description,
    required this.suggestedFreeModels,
    required this.keyHelpUrl,
  });

  final String id;
  final String label;

  /// Base URL up to and including `/v1`; the client appends
  /// `/chat/completions`. Empty for the 'custom' preset, where the person
  /// supplies their own.
  final String baseUrl;
  final String description;

  /// A few example model IDs known to have a free tier on this provider, so
  /// the settings screen can offer them as quick picks. Not exhaustive —
  /// the person can type any model ID the provider supports.
  final List<String> suggestedFreeModels;
  final String keyHelpUrl;
}

/// Providers offered out of the box. NVIDIA's NIM catalog and OpenRouter's
/// free-tier models are both commonly used as no-cost/low-cost ways to try
/// larger hosted models than a phone can run locally; Groq's free tier is
/// included for its speed. "Custom" lets the person point at any other
/// OpenAI-compatible endpoint (a self-hosted server, a different host, etc).
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
      'meta-llama/llama-3.1-8b-instruct:free',
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
    id: 'custom',
    label: 'Custom (OpenAI-compatible)',
    baseUrl: '',
    description:
        'Any other server that implements the OpenAI chat/completions API '
        '— point it at your own base URL.',
    suggestedFreeModels: <String>[],
    keyHelpUrl: '',
  ),
];

CloudAiProviderPreset cloudAiProviderById(String id) => kCloudAiProviders
    .firstWhere((p) => p.id == id, orElse: () => kCloudAiProviders.first);

/// Thin client for the OpenAI-compatible `chat/completions` endpoint. The
/// API key never touches anything but this device and the provider's own
/// endpoint — QuietNote has no server of its own in between.
class CloudAiClient {
  const CloudAiClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  Future<String> chat({
    required String systemPrompt,
    required String userMessage,
    double temperature = 0.4,
    int maxTokens = 512,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw StateError('No API key configured for this provider.');
    }
    if (model.trim().isEmpty) {
      throw StateError('No model selected for this provider.');
    }
    final Uri uri = Uri.parse(
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions',
    );

    final response = await http
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(<String, dynamic>{
            'model': model,
            'messages': <Map<String, String>>[
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userMessage},
            ],
            'temperature': temperature,
            'max_tokens': maxTokens,
            'stream': false,
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Request failed (${response.statusCode}): ${_shortBody(response.body)}',
      );
    }

    final Map<String, dynamic> data =
        jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic>? choices = data['choices'] as List<dynamic>?;
    String? content;
    if (choices != null && choices.isNotEmpty) {
      final Map<String, dynamic> first = choices.first as Map<String, dynamic>;
      final Map<String, dynamic>? message =
          first['message'] as Map<String, dynamic>?;
      content = message?['content'] as String?;
    }
    final String? trimmed = content?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      throw StateError('The provider returned an empty response.');
    }
    return trimmed;
  }

  static String _shortBody(String body) =>
      body.length > 300 ? '${body.substring(0, 300)}…' : body;
}
