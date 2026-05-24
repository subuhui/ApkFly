import 'dart:io';

import 'package:apk_fly/app/providers.dart';
import 'package:apk_fly/channels/channel_models.dart';
import 'package:apk_fly/config/app_profile.dart';
import 'package:apk_fly/services/app_logger.dart';
import 'package:apk_fly/utils/apk_parser.dart';
import 'package:apk_fly/utils/file_util.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final uploadControllerProvider = StateNotifierProvider.autoDispose
    .family<UploadController, UploadState, AppProfile>(
      (ref, config) => UploadController(ref, config),
    );

class UploadState {
  const UploadState({
    required this.config,
    this.apkPath = '',
    this.updateDesc = '',
    this.onlineTime = 0,
    this.selectedChannels = const {},
    this.publishStates = const {},
    this.running = false,
    this.apkInfo,
    this.error,
  });

  final AppProfile config;
  final String apkPath;
  final String updateDesc;
  final int onlineTime;
  final Set<String> selectedChannels;
  final Map<String, PublishState> publishStates;
  final bool running;
  final ApkMetadata? apkInfo;
  final String? error;

  UploadState copyWith({
    String? apkPath,
    String? updateDesc,
    int? onlineTime,
    Set<String>? selectedChannels,
    Map<String, PublishState>? publishStates,
    bool? running,
    ApkMetadata? apkInfo,
    String? error,
  }) {
    return UploadState(
      config: config,
      apkPath: apkPath ?? this.apkPath,
      updateDesc: updateDesc ?? this.updateDesc,
      onlineTime: onlineTime ?? this.onlineTime,
      selectedChannels: selectedChannels ?? this.selectedChannels,
      publishStates: publishStates ?? this.publishStates,
      running: running ?? this.running,
      apkInfo: apkInfo ?? this.apkInfo,
      error: error,
    );
  }
}

class UploadController extends StateNotifier<UploadState> {
  UploadController(this.ref, AppProfile config)
    : super(
        UploadState(
          config: config,
          updateDesc: config.preferences.updateDesc ?? '',
          apkPath: config.preferences.apkDir ?? '',
          selectedChannels: config.stores
              .where((e) => e.enable)
              .map((e) => e.name)
              .toSet(),
          publishStates: {
            for (final name
                in config.stores.where((e) => e.enable).map((e) => e.name))
              name: const PublishIdle(),
          },
        ),
      );

  final Ref ref;

  void setApkPath(String path) =>
      state = state.copyWith(apkPath: path, error: null);

  void setUpdateDesc(String value) =>
      state = state.copyWith(updateDesc: value, error: null);

  void setReleaseNow() => state = state.copyWith(onlineTime: 0, error: null);

