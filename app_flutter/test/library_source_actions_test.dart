import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/state/library_source_actions.dart';
import 'package:comicrd_flutter/state/library_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_api.dart';

void main() {
  Future<WidgetRef> pumpRef(WidgetTester tester, FakeComicRdApi api) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicRdApiProvider.overrideWithValue(api)],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('applyLibrarySource stores the trimmed path and registers it', (
    tester,
  ) async {
    final api = FakeComicRdApi();
    final ref = await pumpRef(tester, api);

    await applyLibrarySource(ref, '  /mnt/komik  ');

    expect(api.savedSettings['library_source_input'], '"/mnt/komik"');
    expect(api.addedLibraries, ['/mnt/komik']);
  });

  testWidgets('an empty path only clears the stored input', (tester) async {
    final api = FakeComicRdApi();
    final ref = await pumpRef(tester, api);

    await applyLibrarySource(ref, '   ');

    expect(api.savedSettings['library_source_input'], '""');
    expect(api.addedLibraries, isEmpty);
  });

  testWidgets('invalidateLibraryData refetches the library listing', (
    tester,
  ) async {
    final api = FakeComicRdApi();
    final ref = await pumpRef(tester, api);

    await ref.read(rawLibraryComicsProvider.future);
    expect(api.listComicsCalls, 1);

    invalidateLibraryData(ref);
    await ref.read(rawLibraryComicsProvider.future);
    expect(api.listComicsCalls, 2);
  });
}
