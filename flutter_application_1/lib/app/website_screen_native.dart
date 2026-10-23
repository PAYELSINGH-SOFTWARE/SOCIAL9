import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../core/checkout.dart' as checkout;
import 'export_transfer.dart';
import 'website_policy.dart';

class Social9WebsiteScreen extends StatefulWidget {
  const Social9WebsiteScreen({super.key});
  @override
  State<Social9WebsiteScreen> createState() => _Social9WebsiteScreenState();
}

class _Social9WebsiteScreenState extends State<Social9WebsiteScreen>
    with WidgetsBindingObserver {
  static const _device = MethodChannel('social9/device');
  final policy = WebsitePolicy(
    website: const String.fromEnvironment(
      'SOCIAL9_WEB_URL',
      defaultValue: WebsitePolicy.canonicalOrigin,
    ),
  );
  final exports = <String, ExportTransfer>{};
  final pendingExports = <String>{};
  Completer<void>? _exportGate;
  WebViewController? controller;
  StreamSubscription<Uri>? _links;
  String _bridgeSource = '', _bridgeToken = '';
  String? _activeOrigin, _error;
  bool _ready = false, _checkoutOpen = false, _dark = true;
  Widget? _fullscreen;
  VoidCallback? _hideFullscreen;

  bool get _supported => const {
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  }.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    _dark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness !=
        Brightness.light;
    WidgetsBinding.instance.addObserver(this);
    if (_supported) unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      try {
        final theme = (await SharedPreferences.getInstance()).getString(
          'social9_shell_theme',
        );
        if (mounted && theme != null) setState(() => _dark = theme == 'dark');
      } catch (_) {
        /* Theme cache is optional; website storage is authoritative. */
      }
      _bridgeSource = await rootBundle.loadString('assets/mobile_bridge.js');
      if (!mounted) return;
      final params = WebViewPlatform.instance is WebKitWebViewPlatform
          ? WebKitWebViewControllerCreationParams(
              allowsInlineMediaPlayback: true,
              mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
            )
          : const PlatformWebViewControllerCreationParams();
      final view = WebViewController.fromPlatformCreationParams(params);
      controller = view;
      await view.setJavaScriptMode(JavaScriptMode.unrestricted);
      await view.setBackgroundColor(_background);
      await view.addJavaScriptChannel(
        'Social9Device',
        onMessageReceived: (message) => unawaited(_message(message)),
      );
      await view.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _navigate,
          onPageStarted: _pageStarted,
          onPageFinished: _pageFinished,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              _showError(
                'Social9 could not load. Check your connection and try again.',
              );
            }
          },
        ),
      );
      if (view.platform is AndroidWebViewController) {
        final android = view.platform as AndroidWebViewController;
        await AndroidWebViewController.enableDebugging(kDebugMode);
        await android.setMediaPlaybackRequiresUserGesture(false);
        await android.setOnShowFileSelector(_chooseFiles);
        await android.setCustomWidgetCallbacks(
          onShowCustomWidget: (widget, hide) {
            if (mounted) {
              setState(() {
                _fullscreen = widget;
                _hideFullscreen = hide;
              });
            }
          },
          onHideCustomWidget: () {
            if (mounted) {
              setState(() {
                _fullscreen = null;
                _hideFullscreen = null;
              });
            }
          },
        );
      }
      if (mounted) setState(() {});
      Uri? initial;
      try {
        final links = AppLinks();
        initial = policy.appLink(await links.getInitialLink() ?? Uri());
        _links = links.uriLinkStream.listen((link) {
          final target = policy.appLink(link);
          if (target != null) unawaited(_openAppLink(target));
        }, onError: (_) => _notice('This link could not be opened.'));
      } catch (_) {
        /* Optional on desktop. */
      }
      if (mounted) await view.loadRequest(initial ?? policy.startPage);
    } catch (_) {
      _showError(
        'The website viewer could not start. Update Android System WebView and try again.',
      );
    }
  }

  Color get _background =>
      _dark ? const Color(0xFF101218) : const Color(0xFFF7F7FB);

  Future<void> _rememberTheme() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        'social9_shell_theme',
        _dark ? 'dark' : 'light',
      );
    } catch (_) {
      /* Do not block a page because of a preference write failure. */
    }
  }

  Future<void> _waitForExports() async {
    await _exportGate?.future;
  }

  void _endExport(String id) {
    pendingExports.remove(id);
    exports.remove(id);
    if (pendingExports.isEmpty) {
      _exportGate?.complete();
      _exportGate = null;
    }
  }

  Future<void> _openAppLink(Uri target) async {
    if (!mounted || _checkoutOpen) return;
    await _waitForExports();
    if (mounted) await controller?.loadRequest(target);
  }

  void _pageStarted(String raw) {
    final url = Uri.tryParse(raw);
    _activeOrigin = url != null && policy.isWebsite(url) ? url.origin : null;
    final random = Random.secure();
    _bridgeToken = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    // Normal navigation waits for disk handoff. An unavoidable document
    // replacement (e.g. a server redirect) must still release partial files.
    for (final id in pendingExports.toList()) {
      unawaited(
        _device
            .invokeMethod<void>('abortExport', {'id': id})
            .catchError((_) {}),
      );
      _endExport(id);
    }
    if (mounted) {
      setState(() {
        _ready = false;
        _error = null;
      });
    }
  }

  Future<void> _pageFinished(String raw) async {
    final url = Uri.tryParse(raw);
    if (!mounted || url == null || !policy.isWebsite(url)) return;
    try {
      final current = Uri.tryParse(await controller?.currentUrl() ?? '');
      if (current == null || !policy.isWebsite(current)) return;
      await controller?.runJavaScript(
        _bridgeSource.replaceAll(
          '__SOCIAL9_BRIDGE_TOKEN__',
          jsonEncode(_bridgeToken),
        ),
      );
    } catch (_) {
      _notice('Some device features could not start. Please reload Social9.');
    }
  }

  Future<NavigationDecision> _navigate(NavigationRequest request) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (policy.isWebsite(uri)) {
      if (request.isMainFrame) await _waitForExports();
      return mounted ? NavigationDecision.navigate : NavigationDecision.prevent;
    }
    if (!request.isMainFrame &&
        (policy.isPaymentFrame(uri) ||
            {'blob', 'data', 'about'}.contains(uri.scheme))) {
      return NavigationDecision.navigate;
    }
    if (policy.isExternal(uri)) {
      final authorization = policy.isProviderAuthorization(uri);
      if (authorization) await _command('beginAuth');
      await _external(uri, authorization: authorization);
    } else if (request.isMainFrame) {
      _notice(
        'This link was blocked because it is not a secure, supported link.',
      );
    }
    return NavigationDecision.prevent;
  }

  Future<void> _external(Uri uri, {bool authorization = false}) async {
    try {
      final opened =
          uri.scheme == 'intent' &&
              defaultTargetPlatform == TargetPlatform.android
          ? await _device.invokeMethod<bool>('openIntent', {
                  'url': uri.toString(),
                }) ??
                false
          : await launchUrl(
              uri,
              mode: authorization
                  ? LaunchMode.inAppBrowserView
                  : LaunchMode.externalApplication,
            );
      if (!opened) {
        _notice(
          'No app could open this link. Please install a compatible browser or payment app.',
        );
      }
    } catch (_) {
      _notice('Unable to open this link. Please try again.');
    }
  }

  Future<List<String>> _chooseFiles(FileSelectorParams params) async {
    try {
      final extensions = <String>{};
      for (final accept in params.acceptTypes.expand(
        (value) => value.split(','),
      )) {
        final value = accept.trim().toLowerCase();
        if (value.startsWith('.') && value.length > 1) {
          extensions.add(value.substring(1));
        }
        if (value.startsWith('image/')) {
          extensions.addAll(['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic']);
        }
        if (value.startsWith('video/')) {
          extensions.addAll(['mp4', 'mov', 'webm', 'm4v']);
        }
        if (value == 'application/pdf') extensions.add('pdf');
      }
      final files = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: extensions.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: extensions.isEmpty ? null : extensions.toList(),
      );
      return files?.paths
              .whereType<String>()
              .map((path) => Uri.file(path).toString())
              .toList() ??
          [];
    } catch (_) {
      _notice('Unable to select files. Please try again.');
      return [];
    }
  }

  Future<void> _message(JavaScriptMessage raw) async {
    if (raw.message.length > 128 * 1024) return;
    Map? message;
    final documentToken = _bridgeToken;
    try {
      final parsed = jsonDecode(raw.message);
      if (parsed is! Map ||
          parsed['version'] != 1 ||
          parsed['token'] != _bridgeToken ||
          _bridgeToken.isEmpty ||
          parsed['origin'] != _activeOrigin ||
          _activeOrigin == null) {
        return;
      }
      message = parsed;
      final id = message['id'];
      switch (message['type']) {
        case 'ready':
          if (mounted) {
            setState(() {
              _ready = true;
              _error = null;
              _dark = message!['theme'] != 'light';
            });
          }
          await controller?.setBackgroundColor(_background);
          unawaited(_rememberTheme());
        case 'notice':
          _notice(message['message']?.toString() ?? 'Please try again.');
        case 'downloadPreparing':
          if (id is! String ||
              !RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(id) ||
              pendingExports.length >= 4 ||
              pendingExports.contains(id)) {
            throw const FormatException(
              'Finish an active export before starting another.',
            );
          }
          _exportGate ??= Completer<void>();
          pendingExports.add(id);
        case 'downloadStart':
          if (id is! String ||
              !pendingExports.contains(id) ||
              exports.containsKey(id)) {
            throw const FormatException('Invalid export.');
          }
          final transfer = ExportTransfer(
            filename: message['filename'] as String,
            expectedBytes: message['size'] as int?,
          );
          exports[id] = transfer;
          await _device.invokeMethod<void>('startExport', {
            'id': id,
            'filename': transfer.filename,
            'mime': message['mime'],
          });
        case 'downloadChunk':
          final transfer = exports[id];
          if (transfer == null) {
            throw const FormatException('Export is no longer active.');
          }
          transfer.validateChunk(
            message['sequence'] as int,
            message['data'] as String,
          );
          await _device.invokeMethod<void>('appendExport', {
            'id': id,
            'sequence': message['sequence'],
            'data': message['data'],
          });
        case 'downloadFinish':
          final transfer = exports[id];
          if (transfer == null || message['size'] != transfer.receivedBytes) {
            throw const FormatException('Incomplete export.');
          }
          transfer.finish();
          await _device.invokeMethod<void>('finishExport', {
            'id': id,
            'size': transfer.receivedBytes,
          });
        case 'downloadAbort':
          await _device.invokeMethod<void>('abortExport', {'id': id});
          if (id is String) _endExport(id);
        case 'print':
          await _print(message['title']?.toString() ?? 'Social9 report');
        case 'checkout':
          if (id is String && message['options'] is Map) {
            unawaited(
              _checkout(
                id,
                Map<String, dynamic>.from(message['options'] as Map),
              ),
            );
          }
      }
      if (documentToken == _bridgeToken && message['requestId'] is String) {
        await _command('acknowledge', {'requestId': message['requestId']});
      }
      if (message['type'] == 'downloadFinish' && id is String) _endExport(id);
    } catch (error) {
      if (message == null) return;
      final id = message['id'];
      if (id is String) {
        try {
          await _device.invokeMethod<void>('abortExport', {'id': id});
        } catch (_) {
          /* Cleanup is best effort. */
        }
        _endExport(id);
      }
      final reason = error is FormatException
          ? error.message
          : 'Unable to complete this device action. Check available storage and try again.';
      if (documentToken == _bridgeToken && message['requestId'] is String) {
        await _command('acknowledge', {
          'requestId': message['requestId'],
          'error': reason,
        });
      } else {
        _notice(reason);
      }
    }
  }

  Future<void> _print(String title) async {
    try {
      final platform = controller?.platform;
      if (platform is! AndroidWebViewController) {
        throw UnsupportedError('Printing');
      }
      final opened = await _device.invokeMethod<bool>('printCurrentPage', {
        'title': title,
        'webViewId': platform.webViewIdentifier,
      });
      if (opened != true) {
        _notice('Printing is unavailable. Export the report as CSV instead.');
      }
    } catch (_) {
      _notice('Printing is unavailable on this device. Export CSV instead.');
    }
  }

  Future<void> _checkout(String id, Map<String, dynamic> options) async {
    final documentToken = _bridgeToken;
    Map<String, dynamic> result;
    if (_checkoutOpen) {
      result = {
        'id': id,
        'status': 'failed',
        'message': 'Another checkout is already open.',
      };
    } else {
      _checkoutOpen = true;
      try {
        if (options['key'] is! String ||
            options['order_id'] is! String ||
            !(options['key'] as String).startsWith('rzp_') ||
            !(options['order_id'] as String).startsWith('order_')) {
          throw checkout.CheckoutFailure(
            'The server did not return a valid payment order.',
          );
        }
        final prefill = options['prefill'] is Map
            ? options['prefill'] as Map
            : {};
        final response = await checkout.openCheckout({
          'key_id': options['key'],
          'order_id': options['order_id'],
          'currency': options['currency'] ?? 'INR',
          'name': options['name'] ?? 'Social9',
          'description': options['description'] ?? 'Social9 subscription',
          'customer_name': prefill['name'],
          'customer_email': prefill['email'],
          'theme': options['theme'],
        });
        result = {
          'id': id,
          'status': response == null ? 'cancelled' : 'success',
          'response': response,
        };
      } catch (error) {
        result = {
          'id': id,
          'status': 'failed',
          'message': error is checkout.CheckoutFailure
              ? error.message
              : 'Unable to open secure checkout.',
        };
      } finally {
        _checkoutOpen = false;
      }
    }
    if (mounted && documentToken == _bridgeToken) {
      await _command('paymentResult', result);
    }
  }

  Future<Object?> _command(String method, [Object? argument]) async {
    if (!_ready || controller == null || _activeOrigin == null) return null;
    try {
      return await controller!.runJavaScriptReturningResult(
        'window.__social9Native?.$method(${argument == null ? '' : jsonEncode(argument)}) ?? false',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _back() async {
    if (_fullscreen != null) {
      _hideFullscreen?.call();
      return;
    }
    if (_checkoutOpen) return;
    final closed = await _command('closeOverlay');
    if (closed == true || closed == 'true') return;
    await _waitForExports();
    if (await controller?.canGoBack() == true) {
      await controller?.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  Future<void> _retry() async {
    if (controller == null) {
      await _initialize();
      return;
    }
    final current = Uri.tryParse(await controller?.currentUrl() ?? '');
    await _waitForExports();
    await controller?.loadRequest(
      current != null && policy.isWebsite(current) ? current : policy.startPage,
    );
  }

  void _showError(String error) {
    if (mounted) setState(() => _error = error);
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_command('resume'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _links?.cancel();
    for (final id in pendingExports.toList()) {
      unawaited(
        _device
            .invokeMethod<void>('abortExport', {'id': id})
            .catchError((_) {}),
      );
      _endExport(id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: _dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) unawaited(_back());
      },
      child: Scaffold(
        backgroundColor: _background,
        body: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                child: !_supported
                    ? Center(
                        child: FilledButton(
                          onPressed: () => _external(policy.startPage),
                          child: const Text('Open Social9'),
                        ),
                      )
                    : Stack(
                        children: [
                          if (controller != null)
                            Positioned.fill(
                              child: WebViewWidget(controller: controller!),
                            ),
                          if (_error != null)
                            Positioned.fill(
                              child: ColoredBox(
                                color: _background,
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(28),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _error!,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _dark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        FilledButton.icon(
                                          onPressed: _retry,
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('Try again'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              _external(policy.startPage),
                                          child: const Text(
                                            'Open website in browser',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            if (_fullscreen != null) Positioned.fill(child: _fullscreen!),
          ],
        ),
      ),
    ),
  );
}
