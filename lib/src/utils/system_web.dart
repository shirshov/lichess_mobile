import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class System {
  const System._();

  static const instance = System._();

  Future<int?> getTotalRam() async => null;

  Future<({String package, String? version})?> getDefaultBrowser() async => null;

  Future<bool> clearUserData() async => true;
}

final androidVersionProvider = FutureProvider<AndroidBuildVersion?>((ref) async => null);
