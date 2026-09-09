import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:threadvault/widgets/clipora_rope_logo.dart';

void main() {
  testWidgets('renders the braided rope logo', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: CliporaRopeLogo(size: 96)),
        ),
      ),
    );

    expect(find.byType(CliporaRopeLogo), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('renders the rope launch finale animation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CliporaRopeLaunchAnimation(animation: AlwaysStoppedAnimation<double>(1)),
        ),
      ),
    );

    expect(find.text('Clipora'), findsOneWidget);
    expect(find.text('threads twist into saves'), findsOneWidget);
  });
}
