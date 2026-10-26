import 'package:flutter_test/flutter_test.dart';
import 'package:classroom_camera_app/main.dart';
import 'package:classroom_camera_app/pages/camera_page.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';

void main() {
  testWidgets('camera app renders', (WidgetTester tester) async {
    // ClassroomCameraApp 需要外部注入 controller（在 main() 里创建，
    // 避免 StatelessWidget 重建时反复 new）。
    await tester.pumpWidget(ClassroomCameraApp(camera: CameraController()));
    expect(find.text('智能课堂 AI 摄像头'), findsOneWidget);
    expect(find.byType(CameraPage), findsOneWidget);
  });
}
