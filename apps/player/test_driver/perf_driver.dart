import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// Writes a timeline summary per scenario to `build/perf/SCENARIO.timeline_summary.json`.
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) return;
        for (final entry in data.entries) {
          final summary = driver.TimelineSummary.summarize(
            driver.Timeline.fromJson(entry.value as Map<String, dynamic>),
          );
          try {
            await summary.writeTimelineToFile(
              entry.key,
              destinationDirectory: 'build/perf',
              pretty: true,
              includeSummary: true,
            );
          } on StateError {
            // No frames in the window: nothing on screen changed, which is itself a result.
            await summary.writeTimelineToFile(
              entry.key,
              destinationDirectory: 'build/perf',
              pretty: true,
              includeSummary: false,
            );
          }
        }
      },
    );
