import 'package:apk_fly/channels/channel_models.dart';
import 'package:apk_fly/config/app_profile.dart';
import 'package:apk_fly/features/upload/upload_controller.dart';
import 'package:apk_fly/theme/app_theme.dart';
import 'package:apk_fly/widgets/app_shell.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class UploadPage extends ConsumerWidget {
  const UploadPage({super.key, required this.config});

  final AppProfile config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(uploadControllerProvider(config));
    final controller = ref.read(uploadControllerProvider(config).notifier);
    return AppShell(
      title: '提交新版本',
      actions: [
        TextButton(
          onPressed: state.running ? null : () => context.go('/'),
          child: const Text('返回'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: state.running
              ? null
              : () => controller.start(retryOnly: true),
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
                      initialValue: state.apkPath,
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
            onChanged: controller.setUpdateDesc,
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
