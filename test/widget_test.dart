import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/main.dart';

void main() {
  testWidgets('SisoApp renders initial MapScreen skeleton without errors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SisoApp(),
      ),
    );

    expect(find.text('SISO — Đại Chiến Bình Thạnh'), findsOneWidget);
    expect(
      find.text('BỘ ĐẾM SONG SONG: % ĐẤT CHIẾM ĐÓNG & % KM CỐNG HIẾN'),
      findsOneWidget,
    );
  });
}
