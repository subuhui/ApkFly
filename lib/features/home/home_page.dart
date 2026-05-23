import 'dart:async';

import 'package:apk_fly/app/providers.dart';
import 'package:apk_fly/features/home/home_controller.dart';
import 'package:apk_fly/theme/app_theme.dart';
import 'package:apk_fly/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _autoRefreshedApps = <String>{};
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeControllerProvider).value!;
    final current = state.current!;
    final channels = ref.watch(channelRegistryProvider).stores;
    if (_autoRefreshedApps.add(current.applicationId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(homeControllerProvider.notifier)
            .refreshEnabledReviewSnapshots();
      });
    }
    return AppShell(
      title: '软件版本更新',
      actions: [
        DropdownButton<String>(
          value: current.applicationId,
          items: [
            for (final app in state.apps)
              DropdownMenuItem(value: app.applicationId, child: Text(app.name)),
          ],
          onChanged: (id) {
            final app = state.apps.firstWhere((e) => e.applicationId == id);
            ref.read(homeControllerProvider.notifier).select(app);
          },
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: '刷新',
          onPressed: () => ref.read(homeControllerProvider.notifier).reload(),
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: '编辑',
          onPressed: () => context.go('/config/${current.applicationId}'),
          icon: const Icon(Icons.edit),
        ),
        IconButton(
          tooltip: '添加',
          onPressed: () => context.go('/config'),
          icon: const Icon(Icons.add),
        ),
        IconButton(
          tooltip: '删除',
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('删除配置'),
                content: Text('确定删除 ${current.name} 吗？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除'),
                  ),
                ],
              ),
            );
            if (ok == true) {
              ref.read(homeControllerProvider.notifier).removeCurrent();
            }
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  current.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(width: 12),
                SelectableText(
                  current.applicationId,
                  style: const TextStyle(color: appMuted),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => context.go('/upload'),
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('提交新版本'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 3.8,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                children: [
                  for (final task in channels)
                    _ChannelTile(
                      name: task.storeName,
                      enabled: current.store(task.storeName)?.enable == true,
                      identify:
                          current
                              .store(task.storeName)
                              ?.paramValue('fileNameIdentify') ??
                          task.apkFileMarker,
                      state: state.reviewSnapshots[task.storeName],
                      refreshRemaining: state.refreshRemaining(task.storeName),
                      onRefresh: () => ref
                          .read(homeControllerProvider.notifier)
                          .refreshReviewSnapshot(task.storeName),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.name,
    required this.enabled,
    required this.identify,
    required this.onRefresh,
    required this.refreshRemaining,
    this.state,
  });

  final String name;
  final bool enabled;
  final String identify;
  final AsyncValue<dynamic>? state;
  final Duration refreshRemaining;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              enabled ? Icons.check_circle : Icons.pause_circle,
              color: enabled ? appAccent : appMuted,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  _MarketStateText(
                    enabled: enabled,
                    identify: identify,
                    state: state,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: _refreshTooltip,
              onPressed: enabled && refreshRemaining == Duration.zero
                  ? onRefresh
                  : null,
              icon: state?.isLoading == true
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  String get _refreshTooltip {
    if (!enabled) return '渠道未启用';
    if (refreshRemaining == Duration.zero) return '刷新状态';
    final minutes = refreshRemaining.inMinutes;
    final seconds = refreshRemaining.inSeconds % 60;
    return '刷新冷却中 $minutes分${seconds.toString().padLeft(2, '0')}秒';
  }
}

class _MarketStateText extends StatelessWidget {
  const _MarketStateText({
    required this.enabled,
    required this.identify,
    this.state,
  });

  final bool enabled;
  final String identify;
  final AsyncValue<dynamic>? state;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const Text('未启用', style: TextStyle(color: appMuted));
    }
    final value = state;
    if (value == null) {
      return Text(
        '已启用，文件标识 $identify',
        style: const TextStyle(color: appMuted),
      );
    }
    return value.when(
      loading: () =>
          const Text('正在查询市场状态...', style: TextStyle(color: appMuted)),
      error: (error, stack) => Text(
        error.toString(),
        style: const TextStyle(color: appDanger),
        overflow: TextOverflow.ellipsis,
      ),
      data: (info) {
        final version = info.lastVersion == null
            ? ''
            : ' · v${info.lastVersion.name} (${info.lastVersion.code})';
        return Text(
          '${info.reviewState.label}$version',
          style: const TextStyle(color: appMuted),
        );
      },
    );
  }
}
