import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apk_fly/channels/channel_models.dart';
import 'package:apk_fly/channels/http_channel_client.dart';
import 'package:apk_fly/utils/crypto_util.dart';
import 'package:apk_fly/utils/file_util.dart';
import 'package:dio/dio.dart' hide ProgressCallback;
import 'package:intl/intl.dart';

abstract class BaseStoreChannel extends StoreChannel {
  BaseStoreChannel();

  final http = HttpChannelClient();
  Map<String, String?> values = const {};

  @override
  void init(Map<String, String?> params) => values = params;

  String value(String key) => values[key]?.trim() ?? '';

  StoreReviewSnapshot parseReviewSnapshot(Map<String, dynamic> data) {
    final text = data.toString();
    final rejected =
        text.contains('拒') || text.toLowerCase().contains('reject');
    final review = text.contains('审核') || text.toLowerCase().contains('review');
    final online = text.contains('上线') ||
        text.toLowerCase().contains('online') ||
        text.toLowerCase().contains('release');
    return StoreReviewSnapshot(
      reviewState: rejected
          ? StoreReviewState.rejected
          : review
              ? StoreReviewState.underReview
              : online
                  ? StoreReviewState.online
                  : StoreReviewState.unknown,
      enableSubmit: !review,
      lastVersion: _looseVersion(data),
    );
  }

  StoreVersion? _looseVersion(Object? value) {
    if (value is Map) {
      int? code;
      String? name;
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (key.contains('versioncode') || key == 'version_code') {
          code = int.tryParse(entry.value.toString());
        }
        if (key.contains('versionname') || key == 'version_name') {
          name = entry.value.toString();
        }
        final nested = _looseVersion(entry.value);
        code ??= nested?.code;
        name ??= nested?.name;
      }
      if (code != null || name != null) {
        return StoreVersion(code ?? 0, name ?? '');
      }
    }
    if (value is List) {
      for (final item in value) {
        final nested = _looseVersion(item);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  String formatOnlineTime(int millis) {
    if (millis <= 0) return '';
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(_chinaTime(millis));
  }

  String formatReleaseTime(int millis) {
    if (millis <= 0) return '';
    return "${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(_chinaTime(millis))}+0800";
  }

  DateTime _chinaTime(int millis) => DateTime.fromMillisecondsSinceEpoch(
        millis,
        isUtc: true,
      ).add(const Duration(hours: 8));

  void checkResultCode(
    Map<String, dynamic> result,
    String action, {
    String codeKey = 'code',
    num successCode = 0,
    String messageKey = 'msg',
  }) {
    checkApiSuccess(
      result[codeKey] as num?,
      successCode,
      action,
      result[messageKey]?.toString() ?? '',
    );
  }

  String requiredText(
    Map<String, dynamic> map,
    List<String> keys,
    String label,
  ) {
    final value = firstNonBlank(keys.map((key) => map[key]));
    if (value == null) {
      throw StateError('$storeName 缺少必要字段: $label, response: $map');
    }
    return value;
  }

  String? firstNonBlank(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    return null;
  }

  String? findNestedTextByKeys(Object? value, Iterable<String> keys) {
    final lowered = {for (final key in keys) key.toLowerCase()};
    return _findNestedTextByKeys(value, lowered);
  }

  String? fallbackUpdateDescFromDetail(Object? value) {
    return findNestedTextByKeys(value, const [
      'updateDesc',
      'update_desc',
      'apkUpdateDesc',
      'newFeature',
      'newFeatures',
      'versionDesc',
      'version_desc',
      'versionContent',
      'version_content',
      'updateContent',
      'update_content',
    ]);
  }

  ReleasePlan resolveReleasePlanWithFallback(
    ReleasePlan versionParams,
    StoreReviewSnapshot reviewSnapshot,
  ) {
    if (versionParams.updateDesc.trim().isNotEmpty) {
      return versionParams;
    }
    final fallback = reviewSnapshot.fallbackUpdateDesc?.trim();
    if (fallback == null || fallback.isEmpty) {
      throw StateError('$storeName 应用详情中未找到更新说明，请手动填写');
    }
    return versionParams.copyWith(updateDesc: fallback);
  }

  String? _findNestedTextByKeys(Object? value, Set<String> keys) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (keys.contains(key)) {
          final text = entry.value?.toString().trim();
          if (text != null && text.isNotEmpty && text != 'null') {
            return text;
          }
        }
      }
      for (final entry in value.entries) {
        final nested = _findNestedTextByKeys(entry.value, keys);
        if (nested != null) {
          return nested;
        }
      }
    }
    if (value is List) {
      for (final item in value) {
        final nested = _findNestedTextByKeys(item, keys);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }
}

class HuaweiStoreChannel extends BaseStoreChannel {
  @override
  String get storeName => '华为';

  @override
  String get apkFileMarker => 'HUAWEI';

  @override
  List<StoreCredentialDefinition> get credentialDefinitions => const [
        StoreCredentialDefinition('client_id', desc: '客户端ID'),
        StoreCredentialDefinition('client_secret', desc: '密钥'),
      ];

  @override
  bool get allowsEmptyUpdateDesc => true;

