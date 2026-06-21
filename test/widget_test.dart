// Basic widget test for SecureLink.
// Updated to reference SecureLinkApp (renamed from MyApp in flutter create).

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_link/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // Note: Firebase is not initialized in unit tests.
    // Use integration_test for full Firebase testing.
    await tester.pumpWidget(const SecureLinkApp());
  });
}
