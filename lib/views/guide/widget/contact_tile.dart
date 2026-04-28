import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactTile extends StatelessWidget {
  const ContactTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.launchUrl,
    this.copyValue,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String launchUrl;
  final String? copyValue;

  Future<void> _onTap(final BuildContext context) async {
    AudioHelper.select();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final bool ok = await launchUrlString(launchUrl);
      if (!ok) {
        await Clipboard.setData(ClipboardData(text: copyValue ?? value));
        _showCopiedSnack(messenger);
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: copyValue ?? value));
      _showCopiedSnack(messenger);
    }
  }

  void _showCopiedSnack(final ScaffoldMessengerState messenger) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Copied: ${copyValue ?? value}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(final BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onTap(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: color.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withValues(alpha: 0.5)),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withValues(alpha: 0.4),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> launchUrlString(final String url) async {
  final Uri uri = Uri.parse(url);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
