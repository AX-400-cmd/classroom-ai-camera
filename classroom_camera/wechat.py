"""微信小程序订阅消息推送。

设计原则：**永不打断主流程**。
摄像头采集循环每帧都会调用 `push_alert()`，所以这里所有网络请求、文件读写、
JSON 解析都必须自己吃掉异常——配置没填、网络不通、token 过期、额度用完，
都只记一行日志就返回，绝不能把异常抛回采集线程。

订阅消息要点（微信规则）：
- 一次性订阅：用户每授权一次（勾选模板并点允许），开发者只获得 1 次下发额度；
- 若用户在弹窗里勾选了「总是保持以上选择」，之后再次调用
  `wx.requestSubscribeMessage` 不会弹窗，直接返回 accept，每次调用都能再攒额度。
  所以小程序端每次打开都调一次授权并上报，后端按 quota 计数。
"""

from __future__ import annotations

import json
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API_BASE = "https://api.weixin.qq.com"
TOKEN_URL = API_BASE + "/cgi-bin/token"
SESSION_URL = API_BASE + "/sns/jscode2session"
SEND_URL = API_BASE + "/cgi-bin/message/subscribe/send"

# 微信接口返回码：这些表示"用户侧原因"，重试也没用，直接扣额度并记日志
FATAL_ERRCODES = {
    40003: "openid 无效",
    43101: "用户拒绝接收（已取消订阅）",
    47003: "模板参数不准确（字段类型或长度不匹配）",
    40037: "template_id 不正确",
    48001: "API 功能未授权",
}

DEFAULT_CONFIG: dict = {
    "enabled": False,
    "appid": "",
    "secret": "",
    "template_id": "",
    # 模板字段名 -> 取值来源。来源可选：
    #   title / detail / time / duration / count
    # 字段名与类型（thing/character_string/time/...）必须和小程序后台选用的模板一致
    "template_fields": {
        "thing1": "title",
        "thing2": "detail",
        "time3": "time",
    },
    "page": "pages/alerts/alerts",
    "min_interval": 60.0,
    "store": "subscribers.json",
}

# 各类字段的长度限制（微信规定，超了会报 47003）
FIELD_LIMITS = {"thing": 20, "character_string": 32, "phrase": 5}

DETAIL_TEXT = {
    "phone": "玩手机",
    "sleep": "打瞌睡",
    "attention": "注意力不集中",
}


def _field_limit(key: str) -> int:
    """从模板字段名推断长度上限：thing1 -> 20，character_string2 -> 32。"""
    for prefix, limit in FIELD_LIMITS.items():
        if key.startswith(prefix):
            return limit
    return 0


def _clip(value: str, key: str) -> str:
    limit = _field_limit(key)
    text = str(value)
    if limit and len(text) > limit:
        text = text[: max(0, limit - 1)] + "…"
    return text


