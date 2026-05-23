import 'package:apk_fly/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StartPage extends StatelessWidget {
  const StartPage({super.key, this.loading = false, this.error});

  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Apk Fly',
      child: Center(
        child: SizedBox(
          width: 460,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '应用市场发版工作台',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(error ?? (loading ? '正在加载配置...' : '还没有应用配置，先添加一个 App。')),
                  const SizedBox(height: 24),
                  if (loading)
                    const LinearProgressIndicator()
                  else
                    FilledButton.icon(
                      onPressed: () => context.go('/config'),
                      icon: const Icon(Icons.add),
                      label: const Text('添加应用'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
