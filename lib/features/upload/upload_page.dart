import 'package:apk_fly/channels/channel_models.dart';
import 'package:apk_fly/config/app_profile.dart';
import 'package:apk_fly/features/upload/upload_controller.dart';
import 'package:apk_fly/theme/app_theme.dart';
import 'package:apk_fly/widgets/app_shell.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class UploadPage extends ConsumerStatefulWidget {
  const UploadPage({super.key, required this.config});

  final AppProfile config;

  @override
  ConsumerState<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends ConsumerState<UploadPage> {
  late final TextEditingController _apkPathController;

  @override
  void initState() {
    super.initState();
    _apkPathController = TextEditingController();
  }

  @override
  void dispose() {
    _apkPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final state = ref.watch(uploadControllerProvider(config));
    final controller = ref.read(uploadControllerProvider(config).notifier);

    if (_apkPathController.text != state.apkPath) {
      _apkPathController.text = state.apkPath;
    }
    final scheduled = state.onlineTime > 0;
    final releaseAt = scheduled
        ? DateTime.fromMillisecondsSinceEpoch(state.onlineTime)
        : null;
    return AppShell(
      title: config.name,
      actions: [
        TextButton(
          onPressed: state.running ? null : () => context.go('/'),
          child: const Text('返回'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed:
              state.running ? null : () => controller.start(retryOnly: true),
          icon: const Icon(Icons.refresh),
          label: const Text('重试失败'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: state.running ? null : () => controller.start(),
          icon: const Icon(Icons.cloud_upload),
          label: const Text('开始提交'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('APK 文件或目录'),
                    TextFormField(
                      controller: _apkPathController,
                      onChanged: controller.setApkPath,
                      decoration: const InputDecoration(
                        hintText: '选择单 APK，或多渠道包目录',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['apk'],
                  );
                  final path = result?.files.single.path;
                  if (path != null) controller.setApkPath(path);
                },
                icon: const Icon(Icons.android),
                label: const Text('APK'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final path = await FilePicker.platform.getDirectoryPath();
                  if (path != null) controller.setApkPath(path);
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('目录'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const FieldLabel('更新说明'),
          TextFormField(
            initialValue: state.updateDesc,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText:
                  '请输入本次版本更新说明；留空时，VIVO / 小米 / OPPO / 华为 / 荣耀将复用商店详情中的已有说明',
            ),
            onChanged: controller.setUpdateDesc,
          ),
          const SizedBox(height: 18),
          const FieldLabel('发布方式'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<_ReleaseMode>(
                segments: const [
                  ButtonSegment<_ReleaseMode>(
                    value: _ReleaseMode.immediate,
                    icon: Icon(Icons.flash_on_outlined),
                    label: Text('立即发布'),
                  ),
                  ButtonSegment<_ReleaseMode>(
                    value: _ReleaseMode.scheduled,
                    icon: Icon(Icons.schedule),
                    label: Text('定时发布'),
                  ),
                ],
                selected: {
                  scheduled ? _ReleaseMode.scheduled : _ReleaseMode.immediate,
                },
                onSelectionChanged: state.running
                    ? null
                    : (selection) {
                        if (selection.contains(_ReleaseMode.scheduled)) {
                          controller.enableScheduledRelease();
                        } else {
                          controller.setReleaseNow();
                        }
                      },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ReleaseSummaryCard(
                  scheduled: scheduled,
                  releaseAt: releaseAt,
                  onPickDate: state.running || releaseAt == null
                      ? null
                      : () => _pickReleaseDate(context, releaseAt, controller),
                  onPickTime: state.running || releaseAt == null
                      ? null
                      : () => _pickReleaseTime(context, releaseAt, controller),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('目标渠道', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final channel in config.stores.where((e) => e.enable))
                FilterChip(
                  selected: state.selectedChannels.contains(channel.name),
                  label: Text(channel.name),
                  onSelected: state.running
                      ? null
                      : (selected) =>
                          controller.toggleChannel(channel.name, selected),
                ),
            ],
          ),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            Text(state.error!, style: const TextStyle(color: appDanger)),
          ],
          const SizedBox(height: 24),
          for (final entry in state.publishStates.entries)
            _SubmitRow(name: entry.key, state: entry.value),
        ],
      ),
    );
  }
}

enum _ReleaseMode { immediate, scheduled }

Future<void> _pickReleaseDate(
  BuildContext context,
  DateTime current,
  UploadController controller,
) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 365)),
  );
  if (picked == null) return;
  controller.setOnlineTime(
    DateTime(
      picked.year,
      picked.month,
      picked.day,
      current.hour,
      current.minute,
    ),
  );
}

Future<void> _pickReleaseTime(
  BuildContext context,
  DateTime current,
  UploadController controller,
) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(current),
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      );
    },
  );
  if (picked == null) return;
  controller.setOnlineTime(
    DateTime(
      current.year,
      current.month,
      current.day,
      picked.hour,
      picked.minute,
    ),
  );
}

class _ReleaseSummaryCard extends StatelessWidget {
  const _ReleaseSummaryCard({
    required this.scheduled,
    required this.releaseAt,
    required this.onPickDate,
    required this.onPickTime,
  });

  final bool scheduled;
  final DateTime? releaseAt;
  final VoidCallback? onPickDate;
  final VoidCallback? onPickTime;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final releaseText = releaseAt == null
        ? '审核通过后立即发布'
        : DateFormat('yyyy年MM月dd日 HH:mm').format(releaseAt!);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appLine),
      ),
      child: Row(
        children: [
          Icon(
            scheduled ? Icons.schedule : Icons.flash_on_outlined,
            color: scheduled ? appWarning : appAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scheduled ? '北京时间发布' : '发布时机',
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(releaseText, style: textTheme.bodyMedium),
              ],
            ),
          ),
          if (scheduled) ...[
            OutlinedButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('日期'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onPickTime,
              icon: const Icon(Icons.access_time),
              label: const Text('时间'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubmitRow extends StatelessWidget {
  const _SubmitRow({required this.name, required this.state});

  final String name;
  final PublishState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      PublishSuccess() => appAccent,
      PublishFailure() => appDanger,
      PublishUploading() || PublishProcessing() => appWarning,
      _ => appMuted,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(_iconFor(state), color: color),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: Text(name, style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(child: Text(state.label, overflow: TextOverflow.ellipsis)),
            if (state case PublishUploading(:final progress))
              SizedBox(
                width: 180,
                child: LinearProgressIndicator(value: progress / 100),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(PublishState state) => switch (state) {
        PublishSuccess() => Icons.check_circle,
        PublishFailure() => Icons.error,
        PublishUploading() => Icons.upload,
        PublishProcessing() => Icons.hourglass_bottom,
        _ => Icons.radio_button_unchecked,
      };
}