  Future<String> _token() async {
    final result = await http.postJson(
      'https://connect-api.cloud.huawei.com/api/oauth2/v1/token',
      data: {
        'client_id': value('client_id'),
        'client_secret': value('client_secret'),
        'grant_type': 'client_credentials',
      },
    );
    final token = result['access_token'] ??
        result['token'] ??
        result['data']?['access_token'];
    if (token == null ||
        token.toString().isEmpty ||
        token.toString() == 'null') {
      throw StateError('获取华为 token 失败: $result');
    }
    return token.toString();
  }

  Future<String> _appId(String packageName, String token) async {
    final result = await http.getJson(
      'https://connect-api.cloud.huawei.com/api/publish/v2/appid-list',
      query: {'packageName': packageName},
      headers: {
        'client_id': value('client_id'),
        'Authorization': 'Bearer $token',
      },
    );
    final list = result['appids'] ?? result['appIdList'] ?? result['data'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is Map) {
        final appId = first['value'] ?? first['appId'] ?? first['id'];
        if (appId != null &&
            appId.toString().isNotEmpty &&
            appId.toString() != 'null') {
          return appId.toString();
        }
      } else if (first.toString().isNotEmpty && first.toString() != 'null') {
        return first.toString();
      }
    }
    final appId = result['appId'] ?? result['id'] ?? result['value'];
    if (appId == null ||
        appId.toString().isEmpty ||
        appId.toString() == 'null') {
      throw StateError('获取华为 AppId 失败: $result');
    }
    return appId.toString();
  }

  void _checkHuaweiResult(Map<String, dynamic> result, String action) {
    final ret = result['ret'];
    if (ret is Map) {
      final retMap = ret.cast<String, dynamic>();
      checkResultCode(retMap, action, messageKey: 'msg');
    }
  }

  @override
  Future<StoreReviewSnapshot> fetchReviewSnapshot(String applicationId) async {
    final token = await _token();
    final appId = await _appId(applicationId, token);
    final result = await http.getJson(
      'https://connect-api.cloud.huawei.com/api/publish/v2/app-info',
      query: {'appId': appId},
      headers: {
        'client_id': value('client_id'),
        'Authorization': 'Bearer $token',
      },
    );
    _checkHuaweiResult(result, '获取华为 App信息');
    return _parseHuaweiMarketInfo(
      result,
      fallbackUpdateDesc: await _fetchHuaweiFallbackUpdateDesc(
        token,
        appId,
        result,
      ),
    );
  }

  Future<String?> _fetchHuaweiFallbackUpdateDesc(
    String token,
    String appId,
    Map<String, dynamic> appInfo,
  ) async {
    final inline = fallbackUpdateDescFromDetail(appInfo);
    if (inline != null && inline.isNotEmpty) {
      return inline;
    }
    try {
      final result = await http.getJson(
        'https://connect-api.cloud.huawei.com/api/publish/v2/app-language-info',
        query: {'appId': appId},
        headers: {
          'client_id': value('client_id'),
          'Authorization': 'Bearer $token',
        },
      );
      _checkHuaweiResult(result, '获取华为语言信息');
      return fallbackUpdateDescFromDetail(result);
    } catch (_) {
      return null;
    }
  }

  StoreReviewSnapshot _parseHuaweiMarketInfo(
    Map<String, dynamic> result, {
    String? fallbackUpdateDesc,
  }) {
    final rawInfo = result['appInfo'] ??
        result['data']?['appInfo'] ??
        result['data'] ??
        result;
    if (rawInfo is! Map) {
      return parseReviewSnapshot(result);
    }
    final info = rawInfo.cast<String, dynamic>();
    final releaseState = int.tryParse(info['releaseState']?.toString() ?? '');
    final reviewState = switch (releaseState) {
      0 => StoreReviewState.online,
      4 || 5 => StoreReviewState.underReview,
      1 || 8 || 9 => StoreReviewState.rejected,
      _ => StoreReviewState.unknown,
    };
    final versionCode = int.tryParse(info['versionCode']?.toString() ?? '');
    final versionName = firstNonBlank([
      info['versionNumber'],
      info['onShelfVersionNumber'],
      info['versionName'],
    ]);
    return StoreReviewSnapshot(
      reviewState: reviewState,
      enableSubmit: releaseState != 4 && releaseState != 5,
      lastVersion: versionCode == null && versionName == null
          ? null
          : StoreVersion(versionCode ?? 0, versionName ?? ''),
      fallbackUpdateDesc: fallbackUpdateDesc,
    );
  }

  @override
  ReleasePlan resolveReleasePlan(
    ReleasePlan versionParams,
    StoreReviewSnapshot reviewSnapshot,
  ) =>
      resolveReleasePlanWithFallback(versionParams, reviewSnapshot);

