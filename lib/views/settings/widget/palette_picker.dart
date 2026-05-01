import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mini_kickers/data/models/team_palette.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/utils/audio_helper.dart';

class PalettePicker extends StatelessWidget {
  const PalettePicker({
    super.key,
    required this.currentId,
    required this.onSelect,
  });

  final String currentId;
  final void Function(String id) onSelect;

  @override
  Widget build(final BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.brandRed.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.brandRed.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.palette_rounded,
                      color: AppColors.brandRed,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Team Colors',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: SettingsService.instance.availablePalettes
                    .map((final TeamPalette p) {
                  final bool selected = p.id == currentId;
                  return GestureDetector(
                    onTap: () {
                      AudioHelper.select();
                      onSelect(p.id);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: selected
                              ? AppColors.accent
                              : Colors.white.withValues(alpha: 0.18),
                          width: selected ? 1.6 : 1,
                        ),
                        boxShadow: selected
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: AppColors.accent
                                      .withValues(alpha: 0.45),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _Swatch(color: p.redPrimary),
                          const SizedBox(width: 4),
                          _Swatch(color: p.bluePrimary),
                          const SizedBox(width: 8),
                          Text(
                            p.name,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.78),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});
  final Color color;

  @override
  Widget build(final BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: 0.7),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}
