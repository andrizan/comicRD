import 'package:comicrd_flutter/utils/forui_theme.dart';
import 'package:comicrd_flutter/widgets/back_to_top_button.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses a larger desktop click target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: ComicReaderFTheme.light,
          child: FTooltipGroup(
            child: Scaffold(
              body: Center(
                child: BackToTopButton(
                  visible: true,
                  tooltip: 'Back to top',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(FButton));

    expect(size.width, greaterThanOrEqualTo(52));
    expect(size.height, greaterThanOrEqualTo(52));
  });
}
