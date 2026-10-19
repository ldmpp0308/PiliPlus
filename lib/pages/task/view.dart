import 'dart:async';

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class TaskPage extends StatefulWidget {
  const TaskPage({super.key});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  /// 默认收藏夹：(名称, mediaId)
  static const List<(String, int)> _defaultFolders = [
    ('收藏夹 A', Constants.favAId),
    ('收藏夹 B', Constants.favBId),
    ('收藏夹 C', Constants.favCId),
  ];

  /// 用户自定义的收藏夹列表
  List<(String, int)> _folders = const [];

  int _selected = 0;
  final TextEditingController _bvController = TextEditingController();

  Timer? _debounce;
  String? _queriedBv;
  bool _bvLoading = false;
  String? _bvTitle;
  int? _bvView;
  String? _bvError;

  @override
  void initState() {
    super.initState();
    _folders = _loadFolders();
    _bvController.addListener(_onBvChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _bvController
      ..removeListener(_onBvChanged)
      ..dispose();
    super.dispose();
  }

  List<(String, int)> _loadFolders() {
    final raw = GStorage.setting.get(SettingBoxKey.taskFavList) as List?;
    if (raw == null) {
      return List.of(_defaultFolders);
    }
    final list = <(String, int)>[];
    for (final item in raw) {
      if (item is! String) continue;
      final index = item.indexOf('|');
      if (index < 0) continue;
      final mediaId = int.tryParse(item.substring(0, index));
      if (mediaId == null) continue;
      list.add((item.substring(index + 1), mediaId));
    }
    return list;
  }

  void _saveFolders() {
    GStorage.setting.put(
      SettingBoxKey.taskFavList,
      _folders.map((e) => '${e.$2}|${e.$1}').toList(),
    );
  }

  Future<void> _addFolder() async {
    final idController = TextEditingController();
    final titleController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加收藏夹'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '收藏夹 ID',
                hintText: '例如 4020281993',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: '名称（可选）',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final mediaId = int.tryParse(idController.text.trim());
    final title = titleController.text.trim();
    idController.dispose();
    titleController.dispose();
    if (mediaId == null) {
      SmartDialog.showToast('收藏夹 ID 需为数字');
      return;
    }
    if (!mounted) return;
    setState(() {
      _folders = [
        ..._folders,
        (title.isEmpty ? '收藏夹 ${_folders.length + 1}' : title, mediaId),
      ];
      _selected = _folders.length - 1;
    });
    _saveFolders();
  }

  void _removeFolder(int index) {
    setState(() {
      _folders = List.of(_folders)..removeAt(index);
      if (_selected >= _folders.length) {
        _selected = _folders.isEmpty ? 0 : _folders.length - 1;
      }
    });
    _saveFolders();
  }

  void _resetFolders() {
    setState(() {
      _folders = List.of(_defaultFolders);
      _selected = 0;
    });
    _saveFolders();
  }

  void _onBvChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _queryBv);
  }

  Future<void> _queryBv() async {
    final String bv = _bvController.text.trim();
    if (bv == _queriedBv) return;
    if (bv.isEmpty) {
      if (!mounted) return;
      setState(() {
        _queriedBv = null;
        _bvLoading = false;
        _bvTitle = null;
        _bvView = null;
        _bvError = null;
      });
      return;
    }
    if (!IdUtils.bvRegexExact.hasMatch(bv)) {
      if (!mounted) return;
      setState(() {
        _queriedBv = bv;
        _bvLoading = false;
        _bvTitle = null;
        _bvView = null;
        _bvError = 'BV 号格式不正确';
      });
      return;
    }
    setState(() {
      _queriedBv = bv;
      _bvLoading = true;
      _bvTitle = null;
      _bvView = null;
      _bvError = null;
    });
    final res = await VideoHttp.videoIntro(bvid: bv);
    if (!mounted || _queriedBv != bv) return;
    final data = res.dataOrNull;
    setState(() {
      _bvLoading = false;
      _bvTitle = data?.title;
      _bvView = data?.stat?.view;
      _bvError = data == null ? res.toString() : null;
    });
  }

  void _startTask() {
    if (_folders.isEmpty) return;
    final String bv = _bvController.text.trim();
    Get.toNamed(
      '/favDetail',
      parameters: {
        'heroTag': 'taskFav${_folders[_selected].$2}',
        'mediaId': '${_folders[_selected].$2}',
        'autoplay': 'true',
        if (bv.isNotEmpty) 'selfTestBv': bv,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final outline = colorScheme.outline;
    final labelStyle = TextStyle(fontSize: 13, color: outline);
    return Scaffold(
      primary: false,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('任务'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '恢复默认收藏夹',
            onPressed: _resetFolders,
            icon: const Icon(Icons.settings_backup_restore),
          ),
          IconButton(
            tooltip: '添加收藏夹',
            onPressed: _addFolder,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('选择收藏夹', style: labelStyle),
          ),
          if (_folders.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('暂无收藏夹，点击右上角「+」添加', style: labelStyle),
            ),
          for (int i = 0; i < _folders.length; i++)
            ListTile(
              selected: _selected == i,
              selectedTileColor: colorScheme.secondaryContainer,
              leading: Icon(
                _selected == i
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: _selected == i ? colorScheme.primary : outline,
              ),
              title: Text(_folders[i].$1),
              trailing: IconButton(
                tooltip: '删除',
                onPressed: () => _removeFolder(i),
                icon: const Icon(Icons.delete_outline),
              ),
              onTap: () => setState(() => _selected = i),
            ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('自测 BV（可选，收藏夹播完后自动续播）', style: labelStyle),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _bvController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: '例如 BV1xx411c7mD',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _buildBvInfo(colorScheme),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: FilledButton(
              onPressed: _startTask,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('开始任务'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBvInfo(ColorScheme colorScheme) {
    if (_bvLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            '查询中…',
            style: TextStyle(fontSize: 13, color: colorScheme.outline),
          ),
        ],
      );
    }
    if (_bvError != null) {
      return Text(
        _bvError!,
        style: TextStyle(fontSize: 13, color: colorScheme.error),
      );
    }
    if (_bvTitle == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _bvTitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '播放量：${NumUtils.numFormat(_bvView)}',
            style: TextStyle(fontSize: 13, color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
