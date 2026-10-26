import argparse
import sys
import time
from pathlib import Path

import cv2
from PySide6.QtCore import QTimer
from PySide6.QtGui import QImage, QPixmap
from PySide6.QtWidgets import QApplication, QLabel, QMainWindow, QPushButton, QVBoxLayout, QWidget

from .capture import CameraCapture


class MainWindow(QMainWindow):
    def __init__(self, source: str, output_dir: str):
        super().__init__()
        self.setWindowTitle("智能课堂 AI 摄像头 MVP")
        self.preview = QLabel("正在打开摄像头…")
        self.preview.setMinimumSize(800, 450)
        self.preview.setScaledContents(True)
        self.toggle = QPushButton("开始录制")
        self.toggle.clicked.connect(self.toggle_recording)
        layout = QVBoxLayout()
        layout.addWidget(self.preview)
        layout.addWidget(self.toggle)
        container = QWidget()
        container.setLayout(layout)
        self.setCentralWidget(container)
        self.camera = CameraCapture(source, output_dir)
        self.recording = False
        self.last_frame = None
        self.camera.open()
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update_frame)
        self.timer.start(30)

    def update_frame(self):
        ok, frame = self.camera.read()
        if not ok:
            self.preview.setText("视频源读取失败")
            return
        self.last_frame = frame
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        image = QImage(rgb.data, rgb.shape[1], rgb.shape[0], rgb.strides[0], QImage.Format_RGB888)
        self.preview.setPixmap(QPixmap.fromImage(image))

    def toggle_recording(self):
        if self.last_frame is None:
            self.preview.setText("还没有读取到视频画面，请稍后再试。")
            return
        if not self.recording:
            height, width = self.last_frame.shape[:2]
            path = self.camera.start_recording((width, height))
            self.toggle.setText(f"停止录制（{path.name}）")
            self.recording = True
        else:
            self.camera.stop_recording()
            self.toggle.setText("开始录制")
            self.recording = False

    def closeEvent(self, event):
        self.camera.close()
        event.accept()


def save_snapshot(source: str, output_dir: str) -> Path:
    camera = CameraCapture(source, output_dir)
    camera.open()
    try:
        for _ in range(10):
            ok, frame = camera.read()
            if ok:
                break
            time.sleep(0.05)
        else:
            raise RuntimeError("无法读取摄像头画面")
        out = Path(output_dir)
        out.mkdir(parents=True, exist_ok=True)
        path = out / "snapshot.jpg"
        cv2.imwrite(str(path), frame)
        return path
    finally:
        camera.close()


def record_seconds(source: str, output_dir: str, seconds: float) -> Path:
    camera = CameraCapture(source, output_dir)
    camera.open()
    try:
        ok, frame = camera.read()
        if not ok:
            raise RuntimeError("无法读取摄像头画面")
        height, width = frame.shape[:2]
        path = camera.start_recording((width, height))
        deadline = time.time() + seconds
        while time.time() < deadline:
            camera.read()
            time.sleep(0.03)
        return path
    finally:
        camera.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="0")
    parser.add_argument("--output", default="recordings")
    parser.add_argument("--snapshot", action="store_true", help="保存一张摄像头截图后退出")
    parser.add_argument("--record-seconds", type=float, default=0, help="录制指定秒数后退出")
    args = parser.parse_args()
    try:
        if args.snapshot:
            print(save_snapshot(args.source, args.output))
            return 0
        if args.record_seconds > 0:
            print(record_seconds(args.source, args.output, args.record_seconds))
            return 0
        app = QApplication(sys.argv)
        window = MainWindow(args.source, args.output)
    except RuntimeError as exc:
        print(exc, file=sys.stderr)
        return 1
    window.show()
    window.raise_()
    window.activateWindow()
    return app.exec()
