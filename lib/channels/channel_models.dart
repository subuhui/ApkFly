import 'dart:io';

enum StoreReviewState {
  online('已上线'),
  underReview('审核中'),
  rejected('被拒绝'),
  unknown('未知状态');

  const StoreReviewState(this.label);
  final String label;
}

class StoreReviewSnapshot {
  const StoreReviewSnapshot({
    required this.reviewState,
    this.enableSubmit = true,
    this.lastVersion,
  });

  final StoreReviewState reviewState;
  final bool enableSubmit;
  final StoreVersion? lastVersion;
}

class StoreVersion {
  const StoreVersion(this.code, this.name);

  final int code;
  final String name;
}

class ApkMetadata {
  const ApkMetadata({
    required this.path,
    required this.applicationId,
    required this.versionCode,
    required this.versionName,
  });

  final String path;
  final String applicationId;
  final int versionCode;
  final String versionName;
}

class ReleasePlan {
  const ReleasePlan({required this.updateDesc, required this.onlineTime});

  final String updateDesc;
  final int onlineTime;
}

class ApiException implements Exception {
  const ApiException(this.code, this.action, this.message);

  final int code;
  final String action;
  final String message;

  @override
  String toString() => '$action失败，code:$code，message:$message';
}

void checkApiSuccess(
  num? code,
  num successCode,
  String action,
  String message,
) {
  if (code != successCode) {
    throw ApiException((code ?? -1).toInt(), action, message);
  }
}

sealed class PublishState {
  const PublishState();

  bool get finish => this is PublishSuccess || this is PublishFailure;
  bool get success => this is PublishSuccess;
  String get label => switch (this) {
    PublishIdle() => '未开始',
    PublishWaiting() => '等待中',
    PublishUploading(:final progress) => '上传中 $progress%',
    PublishProcessing(:final action) => action,
    PublishSuccess() => '成功',
    PublishFailure(:final error) => error.toString(),
  };
}

class PublishIdle extends PublishState {
  const PublishIdle();
}

class PublishWaiting extends PublishState {
  const PublishWaiting();
}

class PublishUploading extends PublishState {
  const PublishUploading(this.progress);
  final int progress;
}

class PublishProcessing extends PublishState {
  const PublishProcessing(this.action);
  final String action;
}

class PublishSuccess extends PublishState {
  const PublishSuccess();
}

class PublishFailure extends PublishState {
  const PublishFailure(this.error);
  final Object error;
}

typedef ProgressCallback = void Function(int progress);

class StoreCredentialDefinition {
  const StoreCredentialDefinition(
    this.name, {
    this.defaultValue,
    this.desc,
    this.textFileExtension,
  });

  final String name;
  final String? defaultValue;
  final String? desc;
  final String? textFileExtension;
}

abstract class StoreChannel {
  String get storeName;
  String get apkFileMarker;
  List<StoreCredentialDefinition> get credentialDefinitions;

  List<StoreCredentialDefinition> get params => [
    ...credentialDefinitions,
    StoreCredentialDefinition(
      'fileNameIdentify',
      defaultValue: apkFileMarker,
      desc: '文件名标识,不区分大小写',
    ),
  ];

  void init(Map<String, String?> params);

  Future<void> upload(
    File file,
    ApkMetadata apkInfo,
    ReleasePlan versionParams,
    ProgressCallback progress,
  );

  Future<StoreReviewSnapshot> fetchReviewSnapshot(String applicationId);
}
