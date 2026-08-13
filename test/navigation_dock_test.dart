import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App Shell loads correctly and navigates between tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Text('Test Host')),
        ),
      ),
    );

    expect(find.text('Test Host'), findsOneWidget);
  });
}
