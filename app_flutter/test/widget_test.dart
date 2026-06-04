import 'package:comicrd_flutter/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders ComicRD shell with library tabs', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ComicRdApp()));
    await tester.pumpAndSettle();

    expect(find.text('ComicRD'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Bookmarks'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('toggles locale from English to Indonesian', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ComicRdApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.translate_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Riwayat'), findsOneWidget);
    expect(find.text('Pustaka'), findsOneWidget);
    expect(find.text('Bookmark'), findsOneWidget);
  });
}
