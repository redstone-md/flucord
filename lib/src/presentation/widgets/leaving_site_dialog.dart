import 'package:flutter/material.dart';

import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_dialog.dart';
import 'trusted_domains_scope.dart';

/// Whether a link from a message may open [uri] in the browser.
///
/// A host Discord owns or the person trusted answers yes at once. Any other
/// asks first, the way Discord's "Leaving Discord" dialog does: it shows
/// the real address, so a masked link cannot hide where it goes, and it
/// can trust the host from now on. With no [TrustedDomainsScope] above
/// [context], the answer is yes.
Future<bool> confirmLeavingFor(BuildContext context, Uri uri) async {
  final trust = TrustedDomainsScope.maybeOf(context);
  if (trust == null || trust.trusts(uri)) return true;
  final answer = await showDialog<_Leave>(
    context: context,
    builder: (_) => _LeavingSiteDialog(uri: uri),
  );
  if (answer == _Leave.visitAndTrust) await trust.trust(uri);
  return answer != null;
}

enum _Leave { visit, visitAndTrust }

class _LeavingSiteDialog extends StatefulWidget {
  const _LeavingSiteDialog({required this.uri});

  final Uri uri;

  @override
  State<_LeavingSiteDialog> createState() => _LeavingSiteDialogState();
}

class _LeavingSiteDialogState extends State<_LeavingSiteDialog> {
  bool _trust = false;

  @override
  Widget build(BuildContext context) => FlucordDialog(
    key: const ValueKey('leaving-site-dialog'),
    title: const Text('Leaving Flucord'),
    description: 'This link is taking you to the following website.',
    cancelLabel: 'Go back',
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Address(uri: widget.uri),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const ValueKey('leaving-site-trust'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _trust,
          onChanged: (value) => setState(() => _trust = value ?? false),
          title: Text('Trust ${widget.uri.host} links from now on'),
        ),
      ],
    ),
    confirm: FlucordDialogConfirm(
      key: const ValueKey('leaving-site-visit'),
      label: 'Visit site',
      onPressed: () => Navigator.of(
        context,
      ).pop(_trust ? _Leave.visitAndTrust : _Leave.visit),
    ),
  );
}

/// The whole address in a recessed box, with the host in full text and the
/// rest muted, so the place the link goes is what the eye lands on.
class _Address extends StatelessWidget {
  const _Address({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final address = uri.toString();
    final host = uri.host;
    // The host comes after the scheme and any user part, which is where a
    // look-alike name hides: `https://discord.com@example.com` goes to
    // example.com.
    final start = host.isEmpty
        ? -1
        : address.indexOf(host, uri.scheme.length + uri.userInfo.length);
    final muted = FlucordTextRole.body.style.copyWith(color: surfaces.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surfaces.inset,
        borderRadius: FlucordRadius.medium,
        border: Border.all(color: surfaces.border),
      ),
      child: Text.rich(
        key: const ValueKey('leaving-site-address'),
        start < 0
            ? TextSpan(text: address)
            : TextSpan(
                children: [
                  TextSpan(text: address.substring(0, start)),
                  TextSpan(
                    text: host,
                    style: FlucordTextRole.body.strong.copyWith(
                      color: surfaces.text,
                    ),
                  ),
                  TextSpan(text: address.substring(start + host.length)),
                ],
              ),
        style: muted,
      ),
    );
  }
}
