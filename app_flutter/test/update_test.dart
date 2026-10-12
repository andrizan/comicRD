import 'package:comicrd_flutter/state/update_state.dart';
import 'package:comicrd_flutter/utils/update_checker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _release({
  String tag = 'v2.9.0',
  bool installer = true,
  String notes = 'Fixes',
}) {
  return {
    'tag_name': tag,
    'body': notes,
    'html_url': 'https://github.com/andrizan/comicRD/releases/tag/$tag',
    'assets': [
      {
        'name': 'comicrd-linux-x86_64.tar.gz',
        'browser_download_url': 'https://example.invalid/linux.tar.gz',
      },
      if (installer)
        {
          'name': 'comicrd-2.9.0-windows-x86_64-setup.exe',
          'browser_download_url': 'https://example.invalid/setup.exe',
        },
    ],
  };
}

void main() {
  group('UpdateChecker.isNewer', () {
    test('compares segment by segment', () {
      expect(UpdateChecker.isNewer('2.9.0', '2.8.3'), isTrue);
      expect(UpdateChecker.isNewer('2.8.3', '2.8.3'), isFalse);
      expect(UpdateChecker.isNewer('2.8.2', '2.8.3'), isFalse);
      expect(UpdateChecker.isNewer('3.0.0', '2.99.99'), isTrue);
    });

    test('treats missing and non-numeric segments as zero', () {
      expect(UpdateChecker.isNewer('2.9', '2.8.3'), isTrue);
      expect(UpdateChecker.isNewer('2.8.3.1', '2.8.3'), isTrue);
      expect(UpdateChecker.isNewer('2.8.3-beta', '2.8.3'), isFalse);
    });
  });

  group('UpdateChecker.parseRelease', () {
    test('returns the update when a newer installer release exists', () {
      final info = UpdateChecker.parseRelease(
        _release(),
        currentVersion: '2.8.3',
      );

      expect(info, isNotNull);
      expect(info!.latestVersion, '2.9.0');
      expect(info.downloadUrl, 'https://example.invalid/setup.exe');
      expect(info.releaseNotes, 'Fixes');
      expect(info.releaseUrl, contains('v2.9.0'));
    });

    test('returns null when already up to date', () {
      expect(
        UpdateChecker.parseRelease(_release(), currentVersion: '2.9.0'),
        isNull,
      );
    });

    test('returns null without an installer asset or tag', () {
      expect(
        UpdateChecker.parseRelease(
          _release(installer: false),
          currentVersion: '1.0.0',
        ),
        isNull,
      );
      expect(
        UpdateChecker.parseRelease(_release(tag: ''), currentVersion: '1.0.0'),
        isNull,
      );
    });
  });

  group('UpdateNotifier', () {
    test('reports an available update, then dismisses it', () async {
      final container = ProviderContainer(
        overrides: [
          updateCheckerProvider.overrideWithValue(
            () async => const UpdateInfo(
              latestVersion: '9.9.9',
              downloadUrl: 'https://example.invalid/setup.exe',
              releaseNotes: '',
              releaseUrl: '',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final check = container.read(updateProvider.notifier).checkForUpdates();
      expect(container.read(updateProvider).status, UpdateStatus.checking);
      await check;

      expect(container.read(updateProvider).status, UpdateStatus.available);
      expect(container.read(updateProvider).info?.latestVersion, '9.9.9');

      container.read(updateProvider.notifier).dismiss();
      expect(container.read(updateProvider).status, UpdateStatus.idle);
      expect(container.read(updateProvider).info, isNull);
    });

    test('reports up to date when the lookup finds nothing', () async {
      final container = ProviderContainer(
        overrides: [updateCheckerProvider.overrideWithValue(() async => null)],
      );
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).checkForUpdates();

      expect(container.read(updateProvider).status, UpdateStatus.upToDate);
    });
  });
}
