import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/utils/audio_helper.dart';

class FaqItem extends StatefulWidget {
  const FaqItem({
    super.key,
    required this.question,
    required this.answer,
  });

  final String question;
  final String answer;

  @override
  State<FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<FaqItem>
    with SingleTickerProviderStateMixin {
  bool _open = false;

  @override
  Widget build(final BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          AudioHelper.select();
          setState(() => _open = !_open);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: _open
                ? AppColors.accent.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: _open
                  ? AppColors.accent.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.12),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.question,
                      style: TextStyle(
                        color: _open ? Colors.white : Colors.white.withValues(alpha: 0.92),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: _open
                          ? AppColors.accent
                          : Colors.white.withValues(alpha: 0.5),
                      size: 22,
                    ),
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: _open
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
                  child: Text(
                    widget.answer,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
