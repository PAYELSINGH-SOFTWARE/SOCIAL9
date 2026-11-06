import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_update.dart';
import 'package:flutter_application_1/widgets/app_update_gate.dart';
import 'package:flutter_test/flutter_test.dart';

AppUpdate update({bool required = false}) => AppUpdate(
  installedVersion: '1.1.1',
  installedBuild: 3,
  latestVersion: '1.1.2',
  latestBuild: 4,
  required: required,
  url: Uri.parse('https://downloads.example.com/social9.apk'),
);

void main() {
  testWidgets(
    'checks at startup, Later suppresses optional repeat, resume can force',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      var checks = 0;
      var required = false;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          builder: (_, child) => AppUpdateGate(
            navigatorKey: key,
            child: child!,
            check: () async {
              checks++;
              return update(required: required);
            },
          ),
          home: const Scaffold(body: Text('Social9 home')),
        ),
      );
      await tester.pumpAndSettle();
      expect(checks, 1);
      expect(find.text('Update available'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(checks, 2);
      expect(find.byType(AppUpdateDialog), findsNothing);

      required = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(checks, 3);
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed check leaves app usable', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        builder: (_, child) => AppUpdateGate(
          navigatorKey: key,
          child: child!,
          check: () async => null,
        ),
        home: const Scaffold(body: Text('Social9 home')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Social9 home'), findsOneWidget);
    expect(find.byType(AppUpdateDialog), findsNothing);
  });

  testWidgets('session navigation cannot remove a required update', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        builder: (_, child) => AppUpdateGate(
          navigatorKey: key,
          child: child!,
          check: () async => update(required: true),
        ),
        home: const Scaffold(body: Text('Social9 home')),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Sign in again')),
      ),
      (_) => false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('update opens correct link and keeps mandatory popup visible', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdateDialog(
            update: update(required: true),
            open: (url) async {
              opened = url;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    expect(opened.toString(), 'https://downloads.example.com/social9.apk');
    expect(find.text('Update required'), findsOneWidget);
  });

  testWidgets('update link failure gives retry feedback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdateDialog(update: update(), open: (_) async => false),
        ),
      ),
    );
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not open the update. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Update now'), findsOneWidget);
  });
}
