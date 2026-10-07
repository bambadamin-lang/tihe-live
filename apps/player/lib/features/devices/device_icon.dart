import 'package:flutter/widgets.dart';

import '../../core/theme/app_icons.dart';

/// The icon for a device's platform, wherever devices are listed.
IconData deviceIcon(String platform) => switch (platform) {
  'windows' || 'macos' => AppIcons.laptop,
  'android' || 'ios' => AppIcons.phone,
  _ => AppIcons.desktop,
};
