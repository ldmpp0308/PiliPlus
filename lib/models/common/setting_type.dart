import 'package:PiliPlus/pages/setting/models/extra_settings.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/models/play_settings.dart';
import 'package:PiliPlus/pages/setting/models/privacy_settings.dart';
import 'package:PiliPlus/pages/setting/models/recommend_settings.dart';
import 'package:PiliPlus/pages/setting/models/style_settings.dart';
import 'package:PiliPlus/pages/setting/models/video_settings.dart';

enum SettingType {
  privacySetting('隐私设置'),
  recommendSetting('推荐流设置'),
  videoSetting('音视频设置'),
  playSetting('播放器设置'),
  styleSetting('外观设置'),
  extraSetting('其它设置'),
  webdavSetting('WebDAV 设置'),
  about('关于'),
  ;

  final String title;
  const SettingType(this.title);

  List<SettingsModel> get settings => switch (this) {
    .privacySetting => privacySettings,
    .recommendSetting => recommendSettings,
    .videoSetting => videoSettings,
    // 仅展示与播放相关的设置项，其余设置项代码保留、仅隐藏
    .playSetting => playSettings
        .where((e) => _playerSettingTitles.contains(e.title))
        .toList(),
    .styleSetting => styleSettings,
    .extraSetting => extraSettings,
    _ => throw UnimplementedError(),
  };
}

/// 播放器设置中需要保留展示的设置项标题
const Set<String> _playerSettingTitles = {
  '弹幕开关',
  '启用点击弹幕',
  '倍速设置',
  '自动播放',
  '全屏显示锁定按钮',
  '全屏显示截图按钮',
  '全屏显示电池电量',
  '双击快退/快进',
  '左右侧滑动调节亮度/音量',
  '中间滑动进入/退出全屏',
  '播放器音量',
  '最高音量',
  '双击快进/快退时长',
  '滑动快进/快退时长',
  'SuperChat (醒目留言) 显示类型',
  '全屏 SC 大小',
  '自动退出全屏',
  '后台播放',
  '后台画中画',
  '画中画不加载弹幕',
  '全屏手势反向',
  '全屏展示点赞/投币/收藏等操作按钮',
  '后台音频服务',
  '播放顺序',
};
