import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

void main() {
  test('the classroom is in Modam unless the app chooses its own typeface', () {
    expect(ClassroomTheme.forBrightness(Brightness.dark).fontFamily, 'Modam');

    // An app with its own typeface sets its classes in it too.
    ClassroomFonts.use('Vazirmatn');
    expect(ClassroomFonts.family, 'Vazirmatn');
    for (final b in Brightness.values) {
      final theme = ClassroomTheme.forBrightness(b);
      expect(theme.fontFamily, 'Vazirmatn');
      expect(theme.brightness, b);
      expect(
        buildClassroomThemeData(theme).textTheme.bodyMedium?.fontFamily,
        'Vazirmatn',
      );
    }
  });
}
