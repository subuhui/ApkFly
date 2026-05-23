import 'package:apk_fly/app/providers.dart';
import 'package:apk_fly/channels/channel_models.dart';
import 'package:apk_fly/config/app_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final configDraftProvider = StateNotifierProvider.autoDispose
    .family<ConfigDraftController, AsyncValue<AppProfile>, String?>(
      (ref, applicationId) => ConfigDraftController(ref, applicationId),
    );

class ConfigDraftController extends StateNotifier<AsyncValue<AppProfile>> {
  ConfigDraftController(this.ref, this.applicationId)
    : super(const AsyncLoading()) {
    _load();
  }

  final Ref ref;
  final String? applicationId;

  Future<void> _load() async {
    final repo = ref.read(configRepositoryProvider);
    final old = applicationId == null || applicationId!.isEmpty
        ? null
        : await repo.get(applicationId!);
    state = AsyncData(_create(old));
  }

  AppProfile _create(AppProfile? old) {
    final channels = ref.read(channelRegistryProvider).stores.map((task) {
      final oldChannel = old?.store(task.storeName);
      return StoreConfig(
        name: task.storeName,
        enable: oldChannel?.enable ?? true,
        params: task.params.map((param) {
          return StoreCredential(
            param.name,
            oldChannel?.paramValue(param.name) ?? param.defaultValue ?? '',
          );
        }).toList(),
      );
    }).toList();
    return AppProfile(
      name: old?.name ?? '',
      applicationId: old?.applicationId ?? '',
      createTime: old?.createTime ?? DateTime.now().millisecondsSinceEpoch,
      stores: channels,
      usesChannelPackages: old?.usesChannelPackages ?? false,
      preferences: old?.preferences ?? const ProfilePreferences(),
    );
  }

  void update(AppProfile Function(AppProfile config) change) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(change(current));
  }

  Future<String?> save({String? oldApplicationId}) async {
    final config = state.value;
    if (config == null) return '配置未加载';
    if (config.name.trim().isEmpty) return '请输入 App 名称';
    if (config.applicationId.trim().isEmpty) return '请输入 ApplicationId';
    if (config.stores.every((e) => !e.enable)) return '请至少启用一个渠道';
    for (final channel in config.stores.where((e) => e.enable)) {
      if (channel.params.any((e) => e.value.trim().isEmpty)) {
        return '${channel.name} 渠道参数未填充完整';
      }
    }
    final repo = ref.read(configRepositoryProvider);
    if (oldApplicationId != null &&
        oldApplicationId.isNotEmpty &&
        oldApplicationId != config.applicationId) {
      await repo.remove(oldApplicationId);
    }
    await repo.save(
      config.copyWith(
        name: config.name.trim(),
        applicationId: config.applicationId.trim(),
      ),
    );
    return null;
  }
}

extension ChannelParamLookup on StoreChannel {
  StoreCredentialDefinition? param(String name) {
    for (final param in params) {
      if (param.name == name) return param;
    }
    return null;
  }
}
