import 'dart:math';

import 'package:dartchess/dartchess.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';

const _latestBigNNUE = 'web_stockfish_big_nnue';
const _latestSmallNNUE = 'web_stockfish_small_nnue';

/// Maximum number of CPU cores available for engine use.
const maxEngineCores = 2;

/// How much of a device's RAM engines may hold, in MB, given its [physicalMemoryInMb].
int engineMaxMemoryFor(int physicalMemoryInMb) => (physicalMemoryInMb / 16).ceil();

const _nnueDownloadUrl = '$kLichessCDNHost/assets/lifat/nnue/';

/// URL to download the latest big NNUE network.
final bigNetUrl = Uri.parse('$_nnueDownloadUrl$_latestBigNNUE');

/// SHA256 hash (first 12 digits) of the latest big NNUE network.
final bigNetHash = _latestBigNNUE.substring(3, 15);

/// URL to download the latest small NNUE network.
final smallNetUrl = Uri.parse('$_nnueDownloadUrl$_latestSmallNNUE');

/// SHA256 hash (first 12 digits) of the latest small NNUE network.
final smallNetHash = _latestSmallNNUE.substring(3, 15);

/// Approximate size in bytes of the big NNUE file (~109MB).
const bigNetExpectedSize = 109 * 1024 * 1024;

/// Approximate size in bytes of the small NNUE file (~3.5MB).
const smallNetExpectedSize = 7 * 512 * 1024;

/// Total expected NNUE download size formatted as a human-readable string (e.g. "113MB").
const nnueTotalSizeMB = '${(bigNetExpectedSize + smallNetExpectedSize) ~/ (1024 * 1024)}MB';

/// Where the Maia networks that do not ship with the app are downloaded from.
const _maiaDownloadUrl = '$kLichessCDNHost/assets/lifat/maia/';

const kMaiaWeightsDirName = 'maia';
const kBundledMaiaAssetDir = 'assets/maia';

String bundledMaiaAsset(String fileName) => '$kBundledMaiaAssetDir/$fileName';

Uri maiaWeightsUrl(String fileName) => Uri.parse('$_maiaDownloadUrl$fileName');

final _sfVersionPattern = RegExp(r'Stockfish\s+(\d+)');

Eval? pickBestEval({
  required LocalEval? localEval,
  required ClientEval? savedEval,
  required ExternalEval? serverEval,
}) {
  if (localEval?.threatMode == true) {
    return localEval;
  }

  return switch (savedEval) {
    CloudEval() => savedEval,
    final LocalEval eval => localEval != null && localEval.isBetter(eval) ? localEval : eval,
    null => localEval ?? serverEval,
  };
}

ClientEval? pickBestClientEval({
  required LocalEval? localEval,
  required ClientEval? savedEval,
}) {
  final eval =
      pickBestEval(localEval: localEval, savedEval: savedEval, serverEval: null) as ClientEval?;

  return eval;
}

String? engineShortLabel(String? engineName) {
  if (engineName == null) return null;
  if (engineName.startsWith('Fairy-Stockfish')) {
    return 'Fairy SF';
  }
  final match = _sfVersionPattern.firstMatch(engineName);
  if (match == null) return null;
  return 'SF ${match.group(1)}';
}

Position threatModePosition(Position position) => position.copyWith(
  turn: position.turn.opposite,
  halfmoves: position.halfmoves + 1,
  fullmoves: position.turn == Side.black ? position.fullmoves + 1 : position.fullmoves,
);

const officialStockfishVariants = {Variant.standard, Variant.chess960, Variant.fromPosition};

extension FairyVariantExtension on Variant {
  String get fairy => switch (this) {
    Variant.standard => 'chess',
    Variant.chess960 => 'chess',
    Variant.fromPosition => 'chess',
    Variant.antichess => 'antichess',
    Variant.kingOfTheHill => 'kingofthehill',
    Variant.threeCheck => '3check',
    Variant.atomic => 'atomic',
    Variant.horde => 'horde',
    Variant.racingKings => 'racingkings',
    Variant.crazyhouse => 'crazyhouse',
  };
}
