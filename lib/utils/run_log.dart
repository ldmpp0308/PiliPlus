import 'dart:async';
import 'dart:convert';

import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/foundation.dart';

enum RunLogType { play, switchAccount, taskStart, taskEnd }

class RunLogEntry {
  const RunLogEntry({
    required this.time,
    required this.type,
    this.account,
    this.mid,
    this.from,
    this.fromMid,
    this.to,
    this.toMid,
    this.success = true,
    this.title,
    this.part,
    this.bvid,
    this.cid,
    this.reason,
    this.favName,
    this.playCount,
    this.switchCount,
    this.count = 1,
  });

  final DateTime time;
  final RunLogType type;

  /// 事件发生的账号
  final String? account;
  final int? mid;

  /// 切号：来源账号
  final String? from;
  final int? fromMid;

  /// 切号：目标账号
  final String? to;
  final int? toMid;
  final bool success;

  /// 播放
  final String? title;
  final String? part;
  final String? bvid;
  final int? cid;

  /// 任务结束
  final String? reason;
  final String? favName;
  final int? playCount;
  final int? switchCount;

  /// 合并后的播放次数
  final int count;

  String get timeText =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  String get label => switch (type) {
    RunLogType.play => '播放',
    RunLogType.switchAccount => '切号',
    RunLogType.taskStart => '任务开始',
    RunLogType.taskEnd => '任务结束',
  };

  /// 一行摘要（用于列表与复制）
  String get display => switch (type) {
    RunLogType.play =>
      '《${title ?? bvid ?? '未知视频'}》'
          '${part?.isNotEmpty == true ? ' $part' : ''}'
          '${account?.isNotEmpty == true ? ' · $account' : ''}'
          '${count > 1 ? ' ×$count' : ''}',
    RunLogType.switchAccount =>
      '${from ?? '未知账号'} → ${to ?? '未知账号'}${success ? '' : ' 失败'}',
    RunLogType.taskStart =>
      '「${favName ?? '任务收藏夹'}」'
          '${account?.isNotEmpty == true ? ' · $account' : ''}',
    RunLogType.taskEnd =>
      '播放 ${playCount ?? 0} 个视频 · 切号 ${switchCount ?? 0} 次'
          '${reason?.isNotEmpty == true ? ' · ${reason!}' : ''}',
  };

  String get line => '${timeText.padRight(6)}${label.padRight(6)}$display';

  Map<String, dynamic> toJson() => {
    'ts': time.millisecondsSinceEpoch,
    't': type.name,
    if (account != null) 'acc': account,
    if (mid != null) 'mid': mid,
    if (from != null) 'from': from,
    if (fromMid != null) 'fmid': fromMid,
    if (to != null) 'to': to,
    if (toMid != null) 'tmid': toMid,
    if (!success) 'fail': true,
    if (title != null) 'title': title,
    if (part != null) 'part': part,
    if (bvid != null) 'bvid': bvid,
    if (cid != null) 'cid': cid,
    if (reason != null) 'reason': reason,
    if (favName != null) 'fav': favName,
    if (playCount != null) 'play': playCount,
    if (switchCount != null) 'sw': switchCount,
    if (count > 1) 'n': count,
  };

  static RunLogEntry fromJson(Map<String, dynamic> json) => RunLogEntry(
    time: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
    type: RunLogType.values.byName(json['t'] as String),
    account: json['acc'] as String?,
    mid: json['mid'] as int?,
    from: json['from'] as String?,
    fromMid: json['fmid'] as int?,
    to: json['to'] as String?,
    toMid: json['tmid'] as int?,
    success: json['fail'] != true,
    title: json['title'] as String?,
    part: json['part'] as String?,
    bvid: json['bvid'] as String?,
    cid: json['cid'] as int?,
    reason: json['reason'] as String?,
    favName: json['fav'] as String?,
    playCount: json['play'] as int?,
    switchCount: json['sw'] as int?,
    count: json['n'] as int? ?? 1,
  );

  /// 账号展示名：昵称(UID)
  static String accountLabel(Account? account) {
    if (account is LoginAccount) {
      final uname = account.uname;
      if (uname == null || uname.isEmpty) return '${account.mid}';
      return '$uname(${account.mid})';
    }
    return '游客';
  }
}

/// 播放 / 切号 / 任务运行日志
abstract final class RunLog {
  static const int maxEntries = 300;

  /// 同账号 + 同 cid 的播放记录在该时间窗内合并为一条
  static const Duration _mergeWindow = Duration(minutes: 10);
  static const Duration _flushDelay = Duration(seconds: 2);

  static final List<RunLogEntry> _entries = [];

  /// 日志变化通知（详情页与「我的」页入口共用）
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Timer? _flushTimer;
  static bool _loaded = false;

  /// 进行中的任务会话
  static Map<String, Object?>? _session;

  static List<RunLogEntry> get entries {
    _ensureLoaded();
    return _entries;
  }

  static bool get isTaskRunning {
    _ensureLoaded();
    return _session != null;
  }

