import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/utils/audio_helper.dart';

class GlassActionCard extends StatefulWidget {
  const GlassActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.locked = false,
    this.lockedLabel = 'SOON',
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool locked;
  final String lockedLabel;
  final bool compact;

  @override
  State<GlassActionCard> createState() => _GlassActionCardState();
}

class _GlassActionCardState extends State<GlassActionCard> {
  bool _hovered = false;

  @override
  Widget build(final BuildContext context) {
    return MouseRegion(
      onEnter: (final _) => setState(() => _hovered = true),
      onExit: (final _) => setState(() => _hovered = false),
      cursor: widget.locked ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.locked
            ? null
            : () {
                AudioHelper.select();
                widget.onTap();
              },
        child: AnimatedScale(
          scale: _hovered && !widget.locked ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                width: widget.compact ? 76 : 96,
                height: widget.compact ? 76 : 96,
                decoration: BoxDecoration(
                  color: AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.glassBorder, width: 1),
                  boxShadow: <BoxShadow>[
                    if (_hovered && !widget.locked)
                      BoxShadow(
                        color: AppColors.limeBright.withValues(alpha: 0.3),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: Stack(
                  children: <Widget>[
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            widget.icon,
                            size: widget.compact ? 24 : 30,
                            color: widget.locked
                                ? Colors.white.withValues(alpha: 0.4)
                                : Colors.white,
                          ),
                          SizedBox(height: widget.compact ? 5 : 8),
                          Text(
                            widget.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: widget.locked
                                  ? Colors.white.withValues(alpha: 0.4)
                                  : Colors.white,
                              fontSize: widget.compact ? 9 : 10,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.locked)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brandRed,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.lockedLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
