import 'package:comicrd_flutter/widgets/back_to_top_button.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses a larger desktop click target', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        home: Center(
          child: BackToTopButton(
            visible: true,
            tooltip: 'Back to top',
            onPressed: () {},
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(IconButton));

    expect(size.width, greaterThanOrEqualTo(52));
    expect(size.height, greaterThanOrEqualTo(52));
  });
}
