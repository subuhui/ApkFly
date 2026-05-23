class AppProfile {
  const AppProfile({
    required this.name,
    required this.applicationId,
    required this.createTime,
    required this.stores,
    required this.usesChannelPackages,
    required this.preferences,
  });

  final String name;
  final String applicationId;
  final int createTime;
  final List<StoreConfig> stores;
  final bool usesChannelPackages;
  final ProfilePreferences preferences;

  StoreConfig? store(String name) {
    for (final store in stores) {
      if (store.name == name) return store;
    }
    return null;
  }

  AppProfile copyWith({
    String? name,
    String? applicationId,
    int? createTime,
    List<StoreConfig>? stores,
    bool? usesChannelPackages,
    ProfilePreferences? preferences,
  }) {
    return AppProfile(
      name: name ?? this.name,
      applicationId: applicationId ?? this.applicationId,
      createTime: createTime ?? this.createTime,
      stores: stores ?? this.stores,
      usesChannelPackages: usesChannelPackages ?? this.usesChannelPackages,
      preferences: preferences ?? this.preferences,
    );
  }

  Map<String, Object?> toMap() => {
    'name': name,
    'applicationId': applicationId,
    'createTime': createTime,
    'enableChannel': usesChannelPackages,
    'extension': preferences.toMap(),
    'channels': stores.map((e) => e.toMap()).toList(),
  };

  factory AppProfile.fromMap(Map<Object?, Object?> map) {
    return AppProfile(
      name: (map['name'] ?? '').toString(),
      applicationId: (map['applicationId'] ?? '').toString(),
      createTime: _asInt(map['createTime']),
      usesChannelPackages:
          map['enableChannel'] == true || map['usesChannelPackages'] == true,
      preferences: ProfilePreferences.fromMap(_asMap(map['extension'])),
      stores: _asList(
        map['channels'],
      ).map((e) => StoreConfig.fromMap(_asMap(e))).toList(),
    );
  }
}

class StoreConfig {
  const StoreConfig({
    required this.name,
    required this.enable,
    required this.params,
  });

  final String name;
  final bool enable;
  final List<StoreCredential> params;

  String? paramValue(String name) {
    for (final param in params) {
      if (param.name == name) return param.value;
    }
    return null;
  }

  StoreConfig copyWith({
    String? name,
    bool? enable,
    List<StoreCredential>? params,
  }) {
    return StoreConfig(
      name: name ?? this.name,
      enable: enable ?? this.enable,
      params: params ?? this.params,
    );
  }

  Map<String, Object?> toMap() => {
    'name': name,
    'enable': enable,
    'params': params.map((e) => e.toMap()).toList(),
  };

  factory StoreConfig.fromMap(Map<Object?, Object?> map) {
    return StoreConfig(
      name: (map['name'] ?? '').toString(),
      enable: map['enable'] != false,
      params: _asList(
        map['params'],
      ).map((e) => StoreCredential.fromMap(_asMap(e))).toList(),
    );
  }
}

class StoreCredential {
  const StoreCredential(this.name, this.value);

  final String name;
  final String value;

  StoreCredential copyWith({String? value}) =>
      StoreCredential(name, value ?? this.value);

  Map<String, Object?> toMap() => {'name': name, 'value': value};

  factory StoreCredential.fromMap(Map<Object?, Object?> map) {
    return StoreCredential(
      (map['name'] ?? '').toString(),
      (map['value'] ?? '').toString(),
    );
  }
}

class ProfilePreferences {
  const ProfilePreferences({this.updateDesc, this.apkDir});

  final String? updateDesc;
  final String? apkDir;

  ProfilePreferences copyWith({String? updateDesc, String? apkDir}) {
    return ProfilePreferences(
      updateDesc: updateDesc ?? this.updateDesc,
      apkDir: apkDir ?? this.apkDir,
    );
  }

  Map<String, Object?> toMap() => {
    if (updateDesc != null) 'updateDesc': updateDesc,
    if (apkDir != null) 'apkDir': apkDir,
  };

  factory ProfilePreferences.fromMap(Map<Object?, Object?> map) {
    return ProfilePreferences(
      updateDesc: map['updateDesc']?.toString(),
      apkDir: map['apkDir']?.toString(),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ??
      DateTime.now().millisecondsSinceEpoch;
}

Map<Object?, Object?> _asMap(Object? value) {
  if (value is Map) return value.cast<Object?, Object?>();
  return const {};
}

List<Object?> _asList(Object? value) {
  if (value is List) return value;
  return const [];
}
