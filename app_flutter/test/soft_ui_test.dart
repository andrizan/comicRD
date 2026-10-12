import 'package:comicrd_flutter/state/api_state.dart';
import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:comicrd_flutter/widgets/soft_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_api.dart';

Widget _host(Widget child, {FakeComicRdApi? api}) {
  final app = MaterialApp(
    theme: ThemeData(extensions: const [ComicReaderColors.light]),
    home: FTheme(
      data: ComicReaderFTheme.light,
      child: FToaster(
        child: FTooltipGroup(
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  );
  if (api == null) return app;
  return ProviderScope(
    overrides: [comicRdApiProvider.overrideWithValue(api)],
    child: app,
  );
}

void main() {
  group('SoftButton', () {
    testWidgets('calls onPressed and tints the icon', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        _host(
          SoftButton(
            label: 'Favorite',
            icon: AppIcons.star,
            iconColor: ComicReaderColors.light.star,
            onPressed: () => pressed++,
          ),
        ),
      );

      await tester.tap(find.text('Favorite'));
      expect(pressed, 1);
      expect(
        tester.widget<Icon>(find.byIcon(AppIcons.star)).color,
        ComicReaderColors.light.star,
      );
    });

    testWidgets('a null onPressed disables the button', (tester) async {
      await tester.pumpWidget(
        _host(const SoftButton(label: 'Disabled', onPressed: null)),
      );

      await tester.tap(find.text('Disabled'), warnIfMissed: false);
      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.text('Disabled'),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, lessThan(1));
    });

    testWidgets('renders every variant and a 52 px pill', (tester) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              for (final variant in SoftButtonVariant.values)
                SoftButton(
                  label: variant.name,
                  variant: variant,
                  onPressed: () {},
                ),
              SoftButton(
                label: 'Big',
                height: 56,
                pill: true,
                icon: AppIcons.folderOpen,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      for (final variant in SoftButtonVariant.values) {
        expect(find.text(variant.name), findsOneWidget);
      }
      expect(tester.getSize(find.byType(SoftButton).last).height, 56);
    });
  });

  group('SoftIconButton', () {
    testWidgets('exposes the tooltip and reports toggled state', (
      tester,
    ) async {
      var pressed = 0;
      await tester.pumpWidget(
        _host(
          SoftIconButton(
            icon: AppIcons.star,
            tooltip: 'Remove Favorite',
            selected: true,
            round: true,
            onPressed: () => pressed++,
          ),
        ),
      );

      await tester.tap(find.byIcon(AppIcons.star));
      expect(pressed, 1);
      expect(
        tester.getSemantics(find.byIcon(AppIcons.star)),
        matchesSemantics(
          label: 'Remove Favorite',
          isButton: true,
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
          // The tooltip wrapper adds the long-press action.
          hasLongPressAction: true,
          hasFocusAction: true,
          isFocusable: true,
          isEnabled: true,
          hasEnabledState: true,
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
    });
  });

  group('SoftChip and SoftSegmented', () {
    testWidgets('chip shows its count and reports presses', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        _host(
          SoftChip(
            label: 'All',
            count: 128,
            selected: true,
            onPressed: () => pressed++,
          ),
        ),
      );

      expect(find.text('128'), findsOneWidget);
      await tester.tap(find.text('All'));
      expect(pressed, 1);
    });

    testWidgets('segmented control reports the tapped value', (tester) async {
      String? selected;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => SoftSegmented<String>(
              value: selected ?? 'all',
              onChanged: (value) => setState(() => selected = value),
              segments: const [
                SoftSegment(value: 'all', label: 'All', count: 30),
                SoftSegment(value: 'marked', label: 'Bookmarks', count: 3),
                SoftSegment(
                  value: 'grid',
                  icon: AppIcons.gridView,
                  tooltip: 'Grid',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('30'), findsOneWidget);
      await tester.tap(find.text('Bookmarks'));
      await tester.pump();
      expect(selected, 'marked');

      await tester.tap(find.byIcon(AppIcons.gridView));
      await tester.pump();
      expect(selected, 'grid');
      // Let the tooltip's hover timer expire before the tree is torn down.
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
    });
  });

  group('SoftSortMenu', () {
    testWidgets('opens the options and reports the chosen one', (tester) async {
      String? chosen;
      await tester.pumpWidget(
        _host(
          SoftSortMenu<String>(
            prefix: 'Sort',
            value: 'name',
            onChanged: (value) => chosen = value,
            options: const [
              SoftSortOption(value: 'name', label: 'Name A–Z'),
              SoftSortOption(value: 'date', label: 'Folder Date ↓'),
            ],
          ),
        ),
      );

      expect(find.textContaining('Name A–Z'), findsOneWidget);
      await tester.tap(find.byIcon(AppIcons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Folder Date ↓'));
      await tester.pumpAndSettle();

      expect(chosen, 'date');
    });
  });

  group('SoftSwitch and SoftSlider', () {
    testWidgets('switch toggles and respects null onChanged', (tester) async {
      bool? received;
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              SoftSwitch(
                value: false,
                semanticLabel: 'Unlimited Scroll',
                onChanged: (value) => received = value,
              ),
              const SoftSwitch(
                value: true,
                semanticLabel: 'Locked',
                onChanged: null,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.byType(SoftSwitch).first);
      expect(received, isTrue);

      await tester.tap(find.byType(SoftSwitch).last, warnIfMissed: false);
      expect(received, isTrue);
    });

    testWidgets('slider reports a stepped value when dragged', (tester) async {
      double? received;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 300,
            child: SoftSlider(
              value: 0,
              min: 0,
              max: 80,
              divisions: 16,
              semanticLabel: 'Page Gap',
              onChanged: (value) => received = value,
            ),
          ),
        ),
      );

      await tester.drag(find.byType(Slider), const Offset(120, 0));
      await tester.pump();

      expect(received, isNotNull);
      expect(received! % 5, 0);
      expect(received, greaterThan(0));
    });
  });

  group('SoftSearchField', () {
    testWidgets('forwards typed text and clears it', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final changes = <String>[];
      await tester.pumpWidget(
        _host(
          SoftSearchField(
            controller: controller,
            hint: 'Search…',
            onChanged: changes.add,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'senja');
      await tester.pump();
      expect(changes, ['senja']);
      expect(find.byIcon(AppIcons.close), findsOneWidget);

      await tester.tap(find.byIcon(AppIcons.close));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(changes.last, '');
      expect(find.byIcon(AppIcons.close), findsNothing);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
    });
  });

  group('SoftProgressBar and SoftBadge', () {
    testWidgets('progress clamps to the 0..1 range', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 200,
            child: Column(
              children: [
                SoftProgressBar(value: 1.8, semanticLabel: 'Progress'),
                SoftProgressBar(value: -1),
              ],
            ),
          ),
        ),
      );

      final boxes = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .toList();
      expect(boxes.first.widthFactor, 1);
      expect(boxes.last.widthFactor, 0);
    });

    testWidgets('badge renders its label and icon', (tester) async {
      await tester.pumpWidget(
        _host(
          const SoftBadge(
            label: 'Finished',
            tone: SoftBadgeTone.success,
            icon: AppIcons.check,
          ),
        ),
      );

      expect(find.text('Finished'), findsOneWidget);
      expect(find.byIcon(AppIcons.check), findsOneWidget);
    });
  });

  group('HoverCard and CoverThumbnail', () {
    testWidgets('card opens on tap', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          HoverCard(
            onTap: () => opened++,
            semanticLabel: 'Penjaga Senja',
            child: const SizedBox(width: 200, height: 80),
          ),
        ),
      );

      await tester.tap(find.byType(HoverCard));
      expect(opened, 1);
    });

    testWidgets('thumbnail falls back to the library icon on bad bytes', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const CoverThumbnail(
            sourcePath: fakeFeaturedPath,
            width: 80,
            height: 120,
          ),
          api: FakeComicRdApi(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(AppIcons.library), findsOneWidget);
    });
  });

  group('PageHeading', () {
    testWidgets('subtitle inherits the ambient font family', (tester) async {
      await tester.pumpWidget(
        _host(
          const DefaultTextStyle(
            style: TextStyle(fontFamily: 'Plus Jakarta Sans'),
            child: PageHeading(
              title: 'Library',
              subtitle: Text('12 Titles Saved'),
            ),
          ),
        ),
      );

      final subtitle = tester.widget<RichText>(
        find
            .descendant(
              of: find.byType(PageHeading),
              matching: find.byType(RichText),
            )
            .last,
      );
      expect(subtitle.text.style?.fontFamily, 'Plus Jakarta Sans');
      expect(find.text('Library'), findsOneWidget);
    });
  });
}
