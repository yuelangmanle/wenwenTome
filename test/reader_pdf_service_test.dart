import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:wenwen_tome/features/reader/reader_pdf_service.dart';

void main() {
  test('normalizes outline page numbers when dest page is 0-based', () {
    const nodes = <PdfOutlineNode>[
      PdfOutlineNode(
        title: 'A',
        dest: PdfDest(0, PdfDestCommand.fit, null),
        children: <PdfOutlineNode>[],
      ),
      PdfOutlineNode(
        title: 'B',
        dest: PdfDest(1, PdfDestCommand.fit, null),
        children: <PdfOutlineNode>[],
      ),
    ];

    final entries = ReaderPdfService.flattenAndNormalizeOutlineForTest(
      nodes,
      pageCount: 2,
    );

    expect(entries.map((e) => e.pageNumber).toList(), [1, 2]);
  });

  test('keeps 1-based outline page numbers intact', () {
    const nodes = <PdfOutlineNode>[
      PdfOutlineNode(
        title: 'A',
        dest: PdfDest(1, PdfDestCommand.fit, null),
        children: <PdfOutlineNode>[],
      ),
      PdfOutlineNode(
        title: 'B',
        dest: PdfDest(2, PdfDestCommand.fit, null),
        children: <PdfOutlineNode>[],
      ),
    ];

    final entries = ReaderPdfService.flattenAndNormalizeOutlineForTest(
      nodes,
      pageCount: 3,
    );

    expect(entries.map((e) => e.pageNumber).toList(), [1, 2]);
  });

  test('clamps outline page numbers into 1..pageCount', () {
    const nodes = <PdfOutlineNode>[
      PdfOutlineNode(
        title: 'Low',
        dest: PdfDest(-10, PdfDestCommand.fit, null),
        children: <PdfOutlineNode>[],
      ),
      PdfOutlineNode(
        title: 'High',
        dest: PdfDest(999, PdfDestCommand.fit, null),
        children: <PdfOutlineNode>[],
      ),
    ];

    final entries = ReaderPdfService.flattenAndNormalizeOutlineForTest(
      nodes,
      pageCount: 5,
    );

    expect(entries.map((e) => e.pageNumber).toList(), [1, 5]);
  });
}

