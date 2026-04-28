import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/main.dart';
import 'package:mini_kickers/routes/routes_name.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/flavors.dart';
import 'package:mini_kickers/views/home/widget/stadium_background.dart';
import 'package:mini_kickers/views/settings/widget/palette_picker.dart';
import 'package:mini_kickers/views/settings/widget/player_name_tile.dart';
import 'package:mini_kickers/views/settings/widget/settings_tile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService.instance;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(final BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.stadiumDeep,
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const StadiumBackground(),
            SafeArea(child: _buildContent(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(final BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: <Widget>[
          _buildHeader(context),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SettingsSectionLabel(text: 'AUDIO'),
                  SettingsTile(
                    icon: Icons.volume_up_rounded,
                    title: 'Sound Effects',
                    subtitle: 'Dice rolls, kicks, goal cheers',
                    iconColor: AppColors.brandYellow,
                    onTap: () => _toggleSound(),
                    trailing: _Switch(
                      value: _settings.soundEnabled,
                      onChanged: (final _) => _toggleSound(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SettingsTile(
                    icon: Icons.music_note_rounded,
                    title: 'Background Music',
                    subtitle: 'Stadium ambient track',
                    iconColor: AppColors.brandYellow,
                    onTap: () => _toggleMusic(),
                    trailing: _Switch(
                      value: _settings.musicEnabled,
                      onChanged: (final bool v) => _toggleMusic(force: v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SettingsTile(
                    icon: Icons.vibration_rounded,
                    title: 'Haptic Feedback',
                    subtitle: _settings.hapticsEnabled
                        ? 'Tap to test  ·  switch to disable'
                        : 'Vibrations on tap and events',
                    iconColor: AppColors.brandYellow,
                    onTap: () {
                      if (_settings.hapticsEnabled) {
                        // Tap to test
                        AudioHelper.testHaptic();
                      } else {
                        _settings.setHapticsEnabled(true);
                      }
                    },
                    trailing: _Switch(
                      value: _settings.hapticsEnabled,
                      onChanged: _settings.setHapticsEnabled,
                    ),
                  ),
                  const SettingsSectionLabel(text: 'GAMEPLAY'),
                  _MatchDurationTile(
                    current: _settings.matchSeconds,
                    onSelect: (final int seconds) async {
                      await _settings.setMatchSeconds(seconds);
                      AudioHelper.select();
                    },
                  ),
                  const SizedBox(height: 8),
                  SettingsTile(
                    icon: Icons.campaign_rounded,
                    title: 'Commentary Toasts',
                    subtitle: 'Floating commentary on the board',
                    iconColor: AppColors.limeBright,
                    onTap: () => _settings.setCommentaryEnabled(
                      !_settings.commentaryEnabled,
                    ),
                    trailing: _Switch(
                      value: _settings.commentaryEnabled,
                      onChanged: _settings.setCommentaryEnabled,
                    ),
                  ),
                  const SettingsSectionLabel(text: 'TEAMS'),
                  PalettePicker(
                    currentId: _settings.palette.id,
                    onSelect: (final String id) =>
                        _settings.setPalette(id),
                  ),
                  const SizedBox(height: 8),
                  PlayerNameTile(
                    team: Team.red,
                    initialName: _settings.redName,
                    onCommit: _settings.setRedName,
                  ),
                  const SizedBox(height: 8),
                  PlayerNameTile(
                    team: Team.blue,
                    initialName: _settings.blueName,
                    onCommit: _settings.setBlueName,
                  ),
                  const SettingsSectionLabel(text: 'INFO'),
                  SettingsTile(
                    icon: Icons.menu_book_rounded,
                    title: 'Game Guide',
                    subtitle:
                        'Rules, features, FAQ and contact info',
                    iconColor: AppColors.blueLight,
                    onTap: () => Navigator.of(context)
                        .pushNamed(RouteName.guideScreen),
                  ),
                  const SizedBox(height: 8),
                  SettingsTile(
                    icon: Icons.info_outline_rounded,
                    title: 'About',
                    subtitle:
                        'Version 1.0.0 · Flavor: $currentFlavor · ${FlavorConfig.title}',
                    iconColor: AppColors.muted,
                    onTap: () {},
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(final BuildContext context) {
    return Row(
      children: <Widget>[
        _BackButton(onTap: () {
          AudioHelper.select();
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        }),
        const SizedBox(width: 14),
        Text(
          'SETTINGS',
          style: AppFonts.bebasNeue(
            fontSize: 32,
            letterSpacing: 6,
            color: Colors.white,
            shadows: <Shadow>[
              Shadow(
                color: AppColors.accent.withValues(alpha: 0.45),
                blurRadius: 24,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _toggleSound() {
    final bool newValue = !_settings.soundEnabled;
    _settings.setSoundEnabled(newValue);
    if (newValue) AudioHelper.select();
  }

  Future<void> _toggleMusic({final bool? force}) async {
    final bool newValue = force ?? !_settings.musicEnabled;
    await _settings.setMusicEnabled(newValue);
    await AudioHelper.setMusicEnabled(enabled: newValue);
  }

}

class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(final BuildContext context) {
    return Switch.adaptive(
      value: value,
      onChanged: (final bool v) {
        AudioHelper.select();
        onChanged(v);
      },
      activeThumbColor: Colors.white,
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
      inactiveThumbColor: Colors.white.withValues(alpha: 0.6),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchDurationTile extends StatelessWidget {
  const _MatchDurationTile({required this.current, required this.onSelect});

  final int current;
  final void Function(int seconds) onSelect;

  @override
  Widget build(final BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      color: AppColors.limeBright.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.limeBright.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.timer_outlined,
                      color: AppColors.limeBright,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Match Duration',
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
                spacing: 8,
                runSpacing: 8,
                children: SettingsService.instance.availableMatchDurations
                    .map((final ({int seconds, String label}) d) {
                  final bool selected = d.seconds == current;
                  return GestureDetector(
                    onTap: () => onSelect(d.seconds),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.accent.withValues(alpha: 0.85)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? AppColors.accent
                              : Colors.white.withValues(alpha: 0.18),
                          width: selected ? 1.6 : 1,
                        ),
                        boxShadow: selected
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.5),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        d.label,
                        style: TextStyle(
                          color: selected ? Colors.black : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
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

