import 'package:apk_fly/app/apk_fly_app.dart';
import 'package:apk_fly/config/app_profile.dart';
import 'package:apk_fly/features/upload/upload_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('renders Apk Fly shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ApkFlyApp()));
    await tester.pump();
    expect(find.text('Apk Fly'), findsWidgets);
  });

  testWidgets('shows scheduled release controls on upload page', (
    tester,
  ) async {
    const profile = AppProfile(
      name: 'Demo',
      applicationId: 'com.demo.app',
      createTime: 0,
      stores: [StoreConfig(name: '华为', enable: true, params: [])],
      usesChannelPackages: false,
      preferences: ProfilePreferences(),
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: UploadPage(config: profile)),
      ),
    );
    await tester.pump();

    expect(find.text('立即发布'), findsOneWidget);
    expect(find.text('定时发布'), findsOneWidget);
    expect(find.text('审核通过后立即发布'), findsOneWidget);
  });
}