  static void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final raw = GStorage.setting.get(SettingBoxKey.runLog);
    if (raw is List) {
      for (final line in raw) {
        if (line is! String) continue;
        try {
          _entries.add(
            RunLogEntry.fromJson(jsonDecode(line) as Map<String, dynamic>),
          );
        } catch (_) {}
      }
    }
    final session = GStorage.setting.get(SettingBoxKey.runLogTask);
    if (session is String) {
      try {
        _session = jsonDecode(session) as Map<String, Object?>;
      } catch (_) {}
    }
  }

  static void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDelay, flush);
  }

  static Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await GStorage.setting.put(
      SettingBoxKey.runLog,
      _entries.map((e) => jsonEncode(e.toJson())).toList(),
    );
    final session = _session;
    if (session == null) {
      if (GStorage.setting.get(SettingBoxKey.runLogTask) != null) {
        await GStorage.setting.delete(SettingBoxKey.runLogTask);
      }
    } else {
      await GStorage.setting.put(
        SettingBoxKey.runLogTask,
        jsonEncode(session),
      );
    }
  }

  /// 追加一条日志，返回是否写入
  static bool _add(RunLogEntry entry) {
    _ensureLoaded();
    if (_entries.isNotEmpty) {
      final last = _entries.first;
      // 同一秒内连续相同事件直接丢弃
      if (last.type == entry.type &&
          last.time.second == entry.time.second &&
          last.time.minute == entry.time.minute &&
          last.display == entry.display) {
        return false;
      }
    }
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    _scheduleFlush();
    revision.value++;
    return true;
  }

  static void _bump(String key) {
    final session = _session;
    if (session == null) return;
    session[key] = ((session[key] as int?) ?? 0) + 1;
    _scheduleFlush();
  }

  /// 播放事件（播放器真正开播时调用）
  static void play({
    String? title,
    String? part,
    int? cid,
    String? bvid,
  }) {
    _ensureLoaded();
    final account = Accounts.main;
    final label = RunLogEntry.accountLabel(account);
    final now = DateTime.now();

    // 同账号 + 同 cid 10 分钟内合并为一条，并累加次数
    if (cid != null) {
      final index = _entries.indexWhere(
        (e) =>
            e.type == RunLogType.play &&
            e.cid == cid &&
            e.mid == account.mid &&
            now.difference(e.time) < _mergeWindow,
      );
      if (index != -1) {
        final old = _entries.removeAt(index);
        _entries.insert(
          0,
          RunLogEntry(
            time: now,
            type: RunLogType.play,
            account: label,
            mid: account.mid,
            title: title ?? old.title,
            part: part ?? old.part,
            bvid: bvid ?? old.bvid,
            cid: cid,
            count: old.count + 1,
          ),
        );
        _scheduleFlush();
        revision.value++;
        _bump('play');
        return;
      }
    }

    final added = _add(
      RunLogEntry(
        time: now,
        type: RunLogType.play,
        account: label,
        mid: account.mid,
        title: title,
        part: part,
        bvid: bvid,
        cid: cid,
      ),
    );
    if (added) _bump('play');
  }

  /// 切号（自动 / 手动）
  static void switchAccount({
    required Account? from,
    required Account to,
    required bool success,
  }) {
    _ensureLoaded();
    _add(
      RunLogEntry(
        time: DateTime.now(),
        type: RunLogType.switchAccount,
        from: RunLogEntry.accountLabel(from),
        fromMid: from?.mid,
        to: RunLogEntry.accountLabel(to),
        toMid: to.mid,
        success: success,
      ),
    );
    _bump('switch');
  }

  /// 任务开始
  static void startTask({required String favName}) {
    _ensureLoaded();
    if (_session != null) {
      endTask('重新开始任务');
    }
    final account = Accounts.main;
    final now = DateTime.now();
    _session = {
      'fav': favName,
      'acc': RunLogEntry.accountLabel(account),
      'mid': account.mid,
      'start': now.millisecondsSinceEpoch,
      'play': 0,
      'switch': 0,
    };
    _add(
      RunLogEntry(
        time: now,
        type: RunLogType.taskStart,
        account: RunLogEntry.accountLabel(account),
        mid: account.mid,
        favName: favName,
      ),
    );
    _scheduleFlush();
  }

  /// 任务结束，[reason] 为结束原因
  static void endTask(String reason) {
    _ensureLoaded();
    final session = _session;
    if (session == null) return;
    _session = null;
    _add(
      RunLogEntry(
        time: DateTime.now(),
        type: RunLogType.taskEnd,
        account: session['acc'] as String?,
        mid: session['mid'] as int?,
        favName: session['fav'] as String?,
        playCount: session['play'] as int? ?? 0,
        switchCount: session['switch'] as int? ?? 0,
        reason: reason,
      ),
    );
    _scheduleFlush();
  }

  /// 上次任务未正常结束（App 被杀 / 崩溃）时补记
  static void restoreUnfinished() {
    _ensureLoaded();
    if (_session == null) return;
    endTask('异常中断（App 已退出）');
    unawaited(flush());
  }

  static Future<void> clear() async {
    _ensureLoaded();
    _entries.clear();
    await flush();
    revision.value++;
  }

  /// 最近一条日志摘要
  static String? get latestSummary {
    _ensureLoaded();
    if (_entries.isEmpty) return null;
    final latest = _entries.first;
    return '${latest.timeText} ${latest.label} ${latest.display}';
  }
}