  @override
  Future<void> upload(
    File file,
    String applicationId,
    ReleasePlan versionParams,
    ProgressCallback progress,
  ) async {
    final token = await _token();
    final appId = await _appId(applicationId, token);
    final baselineInfo = await http.getJson(
      'https://connect-api.cloud.huawei.com/api/publish/v2/app-info',
      query: {'appId': appId},
      headers: {
        'client_id': value('client_id'),
        'Authorization': 'Bearer $token',
      },
    );
    _checkHuaweiResult(baselineInfo, '获取华为 App信息');
    final baselineVersion = _visibleHuaweiVersion(baselineInfo);
    final upload = await http.getJson(
      'https://connect-api.cloud.huawei.com/api/publish/v2/upload-url/for-obs',
      query: {
        'appId': appId,
        'fileName': file.uri.pathSegments.last,
        'contentLength': await file.length(),
      },
      headers: {
        'client_id': value('client_id'),
        'Authorization': 'Bearer $token',
      },
    );
    _checkHuaweiResult(upload, '获取华为上传地址');
    final uploadData = upload['urlInfo'] ??
        upload['uploadUrl'] ??
        upload['url'] ??
        upload['data'];
    if (uploadData is! Map) {
      throw StateError('获取华为上传地址失败: $upload');
    }
    final url = requiredText(
        uploadData.cast<String, dynamic>(),
        const [
          'url',
        ],
        'upload url');
    final objectId = requiredText(
        uploadData.cast<String, dynamic>(),
        const [
          'objectId',
        ],
        'objectId');
    final headers = uploadData['headers'] is Map
        ? (uploadData['headers'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    await http.putFile(url, file, headers: headers, progress: progress);
    progress(100);
    final bind = await http.putJson(
      'https://connect-api.cloud.huawei.com/api/publish/v2/app-file-info',
      query: {'appId': appId},
      headers: {
        'client_id': value('client_id'),
        'Authorization': 'Bearer $token',
      },
      data: {
        'fileType': 5,
        'files': [
          {'fileName': file.uri.pathSegments.last, 'fileDestUrl': objectId},
        ],
      },
    );
    _checkHuaweiResult(bind, '绑定华为Apk文件');
    final pkgVersions = bind['pkgVersion'];
    final pkgId = pkgVersions is List && pkgVersions.isNotEmpty
        ? pkgVersions.first.toString()
        : null;
    if (pkgId == null || pkgId.isEmpty || pkgId == 'null') {
      throw StateError('华为绑定Apk后缺少 pkgId: $bind');
    }
    await _waitHuaweiPackageReady(token, appId, pkgId);
    await _waitHuaweiSubmitWindow(token, appId, baselineVersion);
    final updateDesc = await http.putJson(
      'https://connect-api.cloud.huawei.com/api/publish/v2/app-language-info',
      query: {'appId': appId},
      headers: {
        'client_id': value('client_id'),
        'Authorization': 'Bearer $token',
      },
      data: {'lang': 'zh-CN', 'newFeatures': versionParams.updateDesc},
    );
    _checkHuaweiResult(updateDesc, '更新华为版本说明');
    final submit = await http.postJson(
      'https://connect-api.cloud.huawei.com/api/publish/v2/app-submit',
      query: {
        'appId': appId,
        if (versionParams.onlineTime > 0)
          'releaseTime': formatReleaseTime(versionParams.onlineTime),
      },
      headers: {
        'client_id': value('client_id'),
        'Authorization': 'Bearer $token',
      },
    );
    _checkHuaweiResult(submit, '提交华为审核');
  }

  Future<void> _waitHuaweiPackageReady(
    String token,
    String appId,
    String pkgId,
  ) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < const Duration(minutes: 3)) {
      await Future<void>.delayed(const Duration(seconds: 10));
      final result = await http.getJson(
        'https://connect-api.cloud.huawei.com/api/publish/v2/package/compile/status',
        query: {'appId': appId, 'pkgIds': pkgId},
        headers: {
          'client_id': value('client_id'),
          'Authorization': 'Bearer $token',
        },
      );
      _checkHuaweiResult(result, '查询华为Apk编译状态');
      final stateList = result['pkgStateList'];
      if (stateList is! List || stateList.isEmpty) {
        continue;
      }
      final first = stateList.first;
      if (first is! Map) continue;
      final successStatus = int.tryParse(
        first['successStatus']?.toString() ?? '',
      );
      switch (successStatus) {
        case 0:
          return;
        case 1:
          continue;
        case 2:
          throw StateError(
            '华为Apk编译失败: '
            'successStatus=2, '
            'aabCompileStatus=${first['aabCompileStatus']}, '
            'failReason=${first['failReason']}, '
            'response: $first',
          );
        default:
          throw StateError('未知华为Apk编译状态: $first');
      }
    }
    throw TimeoutException('等待华为Apk编译完成超时');
  }

  Future<void> _waitHuaweiSubmitWindow(
    String token,
    String appId,
    StoreVersion? baselineVersion,
  ) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 15));
      final result = await http.getJson(
        'https://connect-api.cloud.huawei.com/api/publish/v2/app-info',
        query: {'appId': appId},
        headers: {
          'client_id': value('client_id'),
          'Authorization': 'Bearer $token',
        },
      );
      _checkHuaweiResult(result, '获取华为 App信息');
      if (_isHuaweiDraftVersionVisible(result, baselineVersion)) {
        return;
      }
    }
  }

  bool _isHuaweiDraftVersionVisible(
    Map<String, dynamic> result,
    StoreVersion? baselineVersion,
  ) {
    final visibleVersion = _visibleHuaweiVersion(result);
    if (visibleVersion == null) {
      return false;
    }
    if (baselineVersion == null) {
      return true;
    }
    return visibleVersion.code != baselineVersion.code ||
        visibleVersion.name != baselineVersion.name;
  }

  StoreVersion? _visibleHuaweiVersion(Map<String, dynamic> result) {
    final rawInfo = result['appInfo'] ??
        result['data']?['appInfo'] ??
        result['data'] ??
        result;
    if (rawInfo is! Map) return null;
    final info = rawInfo.cast<String, dynamic>();
    final visibleVersionCode = int.tryParse(
      info['versionCode']?.toString() ?? '',
    );
    final visibleVersionName = firstNonBlank([
      info['versionNumber'],
      info['versionName'],
    ]);
    if (visibleVersionCode == null && visibleVersionName == null) {
      return null;
    }
    return StoreVersion(visibleVersionCode ?? 0, visibleVersionName ?? '');
  }
}

