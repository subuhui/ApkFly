import 'dart:async';

import 'package:apk_fly/app/apk_fly_app.dart';
import 'package:apk_fly/services/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  await AppLogger.instance.install();

  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        AppLogger.instance.error(
          'Flutter',
          details.exceptionAsString(),
          details.stack,
        );
      };
      await windowManager.ensureInitialized();
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          title: 'Apk Fly',
          size: Size(1280, 960),
          minimumSize: Size(980, 700),
          center: true,
        ),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
      runApp(const ProviderScope(child: ApkFlyApp()));
    },
    (error, stack) =>
        AppLogger.instance.error('Uncaught', error.toString(), stack),
  );
}
