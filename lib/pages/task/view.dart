import 'package:PiliPlus/common/constants.dart';
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

  @override
  void dispose() {
    _bvController.dispose();
    super.dispose();
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
}
