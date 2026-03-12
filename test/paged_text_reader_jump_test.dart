import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/reader/presentation/paged_text_reader.dart';
import 'package:wenwen_tome/features/reader/providers/reader_settings_provider.dart';

void main() {
  testWidgets('paged reader honors jump request after section change', (tester) async {
    final key = GlobalKey<ReaderPagedTextViewState>();
    final settings = const ReaderSettings();
    ReaderPagedTextLocation? lastLocation;

    Widget build({
      required String text,
      required int baseOffset,
      required int totalLength,
    }) {
      return MaterialApp(
        home: Material(
          child: SizedBox(
            width: 420,
            height: 820,
            child: ReaderPagedTextView(
              key: key,
              text: text,
              settings: settings,
              metaText: 'meta',
              initialProgress: 0,
              baseOffset: baseOffset,
              totalTextLength: totalLength,
              onLocationChanged: (loc) => lastLocation = loc,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(
      build(text: 'A ' * 4000, baseOffset: 0, totalLength: 8000),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      build(text: 'B ' * 4000, baseOffset: 4000, totalLength: 8000),
    );

    await key.currentState!.jumpToOffset(6500, animated: false);
    await tester.pumpAndSettle();

    expect(key.currentState!.currentOffset, greaterThanOrEqualTo(4000));
    expect(lastLocation, isNotNull);
    expect(lastLocation!.startOffset, greaterThanOrEqualTo(4000));
  });
}

