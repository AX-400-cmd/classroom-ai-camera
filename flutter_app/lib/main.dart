/// 应用入口：依赖注入 + 底部两栏壳层。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:classroom_camera_app/pages/alerts_page.dart';
import 'package:classroom_camera_app/pages/camera_page.dart';
import 'package:classroom_camera_app/pages/files_page.dart';
import 'package:classroom_camera_app/pages/server_manage_page.dart';
import 'package:classroom_camera_app/pages/stats_page.dart';
import 'package:classroom_camera_app/state/alert_controller.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';
import 'package:classroom_camera_app/state/media_controller.dart';
import 'package:classroom_camera_app/widgets/wakelock_sync.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 控制器在 runApp 之前创建，避免 StatelessWidget 重建时反复 new 出新的（旧对象不会被 dispose）。
  runApp(ClassroomCameraApp(camera: CameraController()));
}

class ClassroomCameraApp extends StatelessWidget {
  const ClassroomCameraApp({super.key, required this.camera});

  final CameraController camera;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CameraController>.value(value: camera),
        ChangeNotifierProvider<MediaController>(
          create: (_) => MediaController(camera),
        ),
        ChangeNotifierProvider<AlertController>(
          create: (_) => AlertController(camera),
        ),
      ],
      child: MaterialApp(
        title: '智能课堂 AI 摄像头',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
        ),
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 放在这里而不是 main 里 await，避免读本地存档时白屏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CameraController>().init();
      context.read<AlertController>().init();
    });
  }

  void _openServers() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ServerManagePage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CameraController camera = context.watch<CameraController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('智能课堂 AI 摄像头'),
        actions: <Widget>[
          Consumer<AlertController>(
            builder: (BuildContext context, AlertController alerts, _) => Badge(
              isLabelVisible: alerts.unread > 0,
              label: Text(alerts.unread > 99 ? '99+' : '${alerts.unread}'),
              child: IconButton(
                tooltip: '行为告警',
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => setState(() => _index = 2),
              ),
            ),
          ),
          IconButton(
            tooltip: '服务器地址',
            icon: const Icon(Icons.dns_outlined),
            onPressed: _openServers,
          ),
        ],
      ),
      body: camera.ready
          ? WakelockSync(
              // 预览页 + 已连接时保持屏幕常亮；切到文件页或断线就交还系统。
              enabled: camera.isConnected && _index == 0,
              child: IndexedStack(
                index: _index,
                children: <Widget>[
                  CameraPage(
                    onOpenServers: _openServers,
                    onViewAlerts: () => setState(() => _index = 2),
                  ),
                  FilesPage(onGoConnect: () => setState(() => _index = 0)),
                  const AlertsPage(),
                  const StatsPage(),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam),
            label: '实时预览',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '录制文件',
          ),
          const NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: '行为告警',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: '课堂统计',
          ),
        ],
      ),
    );
  }
}
