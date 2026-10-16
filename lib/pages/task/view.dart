import 'dart:async';

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class TaskPage extends StatefulWidget {
  const TaskPage({super.key});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  static const List<(String, int)> _folders = [
    ('收藏夹 A', Constants.favAId),
    ('收藏夹 B', Constants.favBId),
    ('收藏夹 C', Constants.favCId),
  ];

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
              subtitle: Text('ID: ${_folders[i].$2}', style: labelStyle),
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
