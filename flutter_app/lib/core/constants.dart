/// 全局常量：轮询间隔、超时、退避策略、默认地址。
library;

/// 帧轮询间隔。200ms 太密，Chrome 单域名并发上限约 6，慢响应会排队雪崩。
const Duration kFrameInterval = Duration(milliseconds: 250);

/// 出现取帧失败后的降频间隔：弱网时别继续 250ms 猛刷。
const Duration kFrameSlowInterval = Duration(milliseconds: 1000);

/// 状态轮询间隔。
const Duration kStatusInterval = Duration(seconds: 2);

/// 帧请求超时。手机 Wi-Fi 偶发卡顿很常见，1.5s 太激进会频繁误判断线。
const Duration kFrameTimeout = Duration(seconds: 4);

/// 状态请求超时。
const Duration kStatusTimeout = Duration(seconds: 5);

/// 指令请求超时。
const Duration kActionTimeout = Duration(seconds: 5);

/// 重连退避：min(1s * 2^(n-1), 8s) → 1/2/4/8/8…
const Duration kReconnectBaseDelay = Duration(seconds: 1);
const Duration kReconnectMaxDelay = Duration(seconds: 8);

/// status 连续失败多少次判定为断线。
const int kStatusFailThreshold = 3;

/// 帧连续失败多少次判定为断线。达到阈值后还会先用 /status 探活，
/// 服务仍在响应就当作瞬时抖动，不算断线。
const int kFrameFailThreshold = 6;

/// 告警增量轮询间隔。后端已做冷却，3 秒足够及时且不至于刷请求。
const Duration kAlertInterval = Duration(seconds: 3);

/// 同一人同类告警在 APP 端的最短通知间隔（后端 60s 冷却之外的兜底）。
/// 别设太长：测试告警也是同一个 key，太长会导致点了测试却没反应。
const Duration kAlertNotifyThrottle = Duration(seconds: 60);

/// 全局通知节流：窗口内最多弹这么多条，防刷屏。
const Duration kAlertNotifyWindow = Duration(seconds: 30);
const int kAlertNotifyMaxInWindow = 3;

/// 自动重连最多尝试次数，超过则进入 failed 停止重试，避免无限转圈。
const int kMaxReconnectAttempts = 8;

/// Web 端直接把文件读进 JS 堆的阈值，超过则交给浏览器下载。
const int kMaxInlineDownloadBytes = 25 * 1024 * 1024;

/// 地址档案最多保留条数。
const int kMaxServerProfiles = 12;

/// 首次启动时预置的地址。127.0.0.1 用于本机验证，可绕开 Chrome 私有网络访问限制。
const List<String> kDefaultServerUrls = <String>[
  'http://192.168.3.3:8765',
  'http://127.0.0.1:8765',
];
