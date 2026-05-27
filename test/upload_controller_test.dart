import 'dart:io';

import 'package:apk_fly/app/providers.dart';
import 'package:apk_fly/channels/channel_models.dart';
import 'package:apk_fly/channels/channel_registry.dart';
import 'package:apk_fly/channels/market_channels.dart';
import 'package:apk_fly/config/app_profile.dart';
import 'package:apk_fly/features/upload/upload_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UploadController', () {
    test(
        'allows VIVO-style channels to skip local apk parsing and reuse detail update desc',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('apk_fly_upload_test');
      addTearDown(() => tempDir.delete(recursive: true));
      final apkFile = File('${tempDir.path}/demo.apk');
      await apkFile.writeAsBytes(const [1, 2, 3, 4]);

      final channel = _FakeStoreChannel(
        storeNameValue: 'VIVO',
        allowsEmptyUpdateDescValue: true,
        snapshot: const StoreReviewSnapshot(
          reviewState: StoreReviewState.online,
          fallbackUpdateDesc: '来自详情接口的更新说明',
        ),
      );
      final profile = _profile(['VIVO']);
      final container = ProviderContainer(
        overrides: [
          channelRegistryProvider.overrideWithValue(ChannelRegistry([channel])),
        ],
      );
      addTearDown(container.dispose);

      final notifier =
          container.read(uploadControllerProvider(profile).notifier);
      notifier.setApkPath(apkFile.path);

      await notifier.start();

      final state = container.read(uploadControllerProvider(profile));
      expect(state.error, isNull);
      expect(state.publishStates['VIVO'], isA<PublishSuccess>());
      expect(channel.fetchedApplicationIds, ['com.demo.app']);
      expect(channel.uploadedApplicationId, 'com.demo.app');
      expect(channel.uploadedReleasePlan?.updateDesc, '来自详情接口的更新说明');
    });

    test('keeps requiring update desc for channels without fallback support',
        () async {
      final channel = _FakeStoreChannel(
        storeNameValue: '华为',
        snapshot:
            const StoreReviewSnapshot(reviewState: StoreReviewState.online),
      );
      final profile = _profile(['华为']);
      final container = ProviderContainer(
        overrides: [
          channelRegistryProvider.overrideWithValue(ChannelRegistry([channel])),
        ],
      );
      addTearDown(container.dispose);

      final notifier =
          container.read(uploadControllerProvider(profile).notifier);

      await notifier.start();

      final state = container.read(uploadControllerProvider(profile));
      expect(state.error, '请输入更新说明');
      expect(channel.fetchedApplicationIds, isEmpty);
      expect(channel.uploadedReleasePlan, isNull);
    });
  });

  group('Store update desc fallback', () {
    test('xiaomi reuses fallback update desc from snapshot', () {
      final channel = XiaomiStoreChannel();

      final plan = channel.resolveReleasePlan(
        const ReleasePlan(updateDesc: '', onlineTime: 0),
        const StoreReviewSnapshot(
          reviewState: StoreReviewState.online,
          fallbackUpdateDesc: '小米详情里的更新说明',
        ),
      );

      expect(plan.updateDesc, '小米详情里的更新说明');
    });

    test('honor reuses fallback update desc from snapshot', () {
      final channel = HonorStoreChannel();

      final plan = channel.resolveReleasePlan(
        const ReleasePlan(updateDesc: '', onlineTime: 0),
        const StoreReviewSnapshot(
          reviewState: StoreReviewState.online,
          fallbackUpdateDesc: '荣耀详情里的更新说明',
        ),
      );

      expect(plan.updateDesc, '荣耀详情里的更新说明');
    });

    test('oppo reuses fallback update desc from snapshot', () {
      final channel = OppoStoreChannel();

      final plan = channel.resolveReleasePlan(
        const ReleasePlan(updateDesc: '', onlineTime: 0),
        const StoreReviewSnapshot(
          reviewState: StoreReviewState.online,
          fallbackUpdateDesc: 'OPPO详情里的更新说明',
        ),
      );

      expect(plan.updateDesc, 'OPPO详情里的更新说明');
    });

    test('huawei reuses fallback update desc from snapshot', () {
      final channel = HuaweiStoreChannel();

      final plan = channel.resolveReleasePlan(
        const ReleasePlan(updateDesc: '', onlineTime: 0),
        const StoreReviewSnapshot(
          reviewState: StoreReviewState.online,
          fallbackUpdateDesc: '华为详情里的更新说明',
        ),
      );

      expect(plan.updateDesc, '华为详情里的更新说明');
    });

    test('xiaomi throws when fallback update desc is missing', () {
      final channel = XiaomiStoreChannel();

      expect(
        () => channel.resolveReleasePlan(
          const ReleasePlan(updateDesc: '', onlineTime: 0),
          const StoreReviewSnapshot(reviewState: StoreReviewState.online),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

AppProfile _profile(List<String> storeNames) {
  return AppProfile(
    name: 'Demo',
    applicationId: 'com.demo.app',
    createTime: 0,
    stores: [
      for (final storeName in storeNames)
        StoreConfig(name: storeName, enable: true, params: const []),
    ],
    usesChannelPackages: false,
    preferences: const ProfilePreferences(),
  );
}

class _FakeStoreChannel extends StoreChannel {
  _FakeStoreChannel({
    required this.storeNameValue,
    this.allowsEmptyUpdateDescValue = false,
    required this.snapshot,
  });

  final String storeNameValue;
  final bool allowsEmptyUpdateDescValue;
  final StoreReviewSnapshot snapshot;

  final List<String> fetchedApplicationIds = [];
  String? uploadedApplicationId;
  ReleasePlan? uploadedReleasePlan;

  @override
  String get storeName => storeNameValue;

  @override
  String get apkFileMarker => storeNameValue;

  @override
  List<StoreCredentialDefinition> get credentialDefinitions => const [];

  @override
  bool get allowsEmptyUpdateDesc => allowsEmptyUpdateDescValue;

  @override
  void init(Map<String, String?> params) {}

  @override
  Future<StoreReviewSnapshot> fetchReviewSnapshot(String applicationId) async {
    fetchedApplicationIds.add(applicationId);
    return snapshot;
  }

  @override
  ReleasePlan resolveReleasePlan(
    ReleasePlan versionParams,
    StoreReviewSnapshot reviewSnapshot,
  ) {
    if (versionParams.updateDesc.isNotEmpty) {
      return versionParams;
    }
    final fallback = reviewSnapshot.fallbackUpdateDesc;
    if (fallback == null || fallback.isEmpty) {
      return versionParams;
    }
    return versionParams.copyWith(updateDesc: fallback);
  }

  @override
  Future<void> upload(
    File file,
    String applicationId,
    ReleasePlan versionParams,
    ProgressCallback progress,
  ) async {
    uploadedApplicationId = applicationId;
    uploadedReleasePlan = versionParams;
  }
}
