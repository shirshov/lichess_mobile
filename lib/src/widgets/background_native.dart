import 'dart:io' show Directory, File;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/preloaded_data.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:material_ui/material_ui.dart';

const kBackgroundImageBlurFactor = 8.0;

DecorationImage buildBackgroundDecorationImage(Directory appDocumentsDirectory, BackgroundImage backgroundImage) {
  return DecorationImage(
    image: FileImage(File('${appDocumentsDirectory.path}/${backgroundImage.path}')),
    fit: BoxFit.cover,
    colorFilter: ColorFilter.mode(
      BackgroundImage.getFilterColor(BackgroundImage.getTheme(backgroundImage.seedColor).colorScheme.surface, backgroundImage.meanLuminance),
      BlendMode.srcOver,
    ),
  );
}
