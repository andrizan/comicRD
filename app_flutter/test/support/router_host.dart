// Hosts one page under a private GoRouter whose other routes render their
// location as text, so navigation can be asserted without the app shell.
import 'package:comicrd_flutter/routes/path_codec.dart';
import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/state/library_state.dart';
import 'package:comicrd_flutter/state/settings_data_state.dart';
import 'package:comicrd_flutter/state/settings_state.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_api.dart';

Future<void> pumpRoutedPage(
  WidgetTester tester, {
  required FakeComicRdApi api,
  required Widget page,
  Size size = const Size(1280, 800),
  // Extra provider overrides. flutter_riverpod does not export the
  // `Override` type, so the list is untyped and cast by the scope.
  List<dynamic> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => page),
      GoRoute(
        path: '/comic/:comicPath',
        builder: (context, state) => _RouteStub(
          'comic:${decodeRoutePath(state.pathParameters['comicPath'] ?? '')}',
        ),
      ),
      GoRoute(
        path: '/reader/:chapterId',
        builder: (context, state) =>
            _RouteStub('reader:${state.pathParameters['chapterId']}'),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const _RouteStub('settings'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [comicRdApiProvider.overrideWithValue(api), ...overrides],
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(
          fontFamily: appFontFamily,
          extensions: const [ComicReaderColors.light],
        ),
        builder: (context, child) => FTheme(
          data: ComicReaderFTheme.light,
          child: FToaster(
            child: FTooltipGroup(child: _SettingsHydrator(child: child!)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Mirrors what the app shell does: pushes the stored settings into the
/// app, library and reader notifiers once they load.
class _SettingsHydrator extends ConsumerWidget {
  const _SettingsHydrator({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<Map<String, String>>>(settingsMapProvider, (_, next) {
      next.whenData((values) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          ref.read(appSettingsProvider.notifier).hydrateFromSettings(values);
          ref
              .read(libraryPreferencesProvider.notifier)
              .hydrateFromSettings(values);
          ref.read(readerSettingsProvider.notifier).hydrateFromSettings(values);
        });
      });
    });
    return child;
  }
}

class _RouteStub extends StatelessWidget {
  const _RouteStub(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}

/// Records what the page copies to the clipboard.
List<String> mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}