class XiaomiStoreChannel extends BaseStoreChannel {
  @override
  String get storeName => '小米';

  @override
  String get apkFileMarker => 'MI';

  @override
  List<StoreCredentialDefinition> get credentialDefinitions => const [
        StoreCredentialDefinition('account', desc: '账号(邮箱)'),
        StoreCredentialDefinition(
          'publicKey',
          desc: '公钥',
          textFileExtension: 'cer',
        ),
        StoreCredentialDefinition('privateKey', desc: '私钥'),
        StoreCredentialDefinition('iconPath',
            desc: '应用图标文件路径', pickFilePath: true),
      ];

  @override
  bool get allowsEmptyUpdateDesc => true;

  Map<String, dynamic> _sig(Map<String, dynamic> requestData, [File? file]) {
    final sigs = [
      {'name': 'RequestData', 'hash': md5Hex(jsonEncode(requestData))},
    ];
    return {'password': value('privateKey'), 'sig': sigs};
  }

  String _encryptedSig(Map<String, dynamic> sig) =>
      rsaEncryptX509ToHex(jsonEncode(sig), value('publicKey'));

  @override
  Future<StoreReviewSnapshot> fetchReviewSnapshot(String applicationId) async {
    final result = await _queryAppInfo(applicationId);
    return _parseXiaomiMarketInfo(result);
  }

  Future<Map<String, dynamic>> _queryAppInfo(String applicationId) {
    final requestData = {
      'userName': value('account'),
      'packageName': applicationId,
    };
    return http.postJson(
      'https://api.developer.xiaomi.com/devupload/dev/query',
      data: FormData.fromMap({
        'RequestData': jsonEncode(requestData),
        'SIG': _encryptedSig(_sig(requestData)),
      }),
    );
  }

  StoreReviewSnapshot _parseXiaomiMarketInfo(Map<String, dynamic> result) {
    checkApiSuccess(
      result['result'] as num?,
      0,
      '获取小米App信息',
      result['message']?.toString() ?? '',
    );
    final packageInfo = result['packageInfo'];
    final updateVersion = result['updateVersion'] == true;
    if (packageInfo is! Map) {
      return const StoreReviewSnapshot(reviewState: StoreReviewState.unknown);
    }
    final info = packageInfo.cast<String, dynamic>();
    return StoreReviewSnapshot(
      reviewState: updateVersion
          ? StoreReviewState.online
          : StoreReviewState.underReview,
      enableSubmit: updateVersion,
      lastVersion: updateVersion
          ? StoreVersion(
              int.tryParse(info['versionCode']?.toString() ?? '') ?? 0,
              info['versionName']?.toString() ?? '',
            )
          : null,
      fallbackUpdateDesc: fallbackUpdateDescFromDetail(result),
    );
  }

  @override
  ReleasePlan resolveReleasePlan(
    ReleasePlan versionParams,
    StoreReviewSnapshot reviewSnapshot,
  ) =>
      resolveReleasePlanWithFallback(versionParams, reviewSnapshot);

  @override
  Future<void> upload(
    File file,
    String applicationId,
    ReleasePlan versionParams,
    ProgressCallback progress,
  ) async {
    final appInfoResult = await _queryAppInfo(applicationId);
    checkApiSuccess(
      appInfoResult['result'] as num?,
      0,
      '获取小米App信息',
      appInfoResult['message']?.toString() ?? '',
    );
    final packageInfo = appInfoResult['packageInfo'];
    if (packageInfo is! Map) {
      throw StateError('获取小米App信息失败: $appInfoResult');
    }
    if (appInfoResult['updateVersion'] != true) {
      throw StateError('小米当前状态不允许更新版本，请先检查商店后台状态');
    }
    final iconFile = File(value('iconPath'));
    if (!iconFile.existsSync()) {
      throw StateError('小米 iconPath 文件不存在: ${iconFile.path}');
    }
    final requestData = {
      'userName': value('account'),
      'synchroType': 1,
      'appInfo': {
        'appName': packageInfo['appName']?.toString() ?? '',
        'packageName': applicationId,
        'updateDesc': versionParams.updateDesc,
        if (versionParams.onlineTime > 0)
          'onlineTime': versionParams.onlineTime,
      },
    };
    final sig = _sig(requestData, file);
    (sig['sig'] as List).add({'name': 'apk', 'hash': await fileMd5(file)});
    (sig['sig'] as List).add({'name': 'icon', 'hash': await fileMd5(iconFile)});
    final result = await http.postMultipart(
      'https://api.developer.xiaomi.com/devupload/dev/push',
      file: file,
      fileField: 'apk',
      extraFiles: {'icon': iconFile},
      fields: {
        'RequestData': jsonEncode(requestData),
        'SIG': _encryptedSig(sig),
      },
      progress: progress,
    );
    checkApiSuccess(
      result['result'] as num?,
      0,
      '上传小米APK',
      result['message']?.toString() ?? '',
    );
  }
}

