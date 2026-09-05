import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/utils/system.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'preloaded_data_native.dart' if (dart.library_html) 'preloaded_data_web.dart';
