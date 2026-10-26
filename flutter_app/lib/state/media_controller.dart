/// 录制文件列表、筛选、选择与删除。
library;

import 'package:flutter/foundation.dart';

import 'package:classroom_camera_app/core/constants.dart';
import 'package:classroom_camera_app/core/format.dart';
import 'package:classroom_camera_app/models/media_file.dart';
import 'package:classroom_camera_app/services/api_client.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';

class MediaController extends ChangeNotifier {
  MediaController(this._camera);

  final CameraController _camera;

  bool _loading = false;
  String? _error;
  List<MediaFile> _files = const <MediaFile>[];

  /// 文件名模糊搜索。
  String _keyword = '';

  /// null = 全部。
  MediaKind? _kindFilter;

  bool _selectMode = false;
  final Set<String> _selected = <String>{};

  bool get loading => _loading;
  String? get error => _error;
  bool get selectMode => _selectMode;
  Set<String> get selected => _selected;
  String get keyword => _keyword;
  MediaKind? get kindFilter => _kindFilter;

  /// 未连接时列表为空，UI 会提示先连接。
  bool get hasServer => _camera.isConnected;

  /// 过滤后的列表（按修改时间倒序）。
  List<MediaFile> get files {
    final String kw = _keyword.trim().toLowerCase();
    final List<MediaFile> result = _files.where((MediaFile f) {
      if (_kindFilter != null && f.kind != _kindFilter) return false;
      if (kw.isNotEmpty && !f.name.toLowerCase().contains(kw)) return false;
      return true;
    }).toList()
      ..sort((MediaFile a, MediaFile b) => b.mtime.compareTo(a.mtime));
    return result;
  }

  int get totalCount => _files.length;

  int get totalBytes =>
      _files.fold<int>(0, (int sum, MediaFile f) => sum + f.size);

  /// 正在录制中的文件不允许删除，UI 需禁用对应按钮。
  bool isLocked(MediaFile file) => file.recording;

  bool isSelected(String name) => _selected.contains(name);

  // ===== 数据 =====
  Future<void> refresh() async {
    if (!_camera.isConnected) {
      _files = const <MediaFile>[];
      _error = null;
      _loading = false;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _files = await _camera.api.listFiles();
      // 已删除的文件要从选中集合里剔掉，否则删除会报 404。
      final Set<String> known = _files.map((MediaFile f) => f.name).toSet();
      _selected.removeWhere((String n) => !known.contains(n));
    } catch (error) {
      _error = describeError(error,
          statusCode: error is ApiException ? error.statusCode : null);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setKeyword(String value) {
    _keyword = value;
    notifyListeners();
  }

  void setKindFilter(MediaKind? kind) {
    _kindFilter = kind;
    notifyListeners();
  }

  // ===== 选择 =====
  void enterSelectMode([String? first]) {
    _selectMode = true;
    _selected.clear();
    if (first != null) _selected.add(first);
    notifyListeners();
  }

  void exitSelectMode() {
    _selectMode = false;
    _selected.clear();
    notifyListeners();
  }

  void toggleSelected(String name) {
    if (_selected.contains(name)) {
      _selected.remove(name);
    } else {
      _selected.add(name);
    }
    notifyListeners();
  }

  void selectAllVisible() {
    for (final MediaFile f in files) {
      if (!isLocked(f)) _selected.add(f.name);
    }
    notifyListeners();
  }

  // ===== 操作 =====
  /// 删除单个文件，返回后端提示。
  Future<String> delete(String name) async {
    try {
      await _camera.api.deleteFile(name);
      _selected.remove(name);
      await refresh();
      return '已删除 $name';
    } catch (error) {
      throw ApiException(describeError(error,
          statusCode: error is ApiException ? error.statusCode : null));
    }
  }

  /// 批量删除，返回「成功数 / 总数」与首个失败原因。
  Future<DeleteResult> deleteSelected() async {
    final List<String> targets = _selected.toList(growable: false);
    if (targets.isEmpty) return const DeleteResult(0, 0, null);
    int ok = 0;
    String? firstError;
    for (final String name in targets) {
      try {
        await _camera.api.deleteFile(name);
        ok++;
        _selected.remove(name);
      } catch (error) {
        firstError ??= describeError(error,
            statusCode: error is ApiException ? error.statusCode : null);
      }
    }
    await refresh();
    return DeleteResult(ok, targets.length, firstError);
  }

  String downloadUrl(MediaFile file) =>
      _camera.api.fileUrl(file.name, inline: false);

  String playUrl(MediaFile file) => _camera.api.fileUrl(file.name);

  String posterUrl(MediaFile file) =>
      file.poster != null && file.poster!.isNotEmpty
          ? _camera.api.posterUrl(file.name)
          : '';

  /// Web 端直接把文件读进 JS 堆会炸，超过阈值时提示改用浏览器下载。
  bool tooLargeToInline(MediaFile file) =>
      file.size > kMaxInlineDownloadBytes;
}

class DeleteResult {
  const DeleteResult(this.deleted, this.total, this.firstError);

  final int deleted;
  final int total;
  final String? firstError;

  bool get allOk => firstError == null && deleted == total;
}
