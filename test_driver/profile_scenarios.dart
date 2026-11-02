// This is a command line tool, and printing is what it is for.
// ignore_for_file: avoid_print

import 'package:integration_test/integration_test_driver.dart';

/// Runs on the development machine beside `integration_test/profile_scenarios_test.dart`.
/// It prints what the app measured, and keeps it in `build/profile_scenarios.json`.
///
/// It keeps a result from a failed run too, so that one failed scenario does not
/// lose the others. The tool's exit code still says the run failed.
Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 30),
  writeResponseOnFailure: true,
  responseDataCallback: (report) async {
    await writeResponseData(report, testOutputFilename: 'profile_scenarios');
    if (report != null) print(_table(report));
  },
);

const _metrics = ['build', 'raster', 'total'];
const _columns = ['p50', 'p95', 'p99', 'max'];

/// One row per scenario and metric, in milliseconds.
String _table(Map<String, dynamic> report) {
  final scenarios = report['scenarios'] as Map<String, dynamic>;
  final nameWidth = scenarios.keys.fold(
    8,
    (width, name) => name.length > width ? name.length : width,
  );
  final lines = [
    '${report['platform']} (${report['os']}), ${report['processors']} processors, view ${report['view']}, profile mode',
    '${'scenario'.padRight(nameWidth)}  metric  frames${_columns.map((column) => column.padLeft(9)).join()}',
  ];
  for (final MapEntry(key: name, value: scenario as Map<String, dynamic>)
      in scenarios.entries) {
    for (final metric in _metrics) {
      final times = scenario[metric] as Map<String, dynamic>;
      final cells = _columns.map(
        (column) => (times[column] as num).toStringAsFixed(2).padLeft(9),
      );
      lines.add(
        '${name.padRight(nameWidth)}  ${metric.padRight(6)}  ${'${scenario['frames']}'.padLeft(6)}${cells.join()}',
      );
    }
  }
  return lines.join('\n');
}
