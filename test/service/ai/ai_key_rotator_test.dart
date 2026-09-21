import 'package:anx_reader/enums/ai_reasoning_effort.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/ai/ai_key_rotator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AiProvider providerWithKeys({required int keyIndex}) {
    return AiProvider(
      id: 'provider',
      title: 'Test provider',
      url: 'https://example.invalid',
      protocol: AiProtocol.openai,
      keyIndex: keyIndex,
      reasoningEffort: AiReasoningEffort.auto,
      apiKeys: const [
        AiApiKey(id: 'blank', key: '   '),
        AiApiKey(id: 'first', key: 'test-key-1'),
        AiApiKey(id: 'second', key: 'test-key-2'),
      ],
    );
  }

  test('skips enabled API keys that contain only whitespace', () {
    final provider = providerWithKeys(keyIndex: 0);

    expect(AiKeyRotator.getNextKey(provider), 'test-key-1');
    expect(AiKeyRotator.hasValidKey(provider), isTrue);
    expect(AiKeyRotator.getEnabledKeys(provider), [
      'test-key-1',
      'test-key-2',
    ]);
  });

  test('round robin index is based on non-empty enabled keys', () {
    final provider = providerWithKeys(keyIndex: 1);

    expect(AiKeyRotator.getNextKey(provider), 'test-key-2');
  });
}