  void enableScheduledRelease() {
    if (state.onlineTime > 0) return;
    final now = DateTime.now();
    final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1);
    state = state.copyWith(
      onlineTime: nextHour.millisecondsSinceEpoch,
      error: null,
    );
  }

  void setOnlineTime(DateTime value) {
    state = state.copyWith(
      onlineTime: value.millisecondsSinceEpoch,
      error: null,
    );
  }

  void toggleChannel(String name, bool selected) {
    final next = {...state.selectedChannels};
    selected ? next.add(name) : next.remove(name);
    state = state.copyWith(
      selectedChannels: next,
      publishStates: {
        for (final name in next)
          name: state.publishStates[name] ?? const PublishIdle(),
      },
    );
  }

  Future<void> parseSelectedApk() async {
    final file = File(state.apkPath);
    final apk = file.existsSync() && file.path.toLowerCase().endsWith('.apk')
        ? file
        : await _findApkFor(_firstOrNull(state.selectedChannels));
    if (apk == null) {
      state = state.copyWith(error: '找不到 APK 文件');
      return;
    }
    final info = await parseApkMetadata(apk);
    state = state.copyWith(apkPath: file.path, apkInfo: info, error: null);
  }

  Future<void> start({bool retryOnly = false}) async {
    if (state.selectedChannels.isEmpty) {
      state = state.copyWith(error: '请至少选择一个渠道');
      return;
    }
    if (state.updateDesc.trim().isEmpty) {
      state = state.copyWith(error: '请输入更新说明');
      return;
    }
    if (state.onlineTime > 0) {
      final releaseAt = DateTime.fromMillisecondsSinceEpoch(state.onlineTime);
      if (!releaseAt.isAfter(DateTime.now())) {
        state = state.copyWith(
          error:
              '定时发布时间必须晚于当前时间：'
              '${releaseAt.year.toString().padLeft(4, '0')}-'
              '${releaseAt.month.toString().padLeft(2, '0')}-'
              '${releaseAt.day.toString().padLeft(2, '0')} '
              '${releaseAt.hour.toString().padLeft(2, '0')}:'
              '${releaseAt.minute.toString().padLeft(2, '0')}',
        );
        return;
      }
    }
    state = state.copyWith(running: true, error: null);
    final targets = retryOnly
        ? state.publishStates.entries
              .where((e) => e.value is PublishFailure)
              .map((e) => e.key)
              .toSet()
        : state.selectedChannels;
    final params = ReleasePlan(
      updateDesc: state.updateDesc.trim(),
      onlineTime: state.onlineTime,
    );
    for (final storeName in targets) {
      await _runChannel(storeName, params);
    }
    state = state.copyWith(running: false);
  }

  Future<void> _runChannel(String storeName, ReleasePlan params) async {
    setPublishState(storeName, const PublishWaiting());
    try {
      final registry = ref.read(channelRegistryProvider);
      final task = registry.byName(storeName);
      final channelConfig = state.config.store(storeName);
      if (task == null || channelConfig == null) {
        throw StateError('找不到渠道: $storeName');
      }
      task.init({
        for (final param in channelConfig.params) param.name: param.value,
      });
      final apkFile = await _findApkFor(storeName);
      if (apkFile == null) throw StateError('找不到 $storeName 对应的 APK');
      final apkInfo = await parseApkMetadata(apkFile);
      state = state.copyWith(apkInfo: apkInfo);
      final reviewSnapshot = await task.fetchReviewSnapshot(
        apkInfo.applicationId,
      );
      if (!reviewSnapshot.enableSubmit) {
        throw StateError(
          '$storeName 当前状态不允许提交，'
          '${reviewSnapshot.submitDisabledReason ?? '状态：${reviewSnapshot.reviewState.label}'}',
        );
      }
      setPublishState(storeName, const PublishProcessing('请求中'));
      await task.upload(
        apkFile,
        apkInfo,
        params,
        (progress) => setPublishState(storeName, PublishUploading(progress)),
      );
      setPublishState(storeName, const PublishSuccess());
    } catch (error, stack) {
      await AppLogger.instance.error(storeName, '提交失败: $error', stack);
      setPublishState(storeName, PublishFailure(error));
    }
  }

  Future<File?> _findApkFor(String? storeName) async {
    if (state.apkPath.isEmpty) {
      return null;
    }
    final selected = File(state.apkPath);
    if (selected.existsSync() && selected.path.toLowerCase().endsWith('.apk')) {
      return selected;
    }
    if (!selected.existsSync()) {
      return null;
    }
    if (!state.config.usesChannelPackages || storeName == null) {
      final apks = await listApks(selected);
      return _firstOrNull(apks);
    }
    final channel = state.config.store(storeName);
    final identify = channel?.paramValue('fileNameIdentify') ?? storeName;
    final apks = await listApks(selected);
    for (final apk in apks) {
      if (apk.uri.pathSegments.last.toLowerCase().contains(
        identify.toLowerCase(),
      )) {
        return apk;
      }
    }
    return null;
  }

  void setPublishState(String name, PublishState submitState) {
    state = state.copyWith(
      publishStates: {...state.publishStates, name: submitState},
    );
  }
}

T? _firstOrNull<T>(Iterable<T> values) {
  final iterator = values.iterator;
  return iterator.moveNext() ? iterator.current : null;
}
