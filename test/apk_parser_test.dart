import 'dart:io';

import 'package:apk_fly/utils/apk_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses sample APK metadata', () async {
    final sample = File(
      '/Users/xxz/StudioProjects/XiaoZhuan/sample/sample-v1.1.2-mi.apk',
    );
    if (!sample.existsSync()) {
      markTestSkipped('sample APK is not available on this machine');
      return;
    }

    final info = await parseApkMetadata(sample);

    expect(info.applicationId, isNotEmpty);
    expect(info.versionName, isNotEmpty);
  });
}
