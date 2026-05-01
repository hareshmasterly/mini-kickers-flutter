import 'dart:math';

import 'package:flutter/material.dart';

class Dice3DCube extends StatefulWidget {
  const Dice3DCube({
    super.key,
    required this.value,
    required this.isRolling,
    required this.glowColor,
    this.size = 84,
    this.isEnabled = true,
    this.onTap,
  });

  final int? value;
  final bool isRolling;
  final Color glowColor;
  final double size;

  /// When `false`, the dice is dimmed (low opacity, no glow pulse, taps
  /// ignored). Used to indicate it's the OTHER team's turn.
  final bool isEnabled;

  /// Optional tap callback. When provided AND [isEnabled] is true, the cube
  /// becomes the roll button — wraps the entire dice area in a
  /// [GestureDetector] with an opaque hit-test so the full visual region
  /// (including the soft halo) is tappable.
  final VoidCallback? onTap;

  @override
  State<Dice3DCube> createState() => _Dice3DCubeState();
}

class _Dice3DCubeState extends State<Dice3DCube>
    with TickerProviderStateMixin {
  late final AnimationController _tumble;
  late final AnimationController _settle;

  double _rotX = -0.5;
  double _rotY = 0.6;
  double _settleStartRotX = 0;
  double _settleStartRotY = 0;
  double _targetRotX = 0;
  double _targetRotY = 0;

  // Settle-target rotations for each face. Camera looks toward -z (positive
  // z is into the screen), so to make a face visible we rotate the cube so
  // the face's outward normal points to +z (out of the screen).
  //
  // Verified from the face-config table below:
  //   face 5 has normal (0, +1, 0) → rotateX(+π/2) brings +Y to +Z
  //   face 2 has normal (0, -1, 0) → rotateX(-π/2) brings -Y to +Z
  //   face 4 has normal (+1, 0, 0) → rotateY(-π/2) brings +X to +Z
  //   face 3 has normal (-1, 0, 0) → rotateY(+π/2) brings -X to +Z
  //
  // (Faces 2 and 5 were previously swapped here, so e.g. state.dice=5
  // would visually present the 2-pip face — the algorithm using state.dice
  // would compute the right move targets but the cube label would lie.)
  static const Map<int, ({double rx, double ry})> _faceAngles =
      <int, ({double rx, double ry})>{
    1: (rx: 0, ry: 0),
    6: (rx: 0, ry: pi),
    4: (rx: 0, ry: -pi / 2),
    3: (rx: 0, ry: pi / 2),
    2: (rx: -pi / 2, ry: 0),
    5: (rx: pi / 2, ry: 0),
  };

  @override
  void initState() {
    super.initState();
    _tumble = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addListener(_onTumbleTick);

    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addListener(_onSettleTick);

    if (widget.isRolling) {
      _tumble.repeat();
    } else if (widget.value != null) {
      _setAnglesForFace(widget.value!);
    }
  }

  @override
  void didUpdateWidget(covariant final Dice3DCube old) {
    super.didUpdateWidget(old);
    if (widget.isRolling && !old.isRolling) {
      _settle.stop();
      _tumble.repeat();
    } else if (!widget.isRolling && old.isRolling) {
      _tumble.stop();
      _settleToFace(widget.value ?? 1);
    } else if (!widget.isRolling &&
        widget.value != old.value &&
        widget.value != null) {
      _settleToFace(widget.value!);
    }
  }

  void _onTumbleTick() {
    final double t = _tumble.value;
    setState(() {
      _rotX = -0.5 + sin(t * pi * 4) * 0.4 + t * pi * 4;
      _rotY = 0.6 + cos(t * pi * 5) * 0.5 + t * pi * 6;
    });
  }

  void _onSettleTick() {
    final double t =
        Curves.easeOutBack.transform(_settle.value).clamp(0.0, 1.0);
    setState(() {
      _rotX = _settleStartRotX + (_targetRotX - _settleStartRotX) * t;
      _rotY = _settleStartRotY + (_targetRotY - _settleStartRotY) * t;
    });
  }

  void _setAnglesForFace(final int face) {
    final ({double rx, double ry}) angles = _faceAngles[face]!;
    setState(() {
      _rotX = angles.rx;
      _rotY = angles.ry;
    });
  }

  void _settleToFace(final int face) {
    final ({double rx, double ry}) angles = _faceAngles[face]!;
    _settleStartRotX = _normalizeAngle(_rotX);
    _settleStartRotY = _normalizeAngle(_rotY);
    _targetRotX = _shortestPath(_settleStartRotX, angles.rx);
    _targetRotY = _shortestPath(_settleStartRotY, angles.ry);
    _settle
      ..reset()
      ..forward();
  }

  double _normalizeAngle(final double a) {
    double n = a % (2 * pi);
    if (n > pi) n -= 2 * pi;
    if (n < -pi) n += 2 * pi;
    return n;
  }

  double _shortestPath(final double from, final double to) {
    double diff = to - from;
    while (diff > pi) {
      diff -= 2 * pi;
    }
    while (diff < -pi) {
      diff += 2 * pi;
    }
    return from + diff;
  }

  @override
  void dispose() {
    _tumble.dispose();
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final double s = widget.size;
    final double half = s / 2;

    final List<_FaceConfig> faces = <_FaceConfig>[
      _FaceConfig(
        face: 1,
        normal: const _Vec3(0, 0, 1),
        local: Matrix4.identity()..translateByDouble(0.0, 0.0, half, 1),
      ),
      _FaceConfig(
        face: 6,
        normal: const _Vec3(0, 0, -1),
        local: Matrix4.identity()
          ..translateByDouble(0.0, 0.0, -half, 1)
          ..rotateY(pi),
      ),
      _FaceConfig(
        face: 4,
        normal: const _Vec3(1, 0, 0),
        local: Matrix4.identity()
          ..translateByDouble(half, 0.0, 0.0, 1)
          ..rotateY(pi / 2),
      ),
      _FaceConfig(
        face: 3,
        normal: const _Vec3(-1, 0, 0),
        local: Matrix4.identity()
          ..translateByDouble(-half, 0.0, 0.0, 1)
          ..rotateY(-pi / 2),
      ),
      _FaceConfig(
        face: 2,
        normal: const _Vec3(0, -1, 0),
        local: Matrix4.identity()
          ..translateByDouble(0.0, -half, 0.0, 1)
          ..rotateX(pi / 2),
      ),
      _FaceConfig(
        face: 5,
        normal: const _Vec3(0, 1, 0),
        local: Matrix4.identity()
          ..translateByDouble(0.0, half, 0.0, 1)
          ..rotateX(-pi / 2),
      ),
    ];

    final Matrix4 perspective = Matrix4.identity()
      ..setEntry(3, 2, 0.001);
    final Matrix4 rotation = Matrix4.identity()
      ..rotateX(_rotX)
      ..rotateY(_rotY);

    // Compute world transform + depth for each face. Render ALL faces
    // (no culling) so the cube always reads as a solid object even at fast
    // tumble speeds. Painter's algorithm with depth-sorting handles occlusion.
    final List<({_FaceConfig face, double depth, Matrix4 world})> sorted =
        faces.map((final _FaceConfig f) {
      final Matrix4 world =
          perspective.multiplied(rotation).multiplied(f.local);
      // Depth is z of the rotated face center for back-to-front sort.
      final _Vec3 centerWorld = _Vec3(
        f.local.storage[12],
        f.local.storage[13],
        f.local.storage[14],
      ).rotated(_rotX, _rotY);
      return (face: f, depth: centerWorld.z, world: world);
    }).toList()
          ..sort((final a, final b) => a.depth.compareTo(b.depth));

    final double tumblePulse = widget.isRolling
        ? (1.0 + sin(_tumble.value * pi * 6) * 0.04)
        : 1.0;
    // Glow intensity: full when rolling, medium when enabled & idle, low
    // when disabled (the dice on the OTHER team's side).
    final double glow = widget.isRolling
        ? 0.85
        : (widget.isEnabled ? 0.55 : 0.12);
    final double containerSize = s * 1.15;

    final Widget cube = SizedBox(
      width: containerSize,
      height: containerSize,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Square soft halo behind the cube
            IgnorePointer(
              child: Container(
                width: s * 0.95,
                height: s * 0.95,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(s * 0.18),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: widget.glowColor.withValues(alpha: glow),
                      blurRadius: widget.isEnabled ? 28 : 12,
                      spreadRadius: widget.isEnabled ? 2 : 0,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: widget.isEnabled ? 0.55 : 0.3,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
            ),
            // The cube — each face has perspective + rotation + local baked in
            SizedBox(
              width: s,
              height: s,
              child: Transform.scale(
                scale: tumblePulse,
                child: Stack(
                  alignment: Alignment.center,
                  children: sorted.map((final item) {
                    final double facingDot =
                        item.face.normal.rotated(_rotX, _rotY).z;
                    final double facing = facingDot.clamp(0.0, 1.0);
                    return Transform(
                      alignment: Alignment.center,
                      transform: item.world,
                      child: _DiceFaceTile(
                        face: item.face.face,
                        size: s,
                        facing: facing,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Apply the disabled visual treatment (lower opacity + slight
    // desaturation so the inactive team's dice is unmistakably "off").
    final Widget visual = AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: widget.isEnabled ? 1.0 : 0.42,
      child: cube,
    );

    // Wrap with GestureDetector when tappable. HitTestBehavior.opaque so
    // the full container area (including the soft halo around the cube)
    // catches taps — much easier on mobile than aiming for the cube faces.
    if (widget.onTap == null) return visual;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.isEnabled ? widget.onTap : null,
      child: visual,
    );
  }
}

class _FaceConfig {
  _FaceConfig({
    required this.face,
    required this.normal,
    required this.local,
  });

  final int face;
  final _Vec3 normal;
  final Matrix4 local;
}

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;

  _Vec3 rotated(final double rx, final double ry) {
    final double cy = cos(ry);
    final double sy = sin(ry);
    final double x1 = x * cy + z * sy;
    final double z1 = -x * sy + z * cy;
    final double cx = cos(rx);
    final double sx = sin(rx);
    final double y2 = y * cx - z1 * sx;
    final double z2 = y * sx + z1 * cx;
    return _Vec3(x1, y2, z2);
  }
}

class _DiceFaceTile extends StatelessWidget {
  const _DiceFaceTile({
    required this.face,
    required this.size,
    required this.facing,
  });

  final int face;
  final double size;
  final double facing; // 0 = edge-on, 1 = directly facing camera

  @override
  Widget build(final BuildContext context) {
    // Brightness shift based on how directly the face is facing the camera.
    final double bright = 0.5 + facing * 0.5;
    final Color baseLight = Color.lerp(
      const Color(0xFFB0B0B0),
      Colors.white,
      bright,
    )!;
    final Color baseMid = Color.lerp(
      const Color(0xFF707070),
      const Color(0xFFE0E0E0),
      bright,
    )!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // Solid base color first to guarantee opacity, then gradient on top
        color: baseLight,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[baseLight, baseMid],
        ),
        borderRadius: BorderRadius.circular(size * 0.14),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.55),
          width: 1.6,
        ),
      ),
      child: CustomPaint(painter: _DiceFacePainter(face: face)),
    );
  }
}

class _DiceFacePainter extends CustomPainter {
  _DiceFacePainter({required this.face});
  final int face;

  @override
  void paint(final Canvas canvas, final Size size) {
    final Paint dot = Paint()..color = const Color(0xFF111111);
    final Paint dotShine = Paint()..color = Colors.white.withValues(alpha: 0.35);
    final double r = size.width * 0.085;
    final double w = size.width;

    void d(final double fx, final double fy) {
      final Offset c = Offset(w * fx, w * fy);
      canvas.drawCircle(c, r, dot);
      canvas.drawCircle(c.translate(-r * 0.3, -r * 0.3), r * 0.35, dotShine);
    }

    switch (face) {
      case 1:
        d(0.5, 0.5);
        break;
      case 2:
        d(0.28, 0.28);
        d(0.72, 0.72);
        break;
      case 3:
        d(0.25, 0.25);
        d(0.5, 0.5);
        d(0.75, 0.75);
        break;
      case 4:
        d(0.28, 0.28);
        d(0.72, 0.28);
        d(0.28, 0.72);
        d(0.72, 0.72);
        break;
      case 5:
        d(0.28, 0.28);
        d(0.72, 0.28);
        d(0.5, 0.5);
        d(0.28, 0.72);
        d(0.72, 0.72);
        break;
      case 6:
        d(0.28, 0.22);
        d(0.72, 0.22);
        d(0.28, 0.5);
        d(0.72, 0.5);
        d(0.28, 0.78);
        d(0.72, 0.78);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant final _DiceFacePainter old) => old.face != face;
}