class OppoStoreChannel extends BaseStoreChannel {
  @override
  String get storeName => 'OPPO';

  @override
  String get apkFileMarker => 'OPPO';

  @override
  List<StoreCredentialDefinition> get credentialDefinitions => const [
        StoreCredentialDefinition('client_id'),
        StoreCredentialDefinition('client_secret'),
      ];

  @override
  bool get allowsEmptyUpdateDesc => true;

  Future<String> _token() async {
    final result = await http.getJson(
      'https://oop-openapi-cn.heytapmobi.com/developer/v1/token',
      query: {
        'client_id': value('client_id'),
        'client_secret': value('client_secret'),
      },
    );
    checkApiSuccess(
      result['errno'] as num?,
      0,
      '获取OPPO token',
      result['data']?['message']?.toString() ?? '',
    );
    return result['data']['access_token'].toString();
  }

  Map<String, String> _signed(Map<String, String> params, String token) {
    final signed = {
      ...params,
      'access_token': token,
      'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
    };
    final source = signed.keys.toList()..sort();
    final signText = source.map((k) => '$k=${signed[k]}').join('&');
    signed['api_sign'] = hmacSha256Hex(signText, value('client_secret'));
    return signed;
  }

  @override
  Future<StoreReviewSnapshot> fetchReviewSnapshot(String applicationId) async {
    final token = await _token();
    final result = await _getOppoAppInfo(applicationId, token);
    return _parseOppoMarketInfo(result);
  }

  Future<Map<String, dynamic>> _getOppoAppInfo(
    String applicationId,
    String token,
  ) {
    return http.getJson(
      'https://oop-openapi-cn.heytapmobi.com/resource/v1/app/info',
      query: _signed({'pkg_name': applicationId}, token),
    );
  }

  StoreReviewSnapshot _parseOppoMarketInfo(Map<String, dynamic> result) {
    checkApiSuccess(
      result['errno'] as num?,
      0,
      '获取OPPO App信息',
      result['data']?['message']?.toString() ?? '',
    );
    final data = result['data'];
    if (data is! Map) {
      return const StoreReviewSnapshot(reviewState: StoreReviewState.unknown);
    }
    final info = data.cast<String, dynamic>();
    final auditStatus = int.tryParse(info['audit_status']?.toString() ?? '');
    final reviewState = switch (auditStatus) {
      111 => StoreReviewState.online,
      444 => StoreReviewState.rejected,
      _ => StoreReviewState.underReview,
    };
    return StoreReviewSnapshot(
      reviewState: reviewState,
      enableSubmit: reviewState != StoreReviewState.underReview,
      lastVersion: StoreVersion(
        int.tryParse(info['version_code']?.toString() ?? '') ?? 0,
        info['version_name']?.toString() ?? '',
      ),
      fallbackUpdateDesc: fallbackUpdateDescFromDetail(info),
    );
  }

  @override
  ReleasePlan resolveReleasePlan(
    ReleasePlan versionParams,
    StoreReviewSnapshot reviewSnapshot,
  ) =>
      resolveReleasePlanWithFallback(versionParams, reviewSnapshot);

