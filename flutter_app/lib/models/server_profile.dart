/// 服务器地址档案 + 地址规范化。
library;

class ServerProfile {
  ServerProfile({
    required this.baseUrl,
    String? name,
    DateTime? lastUsed,
    String? id,
    String? token,
  })  : id = id ?? baseUrl,
        name = name ?? '',
        lastUsed = lastUsed,
        token = (token ?? '').trim();

  /// 用规范化后的地址做稳定 ID，天然去重。
  final String id;

  /// 用户备注，例如"教室讲台 PC"。
  final String name;
  final String baseUrl;
  final DateTime? lastUsed;

  /// 该服务的访问令牌（对应后端 `--api-token` / `CLASSROOM_API_TOKEN`）。
  ///
  /// 令牌绑定在地址上而非全局：连不同教室的服务各自带各自的令牌。
  /// 留空表示后端未开启鉴权（受信任的局域网自用），此时 APP 不发送 Authorization 头。
  final String token;

  String get displayName => name.isEmpty ? baseUrl : name;

  bool get hasToken => token.isNotEmpty;

  ServerProfile copyWith({String? name, DateTime? lastUsed, String? token}) {
    return ServerProfile(
      baseUrl: baseUrl,
      name: name ?? this.name,
      lastUsed: lastUsed ?? this.lastUsed,
      id: id,
      token: token ?? this.token,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'lastUsed': lastUsed?.toIso8601String(),
        if (token.isNotEmpty) 'token': token,
      };

  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    final String base = (json['baseUrl'] ?? '').toString();
    DateTime? used;
    final String? raw = json['lastUsed']?.toString();
    if (raw != null && raw.isNotEmpty) used = DateTime.tryParse(raw);
    return ServerProfile(
      baseUrl: base,
      name: (json['name'] ?? '').toString(),
      lastUsed: used,
      id: (json['id'] ?? base).toString(),
      token: (json['token'] ?? '').toString(),
    );
  }
}

/// 把用户输入规范化成 `http://host:port`（无尾斜杠）。非法输入返回 null。
///
/// 用户常常只输入 `192.168.3.3:8765` 或末尾多打个斜杠，这里统一补齐。
String? normalizeBaseUrl(String input) {
  String s = input.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'http://$s';
  final Uri? uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  final int port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  return '${uri.scheme}://${uri.host}:$port';
}
