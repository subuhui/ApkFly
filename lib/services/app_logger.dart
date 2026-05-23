import 'dart:async';
import 'dart:io';

import 'package:apk_fly/services/app_paths.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

class AppLogger {
  AppLogger._();

  static final instance = AppLogger._();

  final _paths = AppPaths();
  File? _file;
  final _format = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
  final _entries = StreamController<LogEntry>.broadcast();

  Stream<LogEntry> get entries => _entries.stream;

  Future<void> install() async {
    final dir = await _paths.logDir();
    await dir.create(recursive: true);
    final name = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _file = File(p.join(dir.path, '$name.log'));
    await info('App', 'Apk Fly 启动');
  }

  Future<void> info(String tag, String message) => _write('INFO', tag, message);

  Future<void> error(String tag, String message, [StackTrace? stackTrace]) {
    final text = stackTrace == null ? message : '$message\n$stackTrace';
    return _write('ERROR', tag, text);
  }

  Future<void> _write(String level, String tag, String message) async {
    final entry = LogEntry(DateTime.now(), level, tag, message);
    _entries.add(entry);
    final line = '${_format.format(entry.time)} [$level][$tag] $message\n';
    if (level == 'ERROR') {
      stderr.write(line);
    } else {
      stdout.write(line);
    }
    final file = _file;
    if (file != null) {
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    }
  }
}

class LogEntry {
  const LogEntry(this.time, this.level, this.tag, this.message);

  final DateTime time;
  final String level;
  final String tag;
  final String message;
}
