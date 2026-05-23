import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class AppPaths {
  Future<Directory> rootDir() async {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      throw StateError('无法定位用户目录');
    }
    final root = Directory(p.join(home, '.apk_fly'));
    return kDebugMode ? Directory(p.join(root.path, 'debug')) : root;
  }

  Future<Directory> appsDir() async =>
      Directory(p.join((await rootDir()).path, 'apps'));

  Future<Directory> logDir() async =>
      Directory(p.join((await rootDir()).path, 'logs'));
}
