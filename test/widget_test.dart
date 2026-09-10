import 'package:flutter_test/flutter_test.dart';

import 'package:sos_emergency/main.dart';

void main() {
  testWidgets('home screen shows the SOS button', (tester) async {
    await tester.pumpWidget(const SosApp());
    expect(find.text('SOS'), findsOneWidget);
  });
}
