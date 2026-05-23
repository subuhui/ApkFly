import 'package:apk_fly/channels/channel_registry.dart';
import 'package:apk_fly/config/app_profile_repository.dart';
import 'package:apk_fly/services/app_paths.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appPathsProvider = Provider((ref) => AppPaths());
final configRepositoryProvider = Provider(
  (ref) => AppProfileRepository(ref.watch(appPathsProvider)),
);
final channelRegistryProvider = Provider((ref) => ChannelRegistry.production());
