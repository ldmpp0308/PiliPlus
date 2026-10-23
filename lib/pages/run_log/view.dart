import 'package:PiliPlus/utils/run_log.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

enum _RunLogFilter { all, play, switchAccount, task }

class RunLogPage extends StatefulWidget {
  const RunLogPage({super.key});

  @override
  State<RunLogPage> createState() => _RunLogPageState();
}

class _RunLogPageState extends State<RunLogPage> {
  _RunLogFilter _filter = _RunLogFilter.all;

  static const Map<_RunLogFilter, String> _filterLabels = {
    _RunLogFilter.all: '全部',
    _RunLogFilter.play: '播放',
    _RunLogFilter.switchAccount: '切号',
    _RunLogFilter.task: '任务',
  };

  bool _match(RunLogEntry entry) => switch (_filter) {
    _RunLogFilter.all => true,
    _RunLogFilter.play => entry.type == RunLogType.play,
    _RunLogFilter.switchAccount => entry.type == RunLogType.switchAccount,
    _RunLogFilter.task =>
      entry.type == RunLogType.taskStart || entry.type == RunLogType.taskEnd,
  };

  static String _dayLabel(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    return '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmClear() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空运行日志'),
        content: const Text('确定要清空全部运行日志吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '取消',
              style: TextStyle(color: ColorScheme.of(context).outline),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (res == true) {
      await RunLog.clear();
      SmartDialog.showToast('已清空');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            tooltip: '清空',
            onPressed: _confirmClear,
            icon: const Icon(Icons.delete_outline),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: RunLog.revision,
        builder: (context, _, _) {
          final entries = RunLog.entries.where(_match).toList();
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Row(
                  spacing: 8,
                  children: _RunLogFilter.values.map((filter) {
                    final selected = _filter == filter;
                    return GestureDetector(
                      onTap: () => setState(() => _filter = filter),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(16),
                          ),
                        ),
                        child: Text(
                          _filterLabels[filter]!,
                          style: TextStyle(
                            fontSize: 13,
                            color: selected
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          '暂无记录',
                          style: TextStyle(color: colorScheme.outline),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.viewPaddingOf(context).bottom + 40,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final day = _dayLabel(entry.time);
                          final showDay =
                              index == 0 ||
                              _dayLabel(entries[index - 1].time) != day;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showDay)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                                  child: Text(
                                    day,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.outline,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              _LogTile(entry: entry),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final RunLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final (Color color, IconData icon) = switch (entry.type) {
      RunLogType.play => (colorScheme.primary, Icons.play_circle_outline),
      RunLogType.switchAccount => (
        entry.success ? colorScheme.tertiary : colorScheme.error,
        Icons.swap_horiz,
      ),
      RunLogType.taskStart => (colorScheme.secondary, Icons.flag_outlined),
      RunLogType.taskEnd => (colorScheme.outline, Icons.stop_circle_outlined),
    };
    return InkWell(
      onLongPress: () => Utils.copyText(entry.line),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 42,
              child: Text(
                entry.timeText,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: colorScheme.outline,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 6),
              child: Icon(icon, size: 16, color: color),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${entry.label}  ',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    TextSpan(
                      text: entry.display,
                      style: const TextStyle(fontSize: 13, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
