import 'package:apk_fly/channels/channel_models.dart';
import 'package:apk_fly/channels/market_channels.dart';

class ChannelRegistry {
  ChannelRegistry(this.stores);

  factory ChannelRegistry.production() {
    return ChannelRegistry([
      HuaweiStoreChannel(),
      XiaomiStoreChannel(),
      OppoStoreChannel(),
      VivoStoreChannel(),
      HonorStoreChannel(),
    ]);
  }

  final List<StoreChannel> stores;

  StoreChannel? byName(String name) {
    for (final store in stores) {
      if (store.storeName == name) return store;
    }
    return null;
  }
}
