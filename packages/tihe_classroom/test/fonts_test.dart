import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

void main() {
  test('the classroom is in Modam unless the app chooses its own typeface', () {
    expect(ClassroomTheme.forBrightness(Brightness.dark).fontFamily, 'Modam');

    // The one TIHE app sets the whole app, the class included, in Peyda.
    ClassroomFonts.use('Peyda');
    expect(ClassroomFonts.family, 'Peyda');
    for (final b in Brightness.values) {
      final theme = ClassroomTheme.forBrightness(b);
      expect(theme.fontFamily, 'Peyda');
      expect(theme.brightness, b);
      expect(
        buildClassroomThemeData(theme).textTheme.bodyMedium?.fontFamily,
        'Peyda',
      );
    }
  });
}
