import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/db/secure_storage.dart';
import 'package:lichess_mobile/src/model/auth/auth_storage.dart';
import 'package:lichess_mobile/src/model/auth/auth_user.dart';
import 'package:lichess_mobile/src/model/engine/engine_utils.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/utils/string.dart';
import 'package:package_info_plus/package_info_plus.dart';

typedef PreloadedData = ({
  PackageInfo packageInfo,
  BaseDeviceInfo deviceInfo,
  AuthUser? authUser,
  String sri,
  int engineMaxMemoryInMb,
  dynamic appDocumentsDirectory,
  dynamic appSupportDirectory,
});

final preloadedDataProvider = FutureProvider<PreloadedData>((Ref ref) async {
  final authStorage = ref.read(authStorageProvider);

  final (
    pInfo,
    deviceInfo,
    sri,
    authUser,
    physicalMemory,
  ) = await (
    PackageInfo.fromPlatform(),
    DeviceInfoPlugin().deviceInfo,
    _readOrCreateSri(),
    authStorage.read(),
    System.instance.getTotalRam(),
  ).wait;

  final token = authUser?.token;
  if (token != null) {
    final userAgent = makeUserAgent(pInfo, deviceInfo, sri, null);
    final client = DefaultClient(ref.read(httpClientFactoryProvider)(), userAgent: userAgent);
    client
        .postReadJson(lichessUri('/api/token/test'), mapper: (json) => json, body: token)
        .timeout(const Duration(seconds: 5))
        .then((data) {
          final isValid = data[token] != null;
          if (!isValid) {
            authStorage.delete();
          }
        })
        .catchError((_) {})
        .whenComplete(() {
          client.close();
        });
  }

  return (
    packageInfo: pInfo,
    deviceInfo: deviceInfo,
    authUser: authUser,
    sri: sri,
    engineMaxMemoryInMb: engineMaxMemoryFor(physicalMemory ?? 256),
    appDocumentsDirectory: null,
    appSupportDirectory: null,
  );
}, name: 'PreloadedDataProvider');

Future<String> _readOrCreateSri() async {
  try {
    final storedSri = await SecureStorage.instance.read(key: kSRIStorageKey);
    if (storedSri != null) return storedSri;
    final newSri = genRandomString(12);
    await SecureStorage.instance.write(key: kSRIStorageKey, value: newSri);
    return newSri;
  } on PlatformException catch (_) {
    await SecureStorage.instance.deleteAll();
    return genRandomString(12);
  }
}
