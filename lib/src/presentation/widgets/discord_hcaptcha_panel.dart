import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../domain/discord_remote_auth.dart';
import '../../theme/flucord_theme.dart';
import 'discord_hcaptcha_bridge.dart';

final class DiscordHcaptchaPanel extends StatefulWidget {
  const DiscordHcaptchaPanel({
    required this.challenge,
    required this.onSolved,
    super.key,
  });

  final DiscordRemoteAuthCaptchaChallenge challenge;
  final Future<void> Function(String token) onSolved;

  @override
  State<DiscordHcaptchaPanel> createState() => _DiscordHcaptchaPanelState();
}

final class _DiscordHcaptchaPanelState extends State<DiscordHcaptchaPanel> {
  WebviewController? _controller;
  StreamSubscription<LoadingState>? _loadingSubscription;
  StreamSubscription<Object?>? _messageSubscription;
  StreamSubscription<WebErrorStatus>? _errorSubscription;
  bool _documentInjected = false;
  bool _ready = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (!Platform.isWindows) {
      _setError('CAPTCHA login currently requires Windows WebView2.');
      return;
    }
    final controller = WebviewController();
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      _messageSubscription = controller.webMessage.listen(_acceptMessage);
      _loadingSubscription = controller.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted) {
          unawaited(_injectDocument());
        }
      });
      _errorSubscription = controller.onLoadError.listen((_) {
        _setError('The hCaptcha challenge could not be loaded.');
      });
      await controller.setUserAgent(widget.challenge.userAgent);
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await controller.setBackgroundColor(const Color(0xff1e1f22));
      if (mounted) setState(() {});
      await controller.loadUrl('https://discord.com/login');
    } on PlatformException {
      await _disposeController(controller, clearData: false);
      _setError('Microsoft Edge WebView2 is unavailable.');
    } on Object {
      await _disposeController(controller, clearData: false);
      _setError('The hCaptcha challenge could not be started.');
    }
  }

  Future<void> _injectDocument() async {
    final controller = _controller;
    if (_documentInjected || controller == null) return;
    _documentInjected = true;
    try {
      await controller.executeScript(
        DiscordHcaptchaBridge.documentReplacementScript(widget.challenge),
      );
    } on Object {
      _setError('The hCaptcha challenge could not be prepared.');
    }
  }

  void _acceptMessage(Object? raw) {
    final message = DiscordHcaptchaMessage.tryParse(raw);
    if (message == null || !mounted) return;
    switch (message.type) {
      case DiscordHcaptchaMessageType.ready:
        setState(() => _ready = true);
      case DiscordHcaptchaMessageType.solved:
        unawaited(_submit(message.token!));
      case DiscordHcaptchaMessageType.error:
        _setError('hCaptcha reported a challenge error.');
      case DiscordHcaptchaMessageType.expired:
        _setError('The hCaptcha response expired. Try the challenge again.');
    }
  }

  Future<void> _submit(String token) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    await _teardown(clearData: true);
    try {
      await widget.onSolved(token);
    } on Object {
      _setError('Discord did not accept the CAPTCHA response.');
    }
  }

  Future<void> _retry() async {
    await _teardown(clearData: true);
    if (!mounted) return;
    setState(() {
      _documentInjected = false;
      _ready = false;
      _submitting = false;
      _error = null;
    });
    await _initialize();
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  Future<void> _teardown({required bool clearData}) async {
    await _loadingSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _errorSubscription?.cancel();
    _loadingSubscription = null;
    _messageSubscription = null;
    _errorSubscription = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      await _disposeController(controller, clearData: clearData);
    }
  }

  static Future<void> _disposeController(
    WebviewController controller, {
    required bool clearData,
  }) async {
    if (clearData && controller.value.isInitialized) {
      try {
        await controller.clearCookies();
        await controller.clearCache();
      } on Object {
        // The ephemeral view is disposed even if WebView2 rejects cleanup.
      }
    }
    try {
      await controller.dispose();
    } on Object {
      // A failed native initialization can also make disposal fail.
    }
  }

  @override
  void dispose() {
    unawaited(_teardown(clearData: true));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return SizedBox(
      height: 360,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xff1e1f22),
          border: Border.all(color: context.surfaces.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: _error != null
              ? _CaptchaError(message: _error!, onRetry: _retry)
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (controller != null && controller.value.isInitialized)
                      Webview(
                        controller,
                        permissionRequested: (_, _, _) async =>
                            WebviewPermissionDecision.deny,
                      ),
                    if (!_ready || _submitting)
                      const ColoredBox(
                        color: Color(0xff1e1f22),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

final class _CaptchaError extends StatelessWidget {
  const _CaptchaError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: FlucordColors.danger),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
