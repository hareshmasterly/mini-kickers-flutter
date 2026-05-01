import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/amazon_launcher.dart';
import 'package:mini_kickers/utils/audio_helper.dart';

class BuyAmazonButton extends StatefulWidget {
  const BuyAmazonButton({super.key, this.compact = false});

  /// Slimmer pill for short landscape phones — same content, smaller
  /// padding/icon/font so it doesn't dominate the top bar.
  final bool compact;

  @override
  State<BuyAmazonButton> createState() => _BuyAmazonButtonState();
}

class _BuyAmazonButtonState extends State<BuyAmazonButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    AudioHelper.select();
    await AmazonLauncher.openProductPage();
  }

  @override
  Widget build(final BuildContext context) {
    final bool compact = widget.compact;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (final BuildContext context, final Widget? child) {
        final double t = _pulse.value;
        return AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: GestureDetector(
            onTapDown: (final _) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (final _) {
              setState(() => _pressed = false);
              _onTap();
            },
            child: Container(
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFFFFB300),
                    Color(0xFFFF9800),
                  ],
                ),
                borderRadius: BorderRadius.circular(compact ? 18 : 26),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFFF9800).withValues(
                      alpha: 0.55 + t * 0.35,
                    ),
                    blurRadius: 16 + t * 12,
                    spreadRadius: 1 + t * 2,
                  ),
                  const BoxShadow(
                    color: Colors.black54,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: compact
                  ? _buildCompactLayout()
                  : _buildRegularLayout(),
            ),
          ),
        );
      },
    );
  }

  /// Single-line, smaller pill for landscape phones — saves ~20 dp of
  /// vertical room compared to the regular two-line layout.
  Widget _buildCompactLayout() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              'a',
              style: AppFonts.bebasNeue(
                fontSize: 14,
                color: const Color(0xFF131921),
                height: 1,
                letterSpacing: 0,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'BUY ON AMAZON',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 6),
        const Icon(
          Icons.shopping_cart_rounded,
          color: Colors.white,
          size: 14,
        ),
      ],
    );
  }

  Widget _buildRegularLayout() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              'a',
              style: AppFonts.bebasNeue(
                fontSize: 22,
                color: const Color(0xFF131921),
                height: 1,
                letterSpacing: 0,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'BUY THE BOARD GAME',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'on Amazon',
              style: AppFonts.bebasNeue(
                color: Colors.white,
                fontSize: 18,
                letterSpacing: 1.5,
                height: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        const Icon(
          Icons.shopping_cart_rounded,
          color: Colors.white,
          size: 18,
        ),
      ],
    );
  }
}
