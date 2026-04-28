import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/theme/team_colors.dart';

class PlayerNameTile extends StatefulWidget {
  const PlayerNameTile({
    super.key,
    required this.team,
    required this.initialName,
    required this.onCommit,
  });

  final Team team;
  final String initialName;

  /// Called only when the user finishes editing with a non-empty value.
  /// (on submit / unfocus). Empty submissions are rejected and the field
  /// is restored to the previous name.
  final void Function(String name) onCommit;

  @override
  State<PlayerNameTile> createState() => _PlayerNameTileState();
}

class _PlayerNameTileState extends State<PlayerNameTile> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  late String _lastCommitted;

  @override
  void initState() {
    super.initState();
    _lastCommitted = widget.initialName;
    _controller = TextEditingController(text: widget.initialName);
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant final PlayerNameTile old) {
    super.didUpdateWidget(old);
    // External name change (e.g. someone reset the setting). Only sync if
    // the user isn't currently editing this field.
    if (widget.initialName != _lastCommitted && !_focus.hasFocus) {
      _lastCommitted = widget.initialName;
      _controller.text = widget.initialName;
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final String trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      // Reject blank: restore previous name silently.
      _controller.text = _lastCommitted;
      _controller.selection = TextSelection.collapsed(
        offset: _lastCommitted.length,
      );
      return;
    }
    final String upper = trimmed.toUpperCase();
    if (upper != _lastCommitted) {
      _lastCommitted = upper;
      widget.onCommit(upper);
    }
    // Snap field to the canonical (uppercased) form
    if (_controller.text != upper) {
      _controller.text = upper;
      _controller.selection = TextSelection.collapsed(offset: upper.length);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final Color teamColor = TeamColors.primary(widget.team);
    final Color teamLight = TeamColors.light(widget.team);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.3, -0.4),
                    colors: <Color>[
                      Color.lerp(teamColor, Colors.white, 0.3)!,
                      teamColor,
                    ],
                  ),
                  border: Border.all(color: teamLight, width: 2),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: teamColor.withValues(alpha: 0.6),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _firstLetter(_controller.text.isEmpty
                        ? widget.initialName
                        : _controller.text),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      shadows: <Shadow>[
                        Shadow(color: Colors.black54, blurRadius: 3),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  maxLength: 12,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (final _) {
                    _commit();
                    _focus.unfocus();
                  },
                  onTapOutside: (final _) {
                    _focus.unfocus();
                  },
                  onChanged: (final _) {
                    // Just rebuild to update avatar letter; do NOT save yet.
                    setState(() {});
                  },
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(12),
                  ],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                  cursorColor: teamLight,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: widget.team == Team.red ? 'RED' : 'BLUE',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                    border: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: teamLight.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: teamLight, width: 2),
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

String _firstLetter(final String s) {
  final String t = s.trim();
  if (t.isEmpty) return '?';
  return t[0].toUpperCase();
}
