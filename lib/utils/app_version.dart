import 'package:flutter/services.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

Future<String> getAppVersion() async {
  final pubspecContent = await rootBundle.loadString('pubspec.yaml');
  final pubspec = Pubspec.parse(pubspecContent);
  return pubspec.version.toString();
}

/// Compare stable release tags with the version bundled into the app.
bool isNewerAppVersion(String available, String current) {
  List<int> components(String value) {
    final match =
        RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$').firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid stable app version', value);
    }
    return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  final remote = components(available);
  final local = components(current);
  for (var i = 0; i < 3; i++) {
    if (remote[i] != local[i]) return remote[i] > local[i];
  }
  return false;
}
