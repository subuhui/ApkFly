import 'package:apk_fly/app/apk_fly_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('renders Apk Fly shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ApkFlyApp()));
    await tester.pump();
    expect(find.text('Apk Fly'), findsWidgets);
  });
}
