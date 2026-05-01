import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/utils/ad_manager.dart';

// Re-export AdPlacement so screens that include this widget can pass the
// placement parameter without a second import.
export 'package:mini_kickers/utils/ad_manager.dart' show AdPlacement;

/// Drop-in adaptive AdMob banner.
///
/// Pinned at the bottom of any screen. Sizes itself to the available
/// width via `getAnchoredAdaptiveBannerAdSize`, so it looks correct on
/// phones (full width strip) and tablets (taller leaderboard-ish).
/// Fails silent — if the ad can't load, the widget renders nothing,
/// the surrounding layout is unchanged.
///
/// [placement] selects the AdMob unit id — each placement has a distinct
/// id so per-screen revenue and fill rate can be tracked independently
/// in the AdMob console.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key, required this.placement});

  final AdPlacement placement;

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _loading = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ad == null && !_loading) {
      _loadAd();
    }
  }

  Future<void> _loadAd() async {
    _loading = true;
    // Hard gate: NEVER hit AdMob when the master `show_ads` switch is
    // off — even though parent screens already condition on this flag
    // before mounting BannerAdWidget, having the check here guarantees
    // a single point of truth (and protects against any future caller
    // that forgets the parent gate).
    if (!SettingsService.instance.showAds) {
      _loading = false;
      if (kDebugMode) {
        debugPrint(
          'BannerAd[${widget.placement.name}]: skipped — show_ads=false',
        );
      }
      return;
    }
    // Block until the SDK is initialised. Without this guard,
    // `BannerAd.load()` runs against an un-booted SDK on first launch
    // and fails silently — widget stays as `SizedBox.shrink` forever.
    await AdManager.instance.ready;
    if (!mounted) {
      _loading = false;
      return;
    }
    final int width = MediaQuery.of(context).size.width.truncate();
    final AnchoredAdaptiveBannerAdSize? size =
        await AdSize.getAnchoredAdaptiveBannerAdSize(
      Orientation.landscape,
      width,
    );
    if (!mounted || size == null) {
      _loading = false;
      if (kDebugMode) {
        debugPrint(
          'BannerAd[${widget.placement.name}]: '
          'getAnchoredAdaptiveBannerAdSize returned null '
          '(width=$width) — skipping',
        );
      }
      return;
    }
    final String unitId =
        AdManager.instance.adUnitIdFor(widget.placement);
    if (kDebugMode) {
      debugPrint(
        'BannerAd[${widget.placement.name}]: requesting '
        'size=${size.width}x${size.height} unit=$unitId',
      );
    }
    final BannerAd ad = BannerAd(
      adUnitId: unitId,
      size: size,
      request: AdManager.instance.adRequest,
      listener: BannerAdListener(
        onAdLoaded: (final Ad _) {
          if (kDebugMode) {
            debugPrint('BannerAd[${widget.placement.name}]: loaded');
          }
          if (!mounted) return;
          setState(() {
            _loaded = true;
            _loading = false;
          });
        },
        onAdFailedToLoad: (final Ad ad, final LoadAdError err) {
          ad.dispose();
          if (kDebugMode) {
            debugPrint(
              'BannerAd[${widget.placement.name}]: failed to load — $err',
            );
          }
          if (!mounted) return;
          setState(() {
            _ad = null;
            _loaded = false;
            _loading = false;
          });
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final BannerAd? ad = _ad;
    if (!_loaded || ad == null) {
      // Reserve no space until the ad is ready — avoids a blank strip
      // appearing then jumping when the ad lands.
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