class WeChatNotifier:
    """读取 wechat.json，维护 access_token 与订阅者额度，发送订阅消息。"""

    def __init__(self, config_path: str | Path = "", enabled: bool = False):
        self.config_path = Path(config_path) if config_path else None
        self.enabled = enabled
        self.cfg: dict = dict(DEFAULT_CONFIG)
        self.cfg["template_fields"] = dict(DEFAULT_CONFIG["template_fields"])
        self._store_path: Path | None = None
        self._lock = threading.Lock()
        self._token = ""
        self._token_expire = 0.0
        self._last_send = 0.0
        self._load()

    # ---------- 配置 ----------

    def _load(self) -> None:
        if not self.config_path:
            return
        try:
            raw = json.loads(self.config_path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            print(f"[wechat] 未找到配置文件 {self.config_path}，微信推送关闭")
            self.enabled = False
            return
        except (json.JSONDecodeError, OSError) as exc:
            print(f"[wechat] 配置文件读取失败：{exc}，微信推送关闭")
            self.enabled = False
            return
        self.cfg.update(raw or {})
        self.cfg.setdefault("template_fields", dict(DEFAULT_CONFIG["template_fields"]))
        # 敏感项支持环境变量注入：配置文件里留空或写成 ENV 占位时生效。
        # 这样 AppSecret 不必明文落盘，服务化部署时用 Environment= 注入即可。
        for key, env_name in (("appid", "WECHAT_APPID"),
                              ("secret", "WECHAT_APP_SECRET"),
                              ("template_id", "WECHAT_TEMPLATE_ID")):
            value = os.environ.get(env_name, "").strip()
            if value and str(self.cfg.get(key) or "").strip().upper() in ("", "ENV"):
                self.cfg[key] = value
        if raw.get("enabled") is not None:
            self.enabled = bool(raw["enabled"]) and self.enabled
        store = str(self.cfg.get("store") or "subscribers.json")
        # 相对路径挂在配置文件同级，避免依赖进程工作目录
        self._store_path = (Path(store) if Path(store).is_absolute()
                            else self.config_path.parent / store)

    @property
    def configured(self) -> bool:
        def filled(value) -> bool:
            text = str(value or "").strip()
            # "ENV" 是占位符，表示"等环境变量注入"；没注入就是没配置
            return bool(text) and text.upper() != "ENV"
        return (filled(self.cfg.get("appid"))
                and filled(self.cfg.get("secret"))
                and filled(self.cfg.get("template_id")))

    @property
    def active(self) -> bool:
        return bool(self.enabled) and self.configured

    def status(self) -> dict:
        subs = self._read_subscribers()
        return {
            "enabled": bool(self.enabled),
            "configured": self.configured,
            "active": self.active,
            "appid": str(self.cfg.get("appid") or ""),
            "template_id": str(self.cfg.get("template_id") or ""),
            "subscribers": len(subs),
            "quota_total": sum(int(v.get("quota", 0)) for v in subs.values()),
            "last_error": self._last_error(),
        }

    _err = ""

    def _last_error(self) -> str:
        return self._err

    # ---------- 订阅者 ----------

    def _read_subscribers(self) -> dict:
        if not self._store_path:
            return {}
        try:
            data = json.loads(self._store_path.read_text(encoding="utf-8"))
            return data if isinstance(data, dict) else {}
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            return {}

    def _write_subscribers(self, data: dict) -> None:
        if not self._store_path:
            return
        try:
            self._store_path.parent.mkdir(parents=True, exist_ok=True)
            self._store_path.write_text(
                json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        except OSError as exc:
            print(f"[wechat] 订阅者写入失败：{exc}")

    def add_subscriber(self, openid: str, quota: int = 0, note: str = "") -> dict:
        if not openid:
            return {"ok": False, "message": "openid 为空"}
        with self._lock:
            subs = self._read_subscribers()
            item = subs.get(openid) or {"ts": time.time(), "quota": 0}
            item["quota"] = int(item.get("quota", 0)) + max(0, int(quota))
            item["ts"] = time.time()
            if note:
                item["note"] = note
            subs[openid] = item
            self._write_subscribers(subs)
            return {"ok": True, "openid": openid, "quota": item["quota"]}

    def remove_subscriber(self, openid: str) -> bool:
        with self._lock:
            subs = self._read_subscribers()
            if openid not in subs:
                return False
            subs.pop(openid, None)
            self._write_subscribers(subs)
            return True

    # ---------- 微信 API ----------

    def _http_json(self, url: str, data: bytes | None = None,
                   timeout: float = 6.0) -> dict:
        req = urllib.request.Request(
            url, data=data,
            headers={"Content-Type": "application/json; charset=utf-8"} if data else {})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def code2session(self, code: str) -> dict:
        """小程序端 wx.login 拿到的 code 换 openid。"""
        if not (self.cfg.get("appid") and self.cfg.get("secret")):
            return {"ok": False, "message": "未配置 appid/secret"}
        query = urllib.parse.urlencode({
            "appid": self.cfg["appid"],
            "secret": self.cfg["secret"],
            "js_code": code,
            "grant_type": "authorization_code",
        })
        try:
            res = self._http_json(f"{SESSION_URL}?{query}")
        except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
            self._err = f"code2session 失败：{exc}"
            return {"ok": False, "message": self._err}
        if res.get("errcode"):
            self._err = f"code2session 错误 {res['errcode']}：{res.get('errmsg')}"
            return {"ok": False, "message": self._err}
        return {"ok": True, "openid": res.get("openid", ""),
                "unionid": res.get("unionid", "")}

    def _access_token(self) -> str:
        now = time.time()
        if self._token and now < self._token_expire:
            return self._token
        query = urllib.parse.urlencode({
            "grant_type": "client_credential",
            "appid": self.cfg.get("appid", ""),
            "secret": self.cfg.get("secret", ""),
        })
        try:
            res = self._http_json(f"{TOKEN_URL}?{query}")
        except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
            self._err = f"获取 access_token 失败：{exc}"
            print(f"[wechat] {self._err}")
            return ""
        if res.get("errcode") or not res.get("access_token"):
            self._err = f"获取 access_token 错误：{res.get('errmsg') or res}"
            print(f"[wechat] {self._err}")
            return ""
        self._token = str(res["access_token"])
        # 提前 5 分钟过期，避免边界时刻拿到已失效 token
        self._token_expire = now + max(60.0, float(res.get("expires_in", 7200)) - 300)
        return self._token

    def send(self, openid: str, data: dict, page: str = "") -> dict:
        """发送一条订阅消息。data 为 {模板字段名: 值}。"""
        if not self.active:
            return {"ok": False, "message": "微信推送未启用或未配置完整"}
        token = self._access_token()
        if not token:
            return {"ok": False, "message": self._err or "access_token 获取失败"}
        payload = {
            "touser": openid,
            "template_id": self.cfg["template_id"],
            "page": page or self.cfg.get("page") or "",
            "miniprogram_state": self.cfg.get("state") or "formal",
            "lang": "zh_CN",
            "data": {k: {"value": _clip(v, k)} for k, v in data.items()},
        }
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        try:
            res = self._http_json(f"{SEND_URL}?access_token={token}", data=body)
        except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
            self._err = f"订阅消息发送失败：{exc}"
            print(f"[wechat] {self._err}")
            return {"ok": False, "message": self._err}
        errcode = res.get("errcode", 0)
        if errcode:
            self._err = f"订阅消息错误 {errcode}：{res.get('errmsg')}"
            if errcode in FATAL_ERRCODES:
                self._err += f"（{FATAL_ERRCODES[errcode]}）"
            print(f"[wechat] {self._err}")
            return {"ok": False, "message": self._err}
        self._err = ""
        return {"ok": True}

    # ---------- 告警推送 ----------

    def _build_data(self, alert) -> dict:
        """把 AlertEvent 映射成模板字段。"""
        detail = str(getattr(alert, "detail", "") or getattr(alert, "kind", "") or "")
        title = "课堂行为告警"
        sources = {
            "title": title,
            "detail": DETAIL_TEXT.get(detail, "注意力不集中"),
            "time": time.strftime("%Y-%m-%d %H:%M", time.localtime(alert.ts)),
            "duration": f"持续 {int(round(getattr(alert, 'seconds', 0)))} 秒",
            "count": f"画面 {getattr(alert, 'persons', 0) or ''}",
        }
        fields = self.cfg.get("template_fields") or {}
        data = {}
        for key, src in fields.items():
            value = sources.get(str(src), "")
            if value == "":
                continue
            data[str(key)] = value
        if not data:  # 兜底：至少把 detail 塞进去，避免微信报 47003
            data["thing1"] = "课堂行为告警"
        return data

    def push_test(self) -> dict:
        """发一条测试订阅消息，用于验证模板字段是否匹配。"""
        if not self.configured:
            return {"ok": False, "message": "wechat.json 未配置完整（appid/secret/template_id）"}
        if not self.enabled:
            return {"ok": False, "message": "wechat.json 里 enabled 未开启"}
        subs = self._read_subscribers()
        targets = [oid for oid, item in subs.items() if int(item.get("quota", 0)) > 0]
        if not targets:
            return {"ok": False, "message": "还没有有效订阅者（请在小程序里先点「开启告警推送」授权）"}
        data = {
            "title": "测试告警",
            "detail": "这是一条测试消息",
            "time": time.strftime("%Y-%m-%d %H:%M"),
            "duration": "持续 0 秒",
        }
        fields = self.cfg.get("template_fields") or {}
        payload = {str(k): data.get(str(v), "") for k, v in fields.items()}
        if not payload:
            payload["thing1"] = "测试告警"
        # 测试消息不走 min_interval 节流，直接发
        ok_count = 0
        for openid in targets[:1]:
            res = self.send(openid, payload, page=self.cfg.get("page") or "")
            if res.get("ok"):
                ok_count += 1
                with self._lock:
                    cur = self._read_subscribers()
                    if openid in cur:
                        cur[openid]["quota"] = max(0, int(cur[openid].get("quota", 0)) - 1)
                        self._write_subscribers(cur)
        if ok_count:
            return {"ok": True, "message": f"测试消息已发送（剩余额度已扣 1）"}
        return {"ok": False, "message": self._err or "发送失败"}

    def push_alert(self, alert) -> int:
        """给所有订阅者推送该告警。返回成功条数。

        调用方（采集线程）不需要 try/except —— 这里保证不抛异常。
        """
        if not self.active:
            return 0
        try:
            data = self._build_data(alert)
            page = self.cfg.get("page") or "pages/alerts/alerts"
            with self._lock:
                subs = self._read_subscribers()
                targets = [(oid, int(item.get("quota", 0)))
                           for oid, item in subs.items()
                           if int(item.get("quota", 0)) > 0]
            # 没有订阅者就别消耗节流窗口，否则真正有人订阅后的第一条告警会被误节流
            if not targets:
                return 0

            interval = float(self.cfg.get("min_interval") or 60.0)
            now = time.monotonic()
            if interval > 0 and now - self._last_send < interval:
                return 0
            self._last_send = now

            sent = 0
            for openid, quota in targets:
                res = self.send(openid, data, page=page)
                # 无论成败都扣额度：一次性订阅授权只能消耗一次，
                # 失败通常是模板/用户侧问题，重试仍会失败
                with self._lock:
                    cur = self._read_subscribers()
                    if openid in cur:
                        cur[openid]["quota"] = max(
                            0, int(cur[openid].get("quota", 0)) - 1)
                        self._write_subscribers(cur)
                if res.get("ok"):
                    sent += 1
            if sent:
                print(f"[wechat] 已推送告警 {getattr(alert, 'id', '')} 给 {sent} 位订阅者")
            return sent
        except Exception as exc:  # 兜底：绝不让采集线程挂掉
            self._err = f"推送异常：{exc}"
            print(f"[wechat] {self._err}")
            return 0
