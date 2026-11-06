import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_update.dart';

/// Lives above the app navigator so checks also run after sign-in/navigation.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.check = _check,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final Future<AppUpdate?> Function() check;

  static Future<AppUpdate?> _check() => const AppUpdateService().check();

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  bool _checking = false, _dialogOpen = false;
  final _dismissed = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    if (!mounted || kIsWeb || _checking || _dialogOpen) return;
    _checking = true;
    try {
      final update = await widget.check();
      if (!mounted || update == null) return;
      if (!update.required && _dismissed.contains(update.release)) return;
      while (mounted) {
        final context = widget.navigatorKey.currentState?.overlay?.context;
        if (context == null || !context.mounted) return;
        _dialogOpen = true;
        await showDialog<void>(
          context: context,
          barrierDismissible: !update.required,
          builder: (_) => AppUpdateDialog(update: update),
        );
        if (!update.required) {
          _dismissed.add(update.release);
          break;
        }
        // Auth expiry/sign-in can replace the entire route stack. Keep the
        // required prompt in place even when navigation removes its route.
        await WidgetsBinding.instance.endOfFrame;
      }
    } catch (_) {
      // An update check must not interrupt a working app.
    } finally {
      _checking = false;
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({super.key, required this.update, this.open = _open});

  final AppUpdate update;
  final Future<bool> Function(Uri) open;

  static Future<bool> _open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _opening = false;
  String? _error;

  Future<void> _open() async {
    final url = widget.update.url;
    if (url == null) {
      setState(() {
        _error =
            'The update link is unavailable. Please contact Social9 support.';
      });
      return;
    }
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      if (!await widget.open(url)) throw StateError('Unable to open update');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open the update. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    return PopScope(
      canPop: !update.required,
      child: AlertDialog(
        icon: Icon(
          Icons.system_update_rounded,
          color: Theme.of(context).colorScheme.primary,
          size: 36,
        ),
        title: Text(update.required ? 'Update required' : 'Update available'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                update.required
                    ? 'Please update Social9 to continue.'
                    : 'A new version of Social9 is ready. Update for the latest improvements.',
              ),
              const SizedBox(height: 12),
              Text(
                'Installed: ${update.installedVersion}+${update.installedBuild}',
              ),
              Text('Latest: ${update.release}'),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!update.required)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          FilledButton(
            onPressed: _opening ? null : _open,
            child: Text(_opening ? 'Opening…' : 'Update now'),
          ),
        ],
      ),
    );
  }
}
