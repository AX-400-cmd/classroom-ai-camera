"""跟踪与 PTZ 控制适配层。

后续在这里接入 AutoPTZ。MVP 阶段保持接口稳定，先让固定摄像头录制可用。
"""

from dataclasses import dataclass
from typing import Optional


@dataclass
class TrackingTarget:
    x: int
    y: int
    width: int
    height: int


class TrackerAdapter:
    def select_target(self, frame, x: int, y: int) -> Optional[TrackingTarget]:
        """预留：根据用户点击选择教师目标。"""
        return None

    def update(self, frame) -> Optional[TrackingTarget]:
        """预留：返回当前目标框。"""
        return None

    def move_ptz(self, target: TrackingTarget, frame_size: tuple[int, int]) -> None:
        """预留：调用 AutoPTZ/ONVIF 控制云台。"""
        return None
