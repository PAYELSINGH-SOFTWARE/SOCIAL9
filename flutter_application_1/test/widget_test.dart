import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('shows login when there is no saved session', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const VCueSocial9App());
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
  });
}
