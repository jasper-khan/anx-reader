import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/utils/app_version.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

const _releaseApi =
    'https://api.github.com/repos/jasper-khan/anx-reader/releases/latest';
const _releasePage =
    'https://github.com/jasper-khan/anx-reader/releases/latest';

Future<void> checkUpdate(bool manualCheck) async {
  if (!EnvVar.enableCheckUpdate) {
    return;
  }
  // if is today
  if (!manualCheck &&
      DateTime.now().difference(Prefs().lastShowUpdate) <
          const Duration(days: 1)) {
    return;
  }
  Prefs().lastShowUpdate = DateTime.now();

  final context = navigatorKey.currentContext;
  if (context == null) return;

  late final Map<String, dynamic> release;
  late final String newVersion;
  late final String currentVersion;
  late final bool needUpdate;
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Accept': 'application/vnd.github+json'},
  ));
  try {
    final response = await dio.get<Map<String, dynamic>>(_releaseApi);
    final data = response.data;
    if (data == null ||
        data['draft'] != false ||
        data['prerelease'] != false ||
        data['tag_name'] is! String) {
      throw const FormatException('Invalid stable GitHub release');
    }
    release = data;
    newVersion = (data['tag_name'] as String).replaceFirst(RegExp(r'^v'), '');
    currentVersion = (await getAppVersion()).split('+').first;
    needUpdate = isNewerAppVersion(newVersion, currentVersion);
  } catch (e) {
    if (manualCheck && context.mounted) {
      AnxToast.show(L10n.of(context).commonFailed);
    }
    AnxLog.severe('Update: Failed to check for updates $e');
    return;
  } finally {
    dio.close();
  }
  if (!context.mounted) return;
  AnxLog.info('Update: new version $newVersion');

  if (needUpdate) {
    if (manualCheck) {
      Navigator.of(context).pop();
    }
    SmartDialog.show(
      builder: (BuildContext context) {
        final body = release['body'] as String? ?? '';
        return AlertDialog(
          title: Text(L10n.of(context).commonNewVersion,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              )),
          content: SingleChildScrollView(
            child: StyledMarkdown(
                data: '''### ${L10n.of(context).updateNewVersion} $newVersion\n
${L10n.of(context).updateCurrentVersion} $currentVersion\n
$body'''),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
              },
              child: Text(L10n.of(context).commonCancel),
            ),
            TextButton(
              onPressed: () {
                launchUrl(Uri.parse(_releasePage),
                    mode: LaunchMode.externalApplication);
              },
              child: Text(L10n.of(context).updateViaGithub),
            ),
          ],
        );
      },
    );
  } else {
    if (manualCheck) {
      AnxToast.show(L10n.of(context).commonNoNewVersion);
    }
  }
}
