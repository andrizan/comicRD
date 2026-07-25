import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.releaseUrl,
  });

  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final String releaseUrl;
}

class UpdateChecker {
  static const _repo = 'andrizan/comicRD';
  static const _apiUrl = 'https://api.github.com/repos/$_repo/releases/latest';

  static Future<UpdateInfo?> check() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(_apiUrl));
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        client.close(force: false);
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      client.close(force: false);

      final json = jsonDecode(body) as Map<String, dynamic>;
      final tagName =
          (json['tag_name'] as String?)?.replaceFirst('v', '') ?? '';
      final releaseNotes = (json['body'] as String?) ?? '';
      final releaseUrl = (json['html_url'] as String?) ?? '';

      final assets = (json['assets'] as List?) ?? [];
      String? downloadUrl;
      for (final asset in assets) {
        final name = (asset['name'] as String?) ?? '';
        if (name.endsWith('.exe') && name.contains('setup')) {
          downloadUrl = asset['browser_download_url'] as String?;
          break;
        }
      }

      if (tagName.isEmpty || downloadUrl == null) return null;

      final current = await PackageInfo.fromPlatform();
      if (_isNewer(tagName, current.version)) {
        return UpdateInfo(
          latestVersion: tagName,
          downloadUrl: downloadUrl,
          releaseNotes: releaseNotes,
          releaseUrl: releaseUrl,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _isNewer(String latest, String current) {
    final lParts = latest.split('.').map(int.tryParse).toList();
    final cParts = current.split('.').map(int.tryParse).toList();
    final len = [lParts.length, cParts.length].reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < len; i++) {
      final l = i < lParts.length ? (lParts[i] ?? 0) : 0;
      final c = i < cParts.length ? (cParts[i] ?? 0) : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}
