import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/reader/providers/reader_settings_provider.dart';

void main() {
  group('ReaderSettings', () {
    test('defaults to paged reading with sheet transition', () {
      const settings = ReaderSettings();

      expect(settings.readingMode, 'paged');
      expect(settings.pageAnimation, 'sheet');
      expect(settings.volumeKeyPagingEnabled, isFalse);
      expect(settings.textAlignMode, 'justify');
      expect(settings.paragraphPreset, 'balanced');
    });

    test('persists custom font metadata through json', () {
      const settings = ReaderSettings(
        fontFamily: 'reader_font_123',
        customFontFamily: 'reader_font_123',
        customFontPath: '/fonts/reader_font_123.ttf',
        customFontName: 'Demo Serif',
        volumeKeyPagingEnabled: true,
        textAlignMode: 'start',
        paragraphPreset: 'airy',
        customBgColor: 0xFFF7EBD2,
        customFgColor: 0xFF2C2118,
      );

      final roundTrip = ReaderSettings.fromJson(settings.toJson());

      expect(roundTrip.fontFamily, 'reader_font_123');
      expect(roundTrip.customFontFamily, 'reader_font_123');
      expect(roundTrip.customFontPath, '/fonts/reader_font_123.ttf');
      expect(roundTrip.customFontName, 'Demo Serif');
      expect(roundTrip.volumeKeyPagingEnabled, isTrue);
      expect(roundTrip.textAlignMode, 'start');
      expect(roundTrip.paragraphPreset, 'airy');
      expect(roundTrip.customBgColor, 0xFFF7EBD2);
      expect(roundTrip.customFgColor, 0xFF2C2118);
    });

    test('copyWith can clear nullable custom fields', () {
      const settings = ReaderSettings(
        fontFamily: 'reader_font_123',
        customFontFamily: 'reader_font_123',
        customFontPath: '/fonts/reader_font_123.ttf',
        customFontName: 'Demo Serif',
        customBgColor: 0xFFF7EBD2,
        customFgColor: 0xFF2C2118,
      );

      final cleared = settings.copyWith(
        fontFamily: 'default',
        customFontFamily: null,
        customFontPath: null,
        customFontName: null,
        customBgColor: null,
        customFgColor: null,
      );

      expect(cleared.fontFamily, 'default');
      expect(cleared.customFontFamily, isNull);
      expect(cleared.customFontPath, isNull);
      expect(cleared.customFontName, isNull);
      expect(cleared.customBgColor, isNull);
      expect(cleared.customFgColor, isNull);
    });
  });
}
