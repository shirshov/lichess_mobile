class EngineDiagnostics {
  const EngineDiagnostics({
    required this.phase,
    required this.step,
    required this.elapsed,
    required this.looksStuck,
    this.lastError,
  });

  EngineDiagnostics.stockfish(dynamic diagnostics)
    : phase = '',
      step = '',
      elapsed = Duration.zero,
      looksStuck = false,
      lastError = null;

  EngineDiagnostics.lc0(dynamic diagnostics)
    : phase = '',
      step = '',
      elapsed = Duration.zero,
      looksStuck = false,
      lastError = null;

  final String phase;
  final String step;
  final Duration elapsed;
  final bool looksStuck;
  final String? lastError;

  @override
  String toString() {
    final buffer = StringBuffer(
      'phase=$phase${step.isEmpty ? '' : ' step=$step'} for ${elapsed.inMilliseconds}ms',
    );
    if (looksStuck) buffer.write(' (STUCK)');
    if (lastError != null) buffer.write('; native error: $lastError');
    return buffer.toString();
  }
}