  @override
  Future<void> upload(
    File file,
    String applicationId,
    ReleasePlan versionParams,
    ProgressCallback progress,
  ) async {
    final token = await _token();
    final appInfoResult = await _getOppoAppInfo(applicationId, token);
    checkApiSuccess(
      appInfoResult['errno'] as num?,
      0,
      '获取OPPO App信息',
      appInfoResult['data']?['message']?.toString() ?? '',
    );
    final appInfo = appInfoResult['data'];
    if (appInfo is! Map) {
      throw StateError('获取OPPO App信息失败: $appInfoResult');
    }
    final detail = appInfo.cast<String, dynamic>();
    final adaptiveType = firstNonBlank([
      detail['adaptive_type'],
      detail['adaptiveType'],
    ]);
    final electronicCertUrl = firstNonBlank([
      detail['electronic_cert_url'],
      detail['electronicCertUrl'],
    ]);
    final upload = await http.getJson(
      'https://oop-openapi-cn.heytapmobi.com/resource/v1/upload/get-upload-url',
      query: _signed({}, token),
    );
    final data = upload['data'] as Map;
    final apkResult = await http.postMultipart(
      data['upload_url'].toString(),
      file: file,
      fileField: 'file',
      fields: {'type': 'apk', 'sign': data['sign'].toString()},
      query: _signed({'type': 'apk', 'sign': data['sign'].toString()}, token),
      progress: progress,
    );
    final apkData = apkResult['data'] as Map;
    final versionCodeText = findNestedTextByKeys(apkData, const [
      'versionCode',
      'version_code',
      'pkgVersionCode',
      'apkVersionCode',
    ]);
    final versionCode = int.tryParse(versionCodeText ?? '');
    if (versionCode == null) {
      throw StateError('OPPO 上传返回中缺少 versionCode: $apkResult');
    }
    final params = {
      'pkg_name': applicationId,
      'version_code': versionCode.toString(),
      'apk_url': jsonEncode([
        {'url': apkData['url'], 'md5': apkData['md5'], 'cpu_code': 0},
      ]),
      'app_name': requiredText(
          detail,
          const [
            'app_name',
            'appName',
          ],
          'app_name'),
      'update_desc': versionParams.updateDesc,
      'second_category_id': requiredText(
          detail,
          const [
            'ver_second_category_id',
            'second_category_id',
          ],
          'second_category_id'),
      'third_category_id': requiredText(
          detail,
          const [
            'ver_third_category_id',
            'third_category_id',
          ],
          'third_category_id'),
      'summary': requiredText(detail, const ['summary'], 'summary'),
      'detail_desc': requiredText(detail, const ['detail_desc'], 'detail_desc'),
      'privacy_source_url': requiredText(
          detail,
          const [
            'privacy_source_url',
          ],
          'privacy_source_url'),
      'icon_url': requiredText(detail, const ['icon_url'], 'icon_url'),
      'pic_url': requiredText(detail, const ['pic_url'], 'pic_url'),
      'test_desc': requiredText(detail, const ['test_desc'], 'test_desc'),
      'business_username': requiredText(
          detail,
          const [
            'business_username',
          ],
          'business_username'),
      'business_email': requiredText(
          detail,
          const [
            'business_email',
          ],
          'business_email'),
      'business_mobile': requiredText(
          detail,
          const [
            'business_mobile',
          ],
          'business_mobile'),
      'age_level': requiredText(
          detail,
          const [
            'age_level',
            'ageLevel',
          ],
          'age_level'),
      'adaptive_equipment': requiredText(
          detail,
          const [
            'adaptive_equipment',
            'adaptiveEquipment',
          ],
          'adaptive_equipment'),
      'copyright_url': requiredText(
          detail,
          const [
            'copyright_url',
            'copyrightUrl',
          ],
          'copyright_url'),
      ...?adaptiveType == null ? null : {'adaptive_type': adaptiveType},
      ...?electronicCertUrl == null
          ? null
          : {'electronic_cert_url': electronicCertUrl},
      'online_type': versionParams.onlineTime > 0 ? '2' : '1',
      if (versionParams.onlineTime > 0)
        'sche_online_time': formatOnlineTime(versionParams.onlineTime),
    };
    final result = await http.postForm(
      'https://oop-openapi-cn.heytapmobi.com/resource/v1/app/upd',
      data: params,
      query: _signed(params, token),
    );
    checkApiSuccess(
      result['errno'] as num?,
      0,
      '提交OPPO版本',
      result['data']?['message']?.toString() ?? '',
    );
  }
}

class VivoStoreChannel extends BaseStoreChannel {
  @override
  String get storeName => 'VIVO';

  @override
  String get apkFileMarker => 'VIVO';

  @override
  List<StoreCredentialDefinition> get credentialDefinitions => const [
        StoreCredentialDefinition('access_key'),
        StoreCredentialDefinition('access_secret'),
      ];

  @override
  bool get allowsEmptyUpdateDesc => true;

  Map<String, String> _signed(String method, Map<String, String> params) {
    final data = {
      ...params,
      'access_key': value('access_key'),
      'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      'method': method,
      'v': '1.0',
      'sign_method': 'HMAC-SHA256',
      'format': 'json',
      'target_app_key': 'developer',
    };
    final keys = data.keys.toList()..sort();
    data['sign'] = hmacSha256Hex(
      keys.map((k) => '$k=${data[k]}').join('&'),
      value('access_secret'),
    );
    return data;
  }

  void _checkVivoSuccess(Map<String, dynamic> result, String action) {
    checkApiSuccess(
      result['code'] as num?,
      0,
      action,
      result['msg']?.toString() ?? '',
    );
    final subCode = int.tryParse(result['subCode']?.toString() ?? '') ?? 0;
    checkApiSuccess(subCode, 0, action, result['msg']?.toString() ?? '');
  }

  String? _vivoFallbackUpdateDesc(Map<String, dynamic> info) {
    return fallbackUpdateDescFromDetail(info);
  }

  @override
  Future<StoreReviewSnapshot> fetchReviewSnapshot(String applicationId) async {
    final result = await http.getJson(
      'https://developer-api.vivo.com.cn/router/rest',
      query: _signed('app.query.details', {'packageName': applicationId}),
    );
    _checkVivoSuccess(result, '查询VIVO应用详情');
    final data = result['data'];
    if (data is! Map) {
      return const StoreReviewSnapshot(reviewState: StoreReviewState.unknown);
    }
    final info = data.cast<String, dynamic>();
    final status = int.tryParse(info['status']?.toString() ?? '');
    final reviewState = switch (status) {
      1 => StoreReviewState.draft,
      2 => StoreReviewState.underReview,
      3 => StoreReviewState.online,
      4 => StoreReviewState.rejected,
      5 => StoreReviewState.withdrawn,
      _ => StoreReviewState.unknown,
    };
    return StoreReviewSnapshot(
      reviewState: reviewState,
      enableSubmit: status != 2,
      lastVersion: StoreVersion(
        int.tryParse(info['versionCode']?.toString() ?? '') ?? 0,
        info['versionName']?.toString() ?? '',
      ),
      fallbackUpdateDesc: _vivoFallbackUpdateDesc(info),
    );
  }

  @override
  ReleasePlan resolveReleasePlan(
    ReleasePlan versionParams,
    StoreReviewSnapshot reviewSnapshot,
  ) =>
      resolveReleasePlanWithFallback(versionParams, reviewSnapshot);

