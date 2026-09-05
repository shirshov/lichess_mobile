import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/preloaded_data.dart';
import 'package:lichess_mobile/src/model/engine/opponent_level.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:logging/logging.dart';

final _logger = Logger('EngineWeightsService');

const _nnueDownloadUrl = 'https://lichess1.org/assets/lifat/nnue/';

const bigNetUrl =
    '$_nnueDownloadUrl/sf16-bnwfe6nndkp7wnzngay6jte7icqhb6rn.nnue';

const bigNetHash = 'bnwfe6nndkp7';

const smallNetUrl =
    '$_nnueDownloadUrl/sf16-bnwfe6nndkp7wnzngay6jte7icqhb6r2.nnue';

const smallNetHash = 'bnwfe6nndkp7';

const bigNetExpectedSize = 109 * 1024 * 1024;

const smallNetExpectedSize = 7 * 512 * 1024;

const nnueTotalSizeMB = '${(bigNetExpectedSize + smallNetExpectedSize) ~/ (1024 * 1024)}MB';

const kMaiaWeightsDirName = 'maia';

const kBundledMaiaAssetDir = 'assets/maia';

String bundledMaiaAsset(String fileName) => '$kBundledMaiaAssetDir/$fileName';

Uri maiaWeightsUrl(String fileName) => Uri.parse('https://lichess1.org/assets/lifat/maia/$fileName');

typedef NNUEFiles = ({String bigNet, String smallNet});

final stockfishNnueServiceProvider = Provider<StockfishNnueService>((Ref ref) {
  return StockfishNnueService(ref);
}, name: 'StockfishNnueServiceProvider');

class StockfishNnueService {
  StockfishNnueService(this._ref);

  final Ref _ref;

  final ValueNotifier<double> _nnueDownloadProgress = ValueNotifier(0.0);

  ValueListenable<double> get nnueDownloadProgress => _nnueDownloadProgress;

  bool get isDownloadingNNUEFiles =>
      nnueDownloadProgress.value > 0.0 && nnueDownloadProgress.value < 1.0;

  NNUEFiles get nnueFiles {
    throw UnsupportedError('NNUE files are not available on web.');
  }

  Future<bool> hasOutdatedNNUEFiles() async => false;

  Future<bool> hasNNUEFilesOnDisk() async => false;

  Future<bool> checkNNUEFiles() async => false;

  Future<bool> downloadNNUEFiles({bool inBackground = true}) async => false;

  Future<void> deleteNNUEFiles() async {}
}

final maiaWeightsServiceProvider = Provider<MaiaWeightsService>((Ref ref) {
  return MaiaWeightsService(ref);
}, name: 'MaiaWeightsServiceProvider');

class MaiaWeightsService {
  MaiaWeightsService(this._ref);

  final Ref _ref;

  final Map<MaiaRating, Future<String?>> _inFlight = {};

  final Set<MaiaRating> _verified = {};

  final ValueNotifier<double> _downloadProgress = ValueNotifier(0.0);

  ValueListenable<double> get downloadProgress => _downloadProgress;

  MaiaRating? get downloading => _inFlight.keys.firstOrNull;

  Future<bool> isAvailable(MaiaRating rating) async => rating.isBundled;

  Future<Set<MaiaRating>> availableRatings() async => const <MaiaRating>{};

  Future<({MaiaRating rating, String path})> ensureWeights(MaiaRating rating) async {
    return (rating: MaiaRating.defaultRating, path: 'web_maia_default');
  }

  Future<String?> download(MaiaRating rating) async => null;

  Future<void> deleteWeights() async {}

  Future<({int count, int bytes})> unusableWeights() async => (count: 0, bytes: 0);

  Future<void> deleteUnusableWeights() async {}
}
