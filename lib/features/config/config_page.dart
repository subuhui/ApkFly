import 'dart:io';

import 'package:apk_fly/app/providers.dart';
import 'package:apk_fly/channels/channel_models.dart';
import 'package:apk_fly/config/app_profile.dart';
import 'package:apk_fly/features/config/config_controller.dart';
import 'package:apk_fly/features/home/home_controller.dart';
import 'package:apk_fly/widgets/app_shell.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ConfigPage extends ConsumerWidget {
  const ConfigPage({super.key, this.applicationId});

  final String? applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(configDraftProvider(applicationId));
    return AppShell(
      title: applicationId == null ? '添加应用' : '编辑应用',
      actions: [
        TextButton(onPressed: () => context.go('/'), child: const Text('返回')),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: draft.value == null
              ? null
              : () async {
                  final error = await ref
                      .read(configDraftProvider(applicationId).notifier)
                      .save(oldApplicationId: applicationId);
                  if (context.mounted) {
                    if (error != null) {
                      showSnack(context, error);
                    } else {
                      ref.invalidate(homeControllerProvider);
                      context.go('/');
                    }
                  }
                },
          icon: const Icon(Icons.save),
          label: const Text('保存'),
        ),
      ],
      child: draft.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(error.toString())),
        data: (config) =>
            _ConfigForm(config: config, applicationId: applicationId),
      ),
    );
  }
}

class _ConfigForm extends ConsumerWidget {
  const _ConfigForm({required this.config, required this.applicationId});

  final AppProfile config;
  final String? applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(configDraftProvider(applicationId).notifier);
    final registry = ref.watch(channelRegistryProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: _TextField(
                label: 'App 名称',
                value: config.name,
                onChanged: (value) =>
                    notifier.update((c) => c.copyWith(name: value)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _TextField(
                label: 'ApplicationId',
                value: config.applicationId,
                onChanged: (value) =>
                    notifier.update((c) => c.copyWith(applicationId: value)),
              ),
            ),
            const SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: FilterChip(
                selected: config.usesChannelPackages,
                label: const Text('启用渠道包'),
                onSelected: (value) => notifier.update(
                  (c) => c.copyWith(usesChannelPackages: value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _TextField(
          label: '默认更新说明',
          value: config.preferences.updateDesc ?? '',
          minLines: 3,
          maxLines: 5,
          onChanged: (value) => notifier.update(
            (c) => c.copyWith(
              preferences: c.preferences.copyWith(updateDesc: value),
            ),
          ),
        ),
        const SizedBox(height: 24),
        for (final channel in config.stores)
          _ChannelEditor(
            channel: channel,
            params: registry.byName(channel.name)?.params ?? const [],
            onChanged: (next) => notifier.update(
              (c) => c.copyWith(
                stores: c.stores
                    .map((e) => e.name == next.name ? next : e)
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChannelEditor extends StatelessWidget {
  const _ChannelEditor({
    required this.channel,
    required this.params,
    required this.onChanged,
  });

  final StoreConfig channel;
  final List<StoreCredentialDefinition> params;
  final ValueChanged<StoreConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  channel.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Switch(
                  value: channel.enable,
                  onChanged: (value) =>
                      onChanged(channel.copyWith(enable: value)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (var i = 0; i < channel.params.length; i++)
                  SizedBox(
                    width: 360,
                    child: _ParamField(
                      param: channel.params[i],
                      definition: _paramDefinition(channel.params[i].name),
                      onChanged: (value) {
                        final next = [...channel.params]
                          ..[i] = channel.params[i].copyWith(value: value);
                        onChanged(channel.copyWith(params: next));
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  StoreCredentialDefinition? _paramDefinition(String name) {
    for (final param in params) {
      if (param.name == name) {
        return param;
      }
    }
    return null;
  }
}

class _ParamField extends StatefulWidget {
  const _ParamField({
    required this.param,
    required this.onChanged,
    this.definition,
  });

  final StoreCredential param;
  final ValueChanged<String> onChanged;
  final StoreCredentialDefinition? definition;

  @override
  State<_ParamField> createState() => _ParamFieldState();
}

class _ParamFieldState extends State<_ParamField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.param.value);
  }

  @override
  void didUpdateWidget(covariant _ParamField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.param.value != widget.param.value &&
        _controller.text != widget.param.value) {
      _controller.text = widget.param.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textFileExtension = widget.definition?.textFileExtension;
    final pickFilePath = widget.definition?.pickFilePath == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(widget.param.name),
        TextFormField(
          controller: _controller,
          minLines:
              widget.param.name.toLowerCase().contains('secret') ||
                  widget.param.name.toLowerCase().contains('key')
              ? 1
              : 1,
          maxLines: widget.param.name == 'publicKey' ? 4 : 1,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            suffixIcon: textFileExtension == null && !pickFilePath
                ? null
                : IconButton(
                    icon: const Icon(Icons.file_open),
                    onPressed: () async {
                      final file = textFileExtension == null
                          ? await FilePicker.platform.pickFiles(
                              type: FileType.any,
                            )
                          : await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: [textFileExtension],
                            );
                      final path = file?.files.single.path;
                      if (path != null) {
                        final value = pickFilePath
                            ? path
                            : await File(path).readAsString();
                        _controller.text = value;
                        widget.onChanged(value);
                      }
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        TextFormField(
          initialValue: value,
          minLines: minLines,
          maxLines: maxLines,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