  @override
  Future<void> upload(
    File file,
    String applicationId,
    ReleasePlan versionParams,
    ProgressCallback progress,
  ) async {
    final apk = await http.postMultipart(
      'https://developer-api.vivo.com.cn/router/rest',
      file: file,
      fileField: 'file',
      query: _signed('app.upload.apk.app', {
        'packageName': applicationId,
        'fileMd5': await fileMd5(file),
      }),
      progress: progress,
    );
    _checkVivoSuccess(apk, '上传VIVO apk');
    final data = apk['data'] as Map;
    final params = {
      'packageName': data['packageName'].toString(),
      'versionCode': data['versionCode'].toString(),
      'apk': data['serialnumber'].toString(),
      'fileMd5': data['fileMd5'].toString(),
      'onlineType': versionParams.onlineTime > 0 ? '2' : '1',
      'updateDesc': versionParams.updateDesc,
      if (versionParams.onlineTime > 0)
        'scheOnlineTime': formatOnlineTime(versionParams.onlineTime),
    };
    final result = await http.getJson(
      'https://developer-api.vivo.com.cn/router/rest',
      query: _signed('app.sync.update.app', params),
    );
    _checkVivoSuccess(result, '提交VIVO更新');
  }
}

class HonorStoreChannel extends HuaweiStoreChannel {
  @override
  String get storeName => '荣耀';

  @override
  String get apkFileMarker => 'HONOR';

  @override
  bool get allowsEmptyUpdateDesc => true;

  Future<String> _honorToken() async {
    final result = await http.postForm(
      'https://iam.developer.honor.com/auth/token',
      data: {
        'client_id': value('client_id'),
        'client_secret': value('client_secret'),
        'grant_type': 'client_credentials',
      },
    );
    final token = result['access_token'] ??
        result['token'] ??
        result['data']?['access_token'];
    if (token == null ||
        token.toString().isEmpty ||
        token.toString() == 'null') {
      throw StateError('获取荣耀 token 失败: $result');
    }
    return token.toString();
  }

  void _checkHonorResult(Map<String, dynamic> result, String action) {
    checkResultCode(result, action);
  }

  @override
  Future<StoreReviewSnapshot> fetchReviewSnapshot(String applicationId) async {
    final token = await _honorToken();
    final appIdResult = await http.getJson(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/get-app-id',
      query: {'pkgName': applicationId},
      headers: {'Authorization': 'Bearer $token'},
    );
    _checkHonorResult(appIdResult, '获取荣耀 AppId');
    final appId = _honorAppIdFrom(appIdResult);
    final result = await http.getJson(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/get-app-current-release',
      query: {'appId': appId},
      headers: {'Authorization': 'Bearer $token'},
    );
    _checkHonorResult(result, '获取荣耀审核状态');
    return _parseHonorMarketInfo(result, appId, token);
  }

  Future<StoreReviewSnapshot> _parseHonorMarketInfo(
    Map<String, dynamic> result,
    String appId,
    String token,
  ) async {
    final rawData = result['data'] ?? result;
    final data =
        rawData is Map ? rawData.cast<String, dynamic>() : <String, dynamic>{};
    final auditResult = int.tryParse(data['auditResult']?.toString() ?? '');
    final reviewState = switch (auditResult) {
      0 => StoreReviewState.underReview,
      1 => StoreReviewState.online,
      2 => StoreReviewState.rejected,
      _ => StoreReviewState.unknown,
    };
    var versionCode = int.tryParse(data['versionCode']?.toString() ?? '');
    var versionName = firstNonBlank([
      data['versionName'],
      data['versionNumber'],
    ]);

    final detail = await http.getJson(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/get-app-detail',
      query: {'appId': appId},
      headers: {'Authorization': 'Bearer $token'},
    );
    final releaseInfo = detail['data']?['releaseInfo'];
    if ((versionCode == null || versionName == null) && releaseInfo is Map) {
      versionCode ??= int.tryParse(
        releaseInfo['versionCode']?.toString() ?? '',
      );
      versionName ??= firstNonBlank([
        releaseInfo['versionName'],
        releaseInfo['versionNumber'],
      ]);
    }
    final publishInfo = detail['data']?['publishInfo'];
    final phasedReleaseActive = await _hasHonorPhasedRelease(appId, token);
    final scheduledReleasePending = _isHonorScheduledReleasePending(
      data,
      publishInfo,
      releaseInfo,
    );
    final submitDisabledReason = phasedReleaseActive
        ? '存在待分阶段发布或分阶段发布中的版本'
        : scheduledReleasePending
            ? '存在待发布时间的版本'
            : auditResult == 0
                ? '当前版本审核中'
                : null;

    return StoreReviewSnapshot(
      reviewState: reviewState,
      enableSubmit:
          auditResult != 0 && !phasedReleaseActive && !scheduledReleasePending,
      lastVersion: versionCode == null && versionName == null
          ? null
          : StoreVersion(versionCode ?? 0, versionName ?? ''),
      submitDisabledReason: submitDisabledReason,
      fallbackUpdateDesc: fallbackUpdateDescFromDetail(detail),
    );
  }

  @override
  ReleasePlan resolveReleasePlan(
    ReleasePlan versionParams,
    StoreReviewSnapshot reviewSnapshot,
  ) =>
      resolveReleasePlanWithFallback(versionParams, reviewSnapshot);

