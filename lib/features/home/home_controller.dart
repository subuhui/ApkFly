import 'package:apk_fly/app/providers.dart';
import 'package:apk_fly/channels/channel_models.dart';
import 'package:apk_fly/config/app_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final homeControllerProvider = AsyncNotifierProvider<HomeController, HomeState>(
  HomeController.new,
);

class HomeState {
  const HomeState({
    required this.apps,
    this.current,
    this.reviewSnapshots = const {},
    this.lastRefreshAt = const {},
  });

  final List<AppProfile> apps;
  final AppProfile? current;
  final Map<String, AsyncValue<StoreReviewSnapshot>> reviewSnapshots;
  final Map<String, DateTime> lastRefreshAt;

  HomeState copyWith({
    List<AppProfile>? apps,
    AppProfile? current,
    Map<String, AsyncValue<StoreReviewSnapshot>>? reviewSnapshots,
    Map<String, DateTime>? lastRefreshAt,
  }) {
    return HomeState(
      apps: apps ?? this.apps,
      current: current ?? this.current,
      reviewSnapshots: reviewSnapshots ?? this.reviewSnapshots,
      lastRefreshAt: lastRefreshAt ?? this.lastRefreshAt,
    );
  }

  Duration refreshRemaining(String storeName) {
    final last = lastRefreshAt[storeName];
    if (last == null) return Duration.zero;
    final elapsed = DateTime.now().difference(last);
    if (elapsed >= HomeController.refreshCooldown) return Duration.zero;
    return HomeController.refreshCooldown - elapsed;
  }

  bool canRefresh(String storeName) =>
      refreshRemaining(storeName) == Duration.zero;
}

class HomeController extends AsyncNotifier<HomeState> {
  static const refreshCooldown = Duration(minutes: 3);

  @override
  Future<HomeState> build() async => _load();

  Future<HomeState> _load([String? currentId]) async {
    final apps = await ref.read(configRepositoryProvider).list();
    AppProfile? current;
    for (final app in apps) {
      if (app.applicationId == currentId) current = app;
    }
    current ??= apps.isEmpty ? null : apps.first;
    return HomeState(apps: apps, current: current);
  }

  Future<void> reload() async {
    final id = state.value?.current?.applicationId;
    final old = state.value;
    state = const AsyncLoading();
    final next = await _load(id);
    state = AsyncData(
      next.copyWith(
        reviewSnapshots: old?.reviewSnapshots,
        lastRefreshAt: old?.lastRefreshAt,
      ),
    );
  }

  void select(AppProfile config) {
    final value = state.value;
    if (value == null) return;
    state = AsyncData(HomeState(apps: value.apps, current: config));
  }

  Future<void> removeCurrent() async {
    final current = state.value?.current;
    if (current == null) return;
    await ref.read(configRepositoryProvider).remove(current.applicationId);
    state = AsyncData(await _load());
  }

  Future<void> refreshEnabledReviewSnapshots({
    bool ignoreCooldown = false,
  }) async {
    final current = state.value?.current;
    if (current == null) return;
    final enabledChannels = current.stores
        .where((channel) => channel.enable)
        .map((channel) => channel.name);
    for (final storeName in enabledChannels) {
      await refreshReviewSnapshot(storeName, ignoreCooldown: ignoreCooldown);
    }
  }

  Future<bool> refreshReviewSnapshot(
    String storeName, {
    bool ignoreCooldown = false,
  }) async {
    final value = state.value;
    final current = value?.current;
    if (value == null || current == null) return false;
    if (!ignoreCooldown && !value.canRefresh(storeName)) {
      return false;
    }
    final now = DateTime.now();
    state = AsyncData(
      value.copyWith(
        reviewSnapshots: {
          ...value.reviewSnapshots,
          storeName: const AsyncLoading(),
        },
        lastRefreshAt: {...value.lastRefreshAt, storeName: now},
      ),
    );
    try {
      final task = ref.read(channelRegistryProvider).byName(storeName);
      final channel = current.store(storeName);
      if (task == null || channel == null) {
        throw StateError('找不到渠道: $storeName');
      }
      task.init({for (final param in channel.params) param.name: param.value});
      final info = await task.fetchReviewSnapshot(current.applicationId);
      final latest = state.value ?? value;
      state = AsyncData(
        latest.copyWith(
          reviewSnapshots: {
            ...latest.reviewSnapshots,
            storeName: AsyncData(info),
          },
        ),
      );
      return true;
    } catch (error, stack) {
      final latest = state.value ?? value;
      state = AsyncData(
        latest.copyWith(
          reviewSnapshots: {
            ...latest.reviewSnapshots,
            storeName: AsyncError(error, stack),
          },
        ),
      );
      return true;
    }
  }
}
