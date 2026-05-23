import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

Future<String> fileMd5(File file) async {
  final digest = await md5.bind(file.openRead()).first;
  return digest.toString();
}

Future<String> fileSha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

Future<List<File>> listApks(File dir) async {
  final Directory root =
      dir.existsSync() && dir.statSync().type == FileSystemEntityType.directory
      ? Directory(dir.path)
      : dir.parent;
  final files = <File>[];
  if (!root.existsSync()) return files;
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final rel = p.relative(entity.path, from: root.path);
    if (p.split(rel).length > 3) {
      continue;
    }
    if (entity.path.toLowerCase().endsWith('.apk')) {
      files.add(entity);
    }
  }
  files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  return files.take(9).toList();
}

String prettyBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String jsonString(Object? value) => jsonEncode(value);
