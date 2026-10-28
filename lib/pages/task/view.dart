import 'dart:async';

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models_new/fav/fav_folder/list.dart';
import 'package:PiliPlus/services/shutdown_timer_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/auto_switch_account.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/run_log.dart';
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
    ('任务收藏夹', Constants.favCId),
  ];

  /// 旧的任务收藏夹 ID，用于迁移老数据
  static const int _oldFavCId = 3940948099;

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

  /// 收藏夹入口默认隐藏，连续点击「选择收藏夹」6 次后显示
  bool _folderEntryVisible = false;
  int _folderTapCount = 0;
  Timer? _folderTapTimer;

  int? _folderDuration;
  bool _durationLoading = false;
  int _durationReqId = 0;
  final Map<int, int> _durationCache = {};

  /// 自动切号间隔小时数，0 表示关闭
  int _switchHours = 0;

  @override
  void initState() {
    super.initState();
    _folders = _loadFolders();
    _folderEntryVisible =
        GStorage.setting.get(SettingBoxKey.taskFavManageUnlocked) == true;
    _switchHours = AutoSwitchAccount.hours;
    _bvController.text =
        GStorage.setting.get(SettingBoxKey.taskSelfTestBv) as String? ?? '';
    _bvController.addListener(_onBvChanged);
    if (_bvController.text.trim().isNotEmpty) {
      _onBvChanged();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshDuration());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _folderTapTimer?.cancel();
    _bvController
      ..removeListener(_onBvChanged)
      ..dispose();
    super.dispose();
  }

  void _onFolderEntryTap() {
    if (_folderEntryVisible) return;
    _folderTapTimer?.cancel();
    _folderTapCount++;
    if (_folderTapCount >= 6) {
      _folderTapCount = 0;
      setState(() => _folderEntryVisible = true);
      GStorage.setting.put(SettingBoxKey.taskFavManageUnlocked, true);
      SmartDialog.showToast('收藏夹管理已解锁');
      return;
    }
    _folderTapTimer = Timer(const Duration(seconds: 2), () {
      _folderTapCount = 0;
    });
  }

  Future<void> _refreshDuration() async {
    if (_folders.isEmpty) {
      if (mounted) {
        setState(() {
          _folderDuration = null;
          _durationLoading = false;
        });
      }
      return;
    }
    final mediaId = _folders[_selected].$2;
    final cached = _durationCache[mediaId];
    if (cached != null) {
      setState(() {
        _folderDuration = cached;
        _durationLoading = false;
      });
      return;
    }
    final reqId = ++_durationReqId;
    setState(() {
      _durationLoading = true;
      _folderDuration = null;
    });
    final total = await _fetchFolderDuration(mediaId);
    if (!mounted || reqId != _durationReqId) return;
    if (total != null) {
      _durationCache[mediaId] = total;
    }
    setState(() {
      _durationLoading = false;
      _folderDuration = total;
    });
  }

  /// 拉取收藏夹内全部视频并累计时长（秒）
  Future<int?> _fetchFolderDuration(int mediaId) async {
    const ps = 20;
    var total = 0;
    for (var pn = 1; pn <= 50; pn++) {
      final res = await FavHttp.userFavFolderDetail(
        mediaId: mediaId,
        pn: pn,
        ps: ps,
      );
      final data = res.dataOrNull;
      if (data == null) return null;
      final medias = data.medias;
      if (medias == null || medias.isEmpty) break;
      for (final item in medias) {
        total += item.duration ?? 0;
      }
      if (data.hasMore != true) break;
    }
    return total;
  }

  /// 建议倍速：让播放列表循环一圈刚好 5 分 20 秒，保留一位小数
  double? get _recommendedSpeed {
    final total = _folderDuration;
    if (total == null || total <= 0) return null;
    var speed = (total / 320 * 10).round() / 10;
    if (speed < 1) speed = 1;
    return speed;
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '$h小时$m分$s秒';
    if (m > 0) return '$m分$s秒';
    return '$s秒';
  }

  String _speedText(double speed) => speed == speed.truncateToDouble()
      ? speed.toInt().toString()
      : speed.toStringAsFixed(1);

  List<(String, int)> _loadFolders() {
    // 2.0 起收藏夹仅保留「任务收藏夹」，老数据强制收敛一次
    if (GStorage.setting.get(SettingBoxKey.taskFavListV2) != true) {
      final defaults = List.of(_defaultFolders);
      GStorage.setting.put(
        SettingBoxKey.taskFavList,
        defaults.map((e) => '${e.$2}|${e.$1}').toList(),
      );
      GStorage.setting.put(SettingBoxKey.taskFavListV2, true);
      return defaults;
    }
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
    // 任务收藏夹 ID 变更：老数据迁移为新 ID，保留自定义收藏夹
    var migrated = false;
    final migratedList = list.map((e) {
      if (e.$2 == _oldFavCId) {
        migrated = true;
        return (e.$1, Constants.favCId);
      }
      return e;
    }).toList();
    if (migrated) {
      GStorage.setting.put(
        SettingBoxKey.taskFavList,
        migratedList.map((e) => '${e.$2}|${e.$1}').toList(),
      );
    }
    return migratedList;
  }

  void _saveFolders() {
    GStorage.setting.put(
      SettingBoxKey.taskFavList,
      _folders.map((e) => '${e.$2}|${e.$1}').toList(),
    );
  }

  Future<void> _addFolder() async {
    final source = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('添加收藏夹'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'mine'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.folder_open),
              title: Text('从我的收藏夹选择'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'manual'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_outlined),
              title: Text('手动输入收藏夹 ID'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || source == null) return;
    if (source == 'manual') {
      await _addFolderManually();
    } else {
      await _pickMyFolder();
    }
  }

  /// 从当前账号的收藏夹列表中选择
  Future<void> _pickMyFolder() async {
    if (!Accounts.main.isLogin) {
      SmartDialog.showToast('请先登录');
      return;
    }
    final res = await FavHttp.userfavFolder(
      pn: 1,
      ps: 50,
      mid: Accounts.main.mid,
    );
    if (!mounted) return;
    final list = res.dataOrNull?.list;
    if (list == null) {
      SmartDialog.showToast('收藏夹获取失败：$res');
      return;
    }
    if (list.isEmpty) {
      SmartDialog.showToast('暂无收藏夹');
      return;
    }
    final selected = await showDialog<FavFolderInfo>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择收藏夹'),
        children: [
          for (final item in list)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: Text(item.title),
                subtitle: Text('${item.mediaCount} 个内容'),
              ),
            ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    if (_folders.any((e) => e.$2 == selected.id)) {
      SmartDialog.showToast('该收藏夹已添加');
      return;
    }
    setState(() {
      _folders = [
        ..._folders,
        (selected.title, selected.id),
      ];
      _selected = _folders.length - 1;
    });
    _saveFolders();
    _refreshDuration();
  }

  Future<void> _addFolderManually() async {
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
    _refreshDuration();
  }

  void _removeFolder(int index) {
    final title = _folders[index].$1;
    setState(() {
      _folders = List.of(_folders)..removeAt(index);
      // 删除项在选中项之前时，索引前移保持选中同一个收藏夹
      if (_selected > index) _selected--;
      if (_selected >= _folders.length) {
        _selected = _folders.isEmpty ? 0 : _folders.length - 1;
      }
    });
    _saveFolders();
    _refreshDuration();
    SmartDialog.showToast('已删除 $title');
  }

  void _resetFolders() {
    setState(() {
      _folders = List.of(_defaultFolders);
      _selected = 0;
    });
    _saveFolders();
    _refreshDuration();
  }

  Future<void> _editSwitchHours() async {
    final controller = TextEditingController(
      text: _switchHours > 0 ? '$_switchHours' : '',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自动循环切号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '运行指定小时后自动切换到下一个已登录账号，未登录的游客账号会自动跳过。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '间隔小时数',
                hintText: '填 0 表示关闭',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final hours = result <= 0 ? 0 : result;
    await GStorage.setting.put(SettingBoxKey.autoSwitchAccountHours, hours);
    await AutoSwitchAccount.start(reset: true);
    // 自动切号与定时关闭互斥：开启自动切号后取消定时关闭
    if (hours > 0) {
      shutdownTimerService.reset();
    }
    if (!mounted) return;
    setState(() => _switchHours = hours);
    SmartDialog.showToast(hours > 0 ? '已开启：每 $hours 小时自动切号' : '已关闭自动切号');
  }

  Future<void> _editShutdown() async {
    if (_switchHours > 0) {
      SmartDialog.showToast('已开启自动切号，定时关闭不可用');
      return;
    }
    const options = [0, 60, 120, 180, 240, 300];
    var type = shutdownTimerService.shutdownType;
    // 默认 5 小时
    var selected = shutdownTimerService.durationInMinutes > 0
        ? shutdownTimerService.durationInMinutes
        : ShutdownTimerService.defaultDurationInMinutes;
    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final colorScheme = ColorScheme.of(context);
          return AlertDialog(
            title: const Text('定时关闭'),
            contentPadding: const EdgeInsets.only(top: 12),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      '到点后可选择暂停视频或退出APP。',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final minutes in options)
                    ListTile(
                      dense: true,
                      onTap: () =>
                          setDialogState(() => selected = minutes),
                      title: Text(minutes == 0 ? '关闭' : '${minutes ~/ 60} 小时'),
                      trailing: selected == minutes
                          ? Icon(
                              size: 20,
                              Icons.done,
                              color: colorScheme.primary,
                            )
                          : null,
                    ),
                  ListTile(
                    dense: true,
                    onTap: () async {
                      final custom =
                          await ShutdownTimerService.showCustomHoursDialog(
                            context,
                            initialMinutes: selected,
                          );
                      if (custom == null || !context.mounted) return;
                      setDialogState(() => selected = custom);
                    },
                    title: Text(
                      options.contains(selected)
                          ? '自定义'
                          : '自定义（${selected ~/ 60} 小时）',
                    ),
                    trailing: options.contains(selected)
                        ? null
                        : Icon(
                            size: 20,
                            Icons.done,
                            color: colorScheme.primary,
                          ),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('到点动作', style: TextStyle(fontSize: 13)),
                        ...ShutdownType.values.map(
                          (e) => ChoiceChip(
                            label: Text(e.label),
                            selected: type == e,
                            onSelected: (_) =>
                                setDialogState(() => type = e),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    shutdownTimerService.startShutdown(result, type: type);
    if (!mounted) return;
    setState(() {});
  }

  void _onBvChanged() {
    // 记住自测 BV，下次进入任务页自动带出
    GStorage.setting.put(
      SettingBoxKey.taskSelfTestBv,
      _bvController.text.trim(),
    );
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
    GStorage.setting.put(SettingBoxKey.taskSelfTestBv, bv);
    final speed = _recommendedSpeed;
    if (speed != null) {
      GStorage.video.put(VideoBoxKey.playSpeedDefault, speed);
    }
    RunLog.startTask(favName: _folders[_selected].$1);
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
        actions: _folderEntryVisible
            ? [
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
              ]
            : null,
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onFolderEntryTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('选择收藏夹', style: labelStyle),
                    ),
                  ),
                ),
                if (_folderEntryVisible)
                  TextButton.icon(
                    onPressed: _addFolder,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加收藏夹'),
                  ),
              ],
            ),
          ),
          if (_folders.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('暂无收藏夹，连点上方「选择收藏夹」6 次可添加', style: labelStyle),
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
              trailing:
                  _folderEntryVisible && _folders[i].$2 != Constants.favCId
                  ? IconButton(
                      tooltip: '删除收藏夹',
                      onPressed: () => _removeFolder(i),
                      icon: const Icon(Icons.delete_outline),
                    )
                  : null,
              onTap: () {
                setState(() => _selected = i);
                _refreshDuration();
              },
            ),
          ListTile(
            leading: Icon(Icons.timer_outlined, color: outline),
            title: const Text('定时关闭'),
            subtitle: Text(
              _switchHours > 0
                  ? '已开启自动切号，暂不可用'
                  : shutdownTimerService.durationInMinutes > 0
                  ? '${shutdownTimerService.durationInMinutes ~/ 60} 小时后'
                        '${shutdownTimerService.shutdownType.label}'
                  : '未开启',
              style: labelStyle,
            ),
            trailing: Text(
              _switchHours > 0
                  ? '不可用'
                  : shutdownTimerService.durationInMinutes > 0
                  ? '${shutdownTimerService.durationInMinutes ~/ 60} 小时'
                  : '设置',
              style: TextStyle(
                color: _switchHours > 0 ? outline : colorScheme.primary,
              ),
            ),
            onTap: _editShutdown,
          ),
          ListTile(
            leading: Icon(Icons.swap_horiz, color: outline),
            title: const Text('自动循环切号'),
            subtitle: Text(
              _switchHours > 0
                  ? '每 $_switchHours 小时切换到下一个已登录账号（跳过游客）'
                  : '未开启',
              style: labelStyle,
            ),
            trailing: Text(
              _switchHours > 0 ? '$_switchHours 小时' : '设置',
              style: TextStyle(color: colorScheme.primary),
            ),
            onTap: _editSwitchHours,
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
          if (_folders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                _durationLoading
                    ? '正在统计当前收藏夹总时长…'
                    : _recommendedSpeed != null
                    ? '当前收藏夹总时长${_formatDuration(_folderDuration!)}，建议${_speedText(_recommendedSpeed!)}倍速播放'
                    : '当前收藏夹总时长统计失败',
                style: TextStyle(fontSize: 13, color: colorScheme.primary),
              ),
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
