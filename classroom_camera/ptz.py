"""PTZ 控制适配层。

这里先接入 ONVIF ContinuousMove，作为真正云台控制的第一版。
AutoPTZ 本身支持 ONVIF / VISCA / NDI 等后端；本 MVP 先把跟踪框偏移量转换为
ONVIF pan/tilt 速度命令，后续可替换为 AutoPTZ 更完整的控制器。
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass
class PTZConfig:
    enabled: bool = False
    backend: str = "onvif"
    host: str = ""
    port: int = 80
    username: str = ""
    password: str = ""
    pan_gain: float = 0.35
    tilt_gain: float = 0.30
    dead_zone: float = 0.12
    max_speed: float = 0.45


class BasePTZController:
    def connect(self) -> None:
        return None

    def move_by_error(self, error_x: float, error_y: float) -> None:
        return None

    def stop(self) -> None:
        return None

    def close(self) -> None:
        self.stop()


class NullPTZController(BasePTZController):
    pass


class ONVIFPTZController(BasePTZController):
    def __init__(self, config: PTZConfig):
        self.config = config
        self.client = None
        self.ptz = None
        self.profile_token = None

    def connect(self) -> None:
        try:
            from onvif import ONVIFClient
        except Exception as exc:
            raise RuntimeError("缺少 onvif-python 依赖，请先安装 requirements.txt") from exc

        self.client = ONVIFClient(
            self.config.host,
            self.config.port,
            self.config.username or None,
            self.config.password or None,
        )
        media = self.client.media()
        self.ptz = self.client.ptz()
        profiles = media.GetProfiles()
        if not profiles:
            raise RuntimeError("ONVIF 摄像头没有可用 media profile")
        self.profile_token = profiles[0].token

    def move_by_error(self, error_x: float, error_y: float) -> None:
        if not self.ptz or not self.profile_token:
            return
        cfg = self.config
        if abs(error_x) < cfg.dead_zone and abs(error_y) < cfg.dead_zone:
            self.stop()
            return

        pan = max(-cfg.max_speed, min(cfg.max_speed, error_x * cfg.pan_gain))
        # 图像坐标 y 向下为正；ONVIF tilt 通常向上为正，所以取反。
        tilt = max(-cfg.max_speed, min(cfg.max_speed, -error_y * cfg.tilt_gain))
        velocity = {"PanTilt": {"x": pan, "y": tilt}}
        self.ptz.ContinuousMove(ProfileToken=self.profile_token, Velocity=velocity)

    def stop(self) -> None:
        if self.ptz and self.profile_token:
            try:
                self.ptz.Stop(ProfileToken=self.profile_token, PanTilt=True, Zoom=True)
            except Exception:
                pass


def create_ptz_controller(config: Optional[PTZConfig]) -> BasePTZController:
    if not config or not config.enabled:
        return NullPTZController()
    if config.backend.lower() == "onvif":
        controller = ONVIFPTZController(config)
        controller.connect()
        return controller
    raise RuntimeError(f"暂不支持 PTZ 后端：{config.backend}")
