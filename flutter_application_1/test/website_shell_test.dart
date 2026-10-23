import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:flutter_application_1/main.dart';

class FakeWebPlatform extends WebViewPlatform {
  FakeController? created;
  FakeController get controller => created!;
  late FakeNavigation navigation;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => created = FakeController(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => navigation = FakeNavigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => FakeWebWidget(params);
}

class FakeController extends PlatformWebViewController {
  FakeController(super.params) : super.implementation();
  Uri? url;
  String? script;
  Color? background;
  JavaScriptChannelParams? channel;
  late FakeNavigation navigation;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {
    background = color;
  }

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    navigation = handler as FakeNavigation;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    url = params.uri;
    navigation.started?.call(url.toString());
  }

  @override
  Future<String?> currentUrl() async => url?.toString();
  @override
  Future<void> runJavaScript(String value) async {
    script = value;
  }

  @override
  Future<Object> runJavaScriptReturningResult(String value) async => false;
  @override
  Future<bool> canGoBack() async => false;
  void send(Map<String, dynamic> message, {String? token}) {
    final match = RegExp(r'const token = ("[^"]+");').firstMatch(script!);
    channel!.onMessageReceived(
      JavaScriptMessage(
        message: jsonEncode({
          'version': 1,
          'token': token ?? jsonDecode(match!.group(1)!),
          'origin': 'https://www.social9.io',
          ...message,
        }),
      ),
    );
  }

  void ready({String? token, String theme = 'light'}) =>
      send({'type': 'ready', 'theme': theme}, token: token);
}

class FakeNavigation extends PlatformNavigationDelegate {
  FakeNavigation(super.params) : super.implementation();
  PageEventCallback? started, finished;
  NavigationRequestCallback? navigate;
  WebResourceErrorCallback? error;
  HttpResponseErrorCallback? httpError;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    navigate = callback;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {
    started = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    error = callback;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async {
    httpError = callback;
  }
}

class FakeWebWidget extends PlatformWebViewWidget {
  FakeWebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: ValueKey('real-website-surface'));
}

void main() {
  late FakeWebPlatform platform;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rootBundle.evict('assets/mobile_bridge.js');
    WebViewPlatform.instance = platform = FakeWebPlatform();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> start(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const Social9App());
    for (
      var attempt = 0;
      attempt < 20 && platform.created?.url == null;
      attempt++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump();
    }
    expect(
      platform.created?.url,
      isNotNull,
      reason: 'The WebView must finish initializing before this test acts.',
    );
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets(
    'shipping app loads the real website, not a separate Flutter login',
    (tester) async {
      await start(tester);
      expect(
        platform.controller.url.toString(),
        'https://www.social9.io/login',
      );
      expect(
        find.byKey(const ValueKey('real-website-surface')),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNothing);
      platform.navigation.finished?.call(platform.controller.url.toString());
      await tester.pump();
      platform.controller.ready();
      await tester.pump();
      expect(find.text('Opening Social9…'), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );
  testWidgets('unauthenticated bridge messages cannot mark a page ready', (
    tester,
  ) async {
    await start(tester);
    platform.navigation.finished?.call(platform.controller.url.toString());
    await tester.pump();
    final original = platform.controller.background;
    platform.controller.ready(token: 'wrong-document-secret', theme: 'dark');
    await tester.pump();
    expect(platform.controller.background, original);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await finish(tester);
  });
  testWidgets('subresource errors do not replace the entire workspace', (
    tester,
  ) async {
    await start(tester);
    platform.navigation.error?.call(
      WebResourceError(
        errorCode: -2,
        description: 'thumbnail missing',
        isForMainFrame: false,
      ),
    );
    await tester.pump();
    expect(find.text('Try again'), findsNothing);
    await finish(tester);
  });
  testWidgets(
    'main-page failures show recovery controls without clearing sessions',
    (tester) async {
      await start(tester);
      platform.navigation.error?.call(
        WebResourceError(
          errorCode: -2,
          description: 'offline',
          isForMainFrame: true,
        ),
      );
      await tester.pump();
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Open website in browser'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(
        platform.controller.url.toString(),
        'https://www.social9.io/login',
      );
      expect(find.text('Try again'), findsNothing);
      await finish(tester);
    },
  );
  testWidgets(
    'every first-party page is allowed and dangerous schemes are blocked',
    (tester) async {
      await start(tester);
      expect(
        await platform.navigation.navigate!(
          const NavigationRequest(
            url: 'https://www.social9.io/admin/coupons',
            isMainFrame: true,
          ),
        ),
        NavigationDecision.navigate,
      );
      expect(
        await platform.navigation.navigate!(
          const NavigationRequest(
            url: 'javascript:alert(1)',
            isMainFrame: true,
          ),
        ),
        NavigationDecision.prevent,
      );
      await finish(tester);
    },
  );
  testWidgets('website owns loading UI and late successful loads recover', (
    tester,
  ) async {
    await start(tester);
    await tester.pump(const Duration(seconds: 75));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Try again'), findsNothing);
    platform.navigation.error?.call(
      WebResourceError(
        errorCode: -2,
        description: 'offline',
        isForMainFrame: true,
      ),
    );
    await tester.pump();
    expect(find.text('Try again'), findsOneWidget);
    platform.navigation.finished?.call(platform.controller.url.toString());
    await tester.pump();
    platform.controller.ready();
    await tester.pump();
    expect(find.text('Try again'), findsNothing);
    await finish(tester);
  });
  testWidgets(
    'page navigation waits until an export has reached native storage',
    (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('social9/device'), (
            call,
          ) async {
            calls.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('social9/device'),
              null,
            ),
      );
      await start(tester);
      platform.navigation.finished?.call(platform.controller.url.toString());
      await tester.pump();
      platform.controller.ready();
      await tester.pump();
      platform.controller.send({
        'type': 'downloadPreparing',
        'id': 'export-1',
        'requestId': 'prepare-1',
      });
      await tester.pump();
      var navigated = false;
      final navigation =
          Future<NavigationDecision>.value(
            platform.navigation.navigate!(
              const NavigationRequest(
                url: 'https://www.social9.io/calendar',
                isMainFrame: true,
              ),
            ),
          ).then((decision) {
            navigated = true;
            return decision;
          });
      await tester.pump();
      expect(navigated, isFalse);
      platform.controller.send({
        'type': 'downloadStart',
        'id': 'export-1',
        'filename': 'report.csv',
        'size': null,
        'mime': 'text/csv',
        'requestId': 'start-1',
      });
      await tester.pump();
      platform.controller.send({
        'type': 'downloadFinish',
        'id': 'export-1',
        'size': 0,
        'requestId': 'finish-1',
      });
      await tester.pump();
      expect(await navigation, NavigationDecision.navigate);
      expect(calls, containsAllInOrder(['startExport', 'finishExport']));
      await finish(tester);
    },
  );
}
