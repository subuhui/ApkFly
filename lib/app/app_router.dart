import 'package:apk_fly/features/config/config_page.dart';
import 'package:apk_fly/features/home/home_controller.dart';
import 'package:apk_fly/features/home/home_page.dart';
import 'package:apk_fly/features/start/start_page.dart';
import 'package:apk_fly/features/upload/upload_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          final home = ref.watch(homeControllerProvider);
          return home.when(
            loading: () => const StartPage(loading: true),
            error: (error, stack) => StartPage(error: error.toString()),
            data: (data) =>
                data.apps.isEmpty ? const StartPage() : const HomePage(),
          );
        },
      ),
      GoRoute(path: '/config', builder: (context, state) => const ConfigPage()),
      GoRoute(
        path: '/config/:id',
        builder: (context, state) =>
            ConfigPage(applicationId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/upload',
        builder: (context, state) => UploadPage(
          config: ref.read(homeControllerProvider).value!.current!,
        ),
      ),
    ],
  );
});
