import 'dart:io';
import 'dart:typed_data';

import 'package:apk_fly/channels/channel_models.dart';
import 'package:archive/archive.dart';

Future<ApkMetadata> parseApkMetadata(File file) async {
  if (!file.existsSync()) {
    throw StateError('APK 文件不存在: ${file.path}');
  }
  final archive = ZipDecoder().decodeBytes(
    await file.readAsBytes(),
    verify: false,
  );
  final manifest = archive.findFile('AndroidManifest.xml');
  if (manifest == null) {
    throw StateError('找不到 AndroidManifest.xml: ${file.path}');
  }
  final bytes = Uint8List.fromList(manifest.content as List<int>);
  final manifestReader = _BinaryManifest(bytes);
  final values = manifestReader.readManifestAttributes();
  final packageName = values['package'] ?? manifestReader.guessPackageName();
  if (packageName == null || packageName.isEmpty) {
    throw StateError('解析 APK 包名失败: ${file.path}');
  }
  return ApkMetadata(
    path: file.path,
    applicationId: packageName,
    versionCode: int.tryParse(values['versionCode'] ?? '') ?? 0,
    versionName: values['versionName'] ?? manifestReader.guessVersionName(),
  );
}

class _BinaryManifest {
  _BinaryManifest(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  final strings = <String>[];

  Map<String, String> readManifestAttributes() {
    var offset = 8;
    while (offset + 8 <= bytes.length) {
      final type = _u16(offset);
      final headerSize = _u16(offset + 2);
      final chunkSize = _u32(offset + 4);
      if (chunkSize <= 0) break;
      if (type == 0x0001) {
        _readStringPool(offset);
      } else if (type == 0x0102) {
        final attrs = _readStartElement(offset);
        if (attrs.containsKey('package')) return attrs;
      }
      offset += chunkSize;
      if (headerSize <= 0) break;
    }
    return const {};
  }

  String? guessPackageName() {
    final candidates = strings.where((value) {
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return false;
      }
      return RegExp(r'^[A-Za-z]\w*(\.[A-Za-z_]\w*)+$').hasMatch(value);
    }).toList();
    candidates.sort((a, b) => b.length.compareTo(a.length));
    return candidates.isEmpty ? null : candidates.first;
  }

  String guessVersionName() {
    for (final value in strings) {
      if (RegExp(r'^\d+(\.\d+){1,3}([\-+][A-Za-z0-9_.-]+)?$').hasMatch(value)) {
        return value;
      }
    }
    return '';
  }

  void _readStringPool(int offset) {
    final stringCount = _u32(offset + 8);
    final flags = _u32(offset + 16);
    final stringsStart = _u32(offset + 20);
    final isUtf8 = (flags & 0x00000100) != 0;
    strings.clear();
    for (var i = 0; i < stringCount; i++) {
      final strOffset = _u32(offset + 28 + i * 4);
      strings.add(
        isUtf8
            ? _readUtf8(offset + stringsStart + strOffset)
            : _readUtf16(offset + stringsStart + strOffset),
      );
    }
  }

  Map<String, String> _readStartElement(int offset) {
    final attrStart = _u16(offset + 24);
    final attrSize = _u16(offset + 26);
    final attrCount = _u16(offset + 28);
    final attrs = <String, String>{};
    var cursor = offset + attrStart;
    for (var i = 0; i < attrCount; i++) {
      final nameIdx = _u32(cursor + 4);
      final rawValueIdx = _u32(cursor + 8);
      final dataType = bytes[cursor + 15];
      final valueData = _u32(cursor + 16);
      final name = _string(nameIdx);
      if (name == 'package' || name == 'versionCode' || name == 'versionName') {
        attrs[name] = rawValueIdx != 0xffffffff
            ? _string(rawValueIdx)
            : _typedValue(dataType, valueData);
      }
      cursor += attrSize;
    }
    return attrs;
  }

  String _typedValue(int dataType, int value) {
    if (dataType == 0x03) return _string(value);
    if (dataType >= 0x10 && dataType <= 0x1f) return value.toString();
    return value.toString();
  }

  String _string(int index) {
    if (index < 0 || index >= strings.length) return '';
    return strings[index];
  }

  String _readUtf8(int offset) {
    final skip =
        _length8(offset).bytes +
        _length8(offset + _length8(offset).bytes).bytes;
    final start = offset + skip;
    var end = start;
    while (end < bytes.length && bytes[end] != 0) {
      end++;
    }
    return String.fromCharCodes(bytes.sublist(start, end));
  }

  String _readUtf16(int offset) {
    final len = _length16(offset);
    final start = offset + len.bytes;
    return String.fromCharCodes(
      List.generate(len.value, (i) => _u16(start + i * 2)),
    );
  }

  _Length _length8(int offset) {
    final first = bytes[offset];
    if ((first & 0x80) == 0) return _Length(first, 1);
    return _Length(((first & 0x7f) << 8) | bytes[offset + 1], 2);
  }

  _Length _length16(int offset) {
    final first = _u16(offset);
    if ((first & 0x8000) == 0) return _Length(first, 2);
    return _Length(((first & 0x7fff) << 16) | _u16(offset + 2), 4);
  }

  int _u16(int offset) => data.getUint16(offset, Endian.little);
  int _u32(int offset) => data.getUint32(offset, Endian.little);
}

class _Length {
  const _Length(this.value, this.bytes);

  final int value;
  final int bytes;
}
