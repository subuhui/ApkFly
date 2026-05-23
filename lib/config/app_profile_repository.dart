import 'dart:io';

import 'package:apk_fly/config/app_profile.dart';
import 'package:apk_fly/services/app_paths.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

class AppProfileRepository {
  AppProfileRepository(this.paths);

  final AppPaths paths;

  Future<List<AppProfile>> list() async {
    final dir = await paths.appsDir();
    if (!dir.existsSync()) return [];
    final configs = <AppProfile>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.yaml')) continue;
      final config = await _read(entity);
      if (config != null) configs.add(config);
    }
    configs.sort((a, b) => a.createTime.compareTo(b.createTime));
    return configs;
  }

  Future<AppProfile?> get(String applicationId) async {
    final dir = await paths.appsDir();
    final file = File(p.join(dir.path, '$applicationId.yaml'));
    if (!file.existsSync()) return null;
    return _read(file);
  }

  Future<void> save(AppProfile config) async {
    final dir = await paths.appsDir();
    await dir.create(recursive: true);
    final editor = YamlEditor('{}');
    final data = config.toMap();
    for (final entry in data.entries) {
      editor.update([entry.key], entry.value);
    }
    await File(
      p.join(dir.path, '${config.applicationId}.yaml'),
    ).writeAsString(editor.toString());
  }

  Future<void> remove(String applicationId) async {
    final dir = await paths.appsDir();
    final file = File(p.join(dir.path, '$applicationId.yaml'));
    if (!file.existsSync()) return;
    final bak = File('${file.path}.bak');
    if (bak.existsSync()) await bak.delete();
    await file.rename(bak.path);
  }

  Future<AppProfile?> _read(File file) async {
    try {
      final yaml = loadYaml(await file.readAsString());
      if (yaml is! YamlMap) return null;
      return AppProfile.fromMap(yaml.cast<Object?, Object?>());
    } catch (_) {
      return null;
    }
  }
}
