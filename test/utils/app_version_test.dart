import 'package:anx_reader/utils/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compares stable patch versions numerically', () {
    expect(isNewerAppVersion('v1.15.10', '1.15.9+6342'), isTrue);
    expect(isNewerAppVersion('1.15.2', '1.15.10'), isFalse);
    expect(isNewerAppVersion('v1.15.1', '1.15.1+6342'), isFalse);
  });

  test('compares major and minor versions before patches', () {
    expect(isNewerAppVersion('v1.16.0', '1.15.99'), isTrue);
    expect(isNewerAppVersion('v2.0.0', '1.99.99'), isTrue);
    expect(isNewerAppVersion('v1.14.99', '1.15.1'), isFalse);
  });

  test('rejects prereleases and malformed release tags', () {
    for (final tag in ['v1.15.1-alpha.1', 'v1.15.1-beta.1', '', 'v1.15']) {
      expect(() => isNewerAppVersion(tag, '1.15.0'), throwsFormatException);
    }
  });
}