  Future<bool> _hasHonorPhasedRelease(String appId, String token) async {
    final result = await http.getJson(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/get-phased-release-info',
      query: {'appId': appId},
      headers: {'Authorization': 'Bearer $token'},
    );
    _checkHonorResult(result, '获取荣耀分阶段发布状态');
    final data = result['data'];
    if (data == null) return false;
    if (data is List) return data.isNotEmpty;
    if (data is Map) return data.isNotEmpty;
    return data.toString().trim().isNotEmpty && data.toString() != 'null';
  }

  bool _isHonorScheduledReleasePending(
    Map<String, dynamic> currentRelease,
    Object? publishInfo,
    Object? releaseInfo,
  ) {
    if (publishInfo is! Map) return false;
    final info = publishInfo.cast<String, dynamic>();
    final releaseType = int.tryParse(info['releaseType']?.toString() ?? '');
    if (releaseType != 2) return false;
    final releaseTime = _parseUtcLikeTime(info['releaseTime']?.toString());
    if (releaseTime == null || !releaseTime.isAfter(DateTime.now())) {
      return false;
    }
    final latestVersionCode = int.tryParse(
      currentRelease['versionCode']?.toString() ?? '',
    );
    final onlineVersionCode = releaseInfo is Map
        ? int.tryParse(releaseInfo['versionCode']?.toString() ?? '')
        : null;
    return latestVersionCode != null &&
        onlineVersionCode != null &&
        latestVersionCode != onlineVersionCode;
  }

  DateTime? _parseUtcLikeTime(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final normalized = text.replaceFirstMapped(
      RegExp(r'([+-]\d{2})(\d{2})$'),
      (m) => '${m[1]}:${m[2]}',
    );
    return DateTime.tryParse(normalized);
  }

  @override
  Future<void> upload(
    File file,
    String applicationId,
    ReleasePlan versionParams,
    ProgressCallback progress,
  ) async {
    final token = await _honorToken();
    final auth = 'Bearer $token';
    final appIdResult = await http.getJson(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/get-app-id',
      query: {'pkgName': applicationId},
      headers: {'Authorization': auth},
    );
    _checkHonorResult(appIdResult, '获取荣耀 AppId');
    final appIds = appIdResult['data'];
    final appId = _honorAppIdFrom({'data': appIds});
    final appInfo = await http.getJson(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/get-app-detail',
      query: {'appId': appId},
      headers: {'Authorization': auth},
    );
    _checkHonorResult(appInfo, '获取荣耀 App信息');
    final languageInfo = appInfo['data']?['languageInfo'] is List &&
            (appInfo['data']['languageInfo'] as List).isNotEmpty
        ? (appInfo['data']['languageInfo'] as List).first as Map
        : const {};
    final uploadUrls = await http.postJson(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/get-file-upload-url',
      query: {'appId': appId},
      headers: {'Authorization': auth},
      data: [
        {
          'fileName': file.uri.pathSegments.last,
          'fileType': 100,
          'fileSize': await file.length(),
          'fileSha256': await fileSha256(file),
        },
      ],
    );
    _checkHonorResult(uploadUrls, '获取荣耀上传地址');
    final uploadUrl = (uploadUrls['data'] as List).first as Map;
    await http.postMultipart(
      (uploadUrl['uploadUrl'] ?? uploadUrl['url']).toString(),
      file: file,
      fileField: 'file',
      headers: {'Authorization': auth},
      progress: progress,
    );
    final bind = await http.postJson(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/update-file-info',
      query: {'appId': appId},
      headers: {'Authorization': auth},
      data: {
        'bindingFileList': [
          {'objectId': uploadUrl['objectId']},
        ],
      },
    );
    _checkHonorResult(bind, '绑定荣耀已上传Apk');
    final updateDesc = await http.postJson(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/update-language-info',
      query: {'appId': appId},
      headers: {'Authorization': auth},
      data: {
        'languageInfoList': [
          {
            'languageId': languageInfo['languageId'] ?? 'zh-CN',
            'appName': languageInfo['appName'] ?? '',
            'intro': languageInfo['intro'] ?? '',
            'briefIntro': languageInfo['briefIntro'] ?? '',
            'newFeature': versionParams.updateDesc,
          },
        ],
        'setAll': 0,
      },
    );
    _checkHonorResult(updateDesc, '更新荣耀版本说明');
    final submit = await http.postJson(
      'https://appmarket-openapi-drcn.cloud.honor.com/openapi/v1/publish/submit-audit',
      query: {'appId': appId},
      headers: {'Authorization': auth},
      data: {
        'releaseType': versionParams.onlineTime > 0 ? 2 : 1,
        if (versionParams.onlineTime > 0)
          'releaseTime': formatReleaseTime(versionParams.onlineTime),
      },
    );
    _checkHonorResult(submit, '提交荣耀审核');
  }

  String _honorAppIdFrom(Map<String, dynamic> result) {
    final list = result['data'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is Map) {
        final appId = first['appId'] ?? first['id'] ?? first['value'];
        if (appId != null &&
            appId.toString().isNotEmpty &&
            appId.toString() != 'null') {
          return appId.toString();
        }
      }
    }
    final appId = result['appId'] ?? result['id'] ?? result['value'];
    if (appId == null ||
        appId.toString().isEmpty ||
        appId.toString() == 'null') {
      throw StateError('获取荣耀 AppId 失败: $result');
    }
    return appId.toString();
  }
}
