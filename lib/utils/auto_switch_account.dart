import 'dart:async';

import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 自动循环切号：运行 X 小时后切换到下一个已登录账号（跳过游客账号）
abstract final class AutoSwitchAccount {
  static const _checkInterval = Duration(minutes: 1);

  static Timer? _timer;

  /// 间隔小时数，0 表示关闭
  static int get hours =>
      (GStorage.setting.get(SettingBoxKey.autoSwitchAccountHours) as num?)
          ?.toInt() ??
      0;

  /// 下一次自动切号的时间，未开启时返回 null
  static DateTime? get deadline {
    final h = hours;
    if (h <= 0) return null;
    final last =
        GStorage.setting.get(SettingBoxKey.autoSwitchAccountAt) as int?;
    if (last == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      last + h * Duration.millisecondsPerHour,
    );
  }

  /// 可切换的账号（排除账号 0 游客，按 mid 排序保证顺序稳定）
  static List<LoginAccount> get candidates =>
      Accounts.account.values.where((e) => e.isLogin && e.mid != 0).toList()
        ..sort((a, b) => a.mid.compareTo(b.mid));

  /// [reset] 为 true 时重新计时（用户修改间隔时调用）
  static Future<void> start({bool reset = false}) async {
    _timer?.cancel();
    _timer = null;
    final h = hours;
    if (h <= 0) {
      await GStorage.setting.delete(SettingBoxKey.autoSwitchAccountAt);
      return;
    }
    if (reset ||
        GStorage.setting.get(SettingBoxKey.autoSwitchAccountAt) == null) {
      await _mark();
    }
    _timer = Timer.periodic(_checkInterval, (_) => _check());
  }

  static Future<void> _mark() {
    return GStorage.setting.put(
      SettingBoxKey.autoSwitchAccountAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<void> _check() async {
    final h = hours;
    if (h <= 0) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    final last =
        GStorage.setting.get(SettingBoxKey.autoSwitchAccountAt) as int?;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last != null && now - last < h * Duration.millisecondsPerHour) {
      return;
    }
    await _mark();
    await switchNext();
  }

  /// 切换到下一个已登录账号
  static Future<void> switchNext() async {
    final list = candidates;
    if (list.length < 2) return;
    final currentMid = Accounts.main.mid;
    final index = list.indexWhere((e) => e.mid == currentMid);
    final next = list[(index + 1) % list.length];
    if (next.mid == currentMid) return;
    for (final type in AccountType.values) {
      await Accounts.set(type, next);
    }
    SmartDialog.showToast('已自动切换到 ${next.uname ?? next.mid}');
  }
}
