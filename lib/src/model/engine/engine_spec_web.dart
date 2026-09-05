import 'package:lichess_mobile/src/model/engine/engine_slot.dart';
import 'package:meta/meta.dart';

enum StockfishFlavor {
  sf16,
  latestNoNNUE,
  variant,
}

sealed class EngineSpec {
  const EngineSpec();

  EngineSlot get slot;
  String get label;
}

@immutable
final class StockfishSpec extends EngineSpec {
  const StockfishSpec.sf16()
    : slot = EngineSlot.sf16,
      flavor = StockfishFlavor.sf16,
      bigNetPath = null,
      smallNetPath = null;

  const StockfishSpec.latest({required String this.bigNetPath, required String this.smallNetPath})
    : slot = EngineSlot.sfLatest,
      flavor = StockfishFlavor.latestNoNNUE;

  const StockfishSpec.fairy()
    : slot = EngineSlot.fairy,
      flavor = StockfishFlavor.variant,
      bigNetPath = null,
      smallNetPath = null;

  @override
  final EngineSlot slot;

  final StockfishFlavor flavor;

  @override
  String get label => flavor.name;

  final String? bigNetPath;
  final String? smallNetPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockfishSpec &&
          other.slot == slot &&
          other.bigNetPath == bigNetPath &&
          other.smallNetPath == smallNetPath;

  @override
  int get hashCode => Object.hash(slot, bigNetPath, smallNetPath);

  @override
  String toString() => 'StockfishSpec(${flavor.name})';
}

final class Lc0Spec extends EngineSpec {
  const Lc0Spec();

  @override
  EngineSlot get slot => EngineSlot.lc0;

  @override
  String get label => 'lc0';

  @override
  bool operator ==(Object other) => other is Lc0Spec;

  @override
  int get hashCode => (Lc0Spec).hashCode;

  @override
  String toString() => 'Lc0Spec()';
}
