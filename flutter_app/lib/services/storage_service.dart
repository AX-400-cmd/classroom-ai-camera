/// 本地持久化：服务器地址档案与设置项。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:classroom_camera_app/core/constants.dart';
import 'package:classroom_camera_app/models/server_profile.dart';

/// 存储 key 统一加 `cc.` 前缀，避免与其它数据混淆。
class StorageKeys {
  static const String servers = 'cc.servers.v1';
  static const String lastBaseUrl = 'cc.server.last';
  static const String autoConnect = 'cc.settings.auto_connect';
  static const String autoReconnect = 'cc.settings.auto_reconnect';
  static const String drawOverlay = 'cc.settings.draw_overlay';
  static const String rawFrame = 'cc.settings.raw_frame';
  // 告警相关
  static const String alertNotify = 'cc.settings.alert_notify';
  static const String alertSound = 'cc.settings.alert_sound';
  static const String alertDnd = 'cc.settings.alert_dnd';
  static const String detectPhone = 'cc.settings.detect_phone';
  static const String detectSleep = 'cc.settings.detect_sleep';
}

class StorageService {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _store async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// 注意：必须返回**可增长**列表——upsertServer/removeServer 会对返回值
  /// 原地 removeWhere/insert，固定长度列表会抛
  /// "Unsupported operation: Cannot remove from a fixed-length list"。
  Future<List<ServerProfile>> loadServers() async {
    final SharedPreferences prefs = await _store;
    final String? raw = prefs.getString(StorageKeys.servers);
    if (raw == null || raw.isEmpty) {
      return kDefaultServerUrls
          .map((String url) => ServerProfile(baseUrl: url))
          .toList();
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <ServerProfile>[];
      final List<ServerProfile> list = decoded
          .whereType<Map<String, dynamic>>()
          .map(ServerProfile.fromJson)
          .where((ServerProfile p) => p.baseUrl.isNotEmpty)
          .toList()
        ..sort(_byLastUsedDesc);
      return list;
    } catch (_) {
      // 存档损坏时退回默认值，不要让 APP 起不来。
      return kDefaultServerUrls
          .map((String url) => ServerProfile(baseUrl: url))
          .toList();
    }
  }

  /// 新增或更新（同一 baseUrl 覆盖），最多保留 kMaxServerProfiles 条。
  Future<void> upsertServer(ServerProfile profile) async {
    final List<ServerProfile> list = await loadServers();
    list.removeWhere((ServerProfile p) => p.baseUrl == profile.baseUrl);
    list.insert(0, profile);
    if (list.length > kMaxServerProfiles) {
      list.removeRange(kMaxServerProfiles, list.length);
    }
    await _saveServers(list);
  }

  Future<void> removeServer(String id) async {
    final List<ServerProfile> list = await loadServers();
    list.removeWhere((ServerProfile p) => p.id == id);
    await _saveServers(list);
  }

  Future<void> renameServer(String id, String name) async {
    final List<ServerProfile> list = await loadServers();
    for (int i = 0; i < list.length; i++) {
      if (list[i].id == id) list[i] = list[i].copyWith(name: name);
    }
    await _saveServers(list);
  }

  Future<void> _saveServers(List<ServerProfile> list) async {
    final SharedPreferences prefs = await _store;
    list.sort(_byLastUsedDesc);
    await prefs.setString(
      StorageKeys.servers,
      jsonEncode(list.map((ServerProfile p) => p.toJson()).toList(growable: false)),
    );
  }

  Future<String?> loadLastBaseUrl() async {
    final SharedPreferences prefs = await _store;
    return prefs.getString(StorageKeys.lastBaseUrl);
  }

  Future<void> saveLastBaseUrl(String url) async {
    final SharedPreferences prefs = await _store;
    await prefs.setString(StorageKeys.lastBaseUrl, url);
  }

  Future<bool> loadBool(String key, {bool fallback = true}) async {
    final SharedPreferences prefs = await _store;
    return prefs.getBool(key) ?? fallback;
  }

  Future<void> saveBool(String key, bool value) async {
    final SharedPreferences prefs = await _store;
    await prefs.setBool(key, value);
  }

  static int _byLastUsedDesc(ServerProfile a, ServerProfile b) {
    final DateTime at = a.lastUsed ?? DateTime.fromMillisecondsSinceEpoch(0);
    final DateTime bt = b.lastUsed ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bt.compareTo(at);
  }
}
