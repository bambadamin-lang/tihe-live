import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_player/core/api/models.dart';
import 'package:tihe_player/core/providers.dart';

import 'support/fakes.dart';

class _CountingCatalog extends FakeCatalog {
  final queries = <String>[];

  @override
  Future<List<SearchHit>> search(String query, {String? courseId}) async {
    queries.add(query);
    return super.search(query, courseId: courseId);
  }
}

/// Search is debounced so typing a word costs one request, not one per letter — the server
/// normalises and ranks Persian text, which is not free, and a phone on a weak network pays
/// for every request.
void main() {
  testWidgets('typing a word sends one search, for the final text', (tester) async {
    final catalog = _CountingCatalog();
    final container = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(catalog)],
    );
    addTearDown(container.dispose);

    // A search field watching the provider for whatever is typed so far, as SearchScreen does.
    var query = '';
    late StateSetter setQuery;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setQuery = setState;
              return Consumer(
                builder: (context, ref, _) {
                  if (query.trim().length >= 2) ref.watch(searchProvider(query));
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      ),
    );

    // Time passes a frame at a time, as it does on screen (the cursor blinks while typing).
    Future<void> wait(int ms) async {
      for (var t = 0; t < ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    // "مشتق" typed at a normal pace: a key every 120 ms, inside the debounce window.
    for (final typed in ['م', 'مش', 'مشت', 'مشتق']) {
      setQuery(() => query = typed);
      await wait(120);
    }
    await wait(1000);

    expect(catalog.queries, ['مشتق']);
  });
}
