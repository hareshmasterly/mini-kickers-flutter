import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:mini_kickers/utils/ad_manager.dart';

/// Drop-in adaptive AdMob banner.
///
/// Pinned at the bottom of any screen. Sizes itself to the available
/// width via `getAnchoredAdaptiveBannerAdSize`, so it looks correct on
/// phones (full width strip) and tablets (taller leaderboard-ish).
/// Fails silent — if the ad can't load, the widget renders nothing,
/// the surrounding layout is unchanged.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

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
          'BannerAd: getAnchoredAdaptiveBannerAdSize returned null '
          '(width=$width) — skipping',
        );
      }
      return;
    }
    if (kDebugMode) {
      debugPrint(
        'BannerAd: requesting size=${size.width}x${size.height} '
        'unit=${AdManager.instance.bannerAdUnitId}',
      );
    }
    final BannerAd ad = BannerAd(
      adUnitId: AdManager.instance.bannerAdUnitId,
      size: size,
      request: AdManager.instance.adRequest,
      listener: BannerAdListener(
        onAdLoaded: (final Ad _) {
          if (kDebugMode) debugPrint('BannerAd: loaded');
          if (!mounted) return;
          setState(() {
            _loaded = true;
            _loading = false;
          });
        },
        onAdFailedToLoad: (final Ad ad, final LoadAdError err) {
          ad.dispose();
          if (kDebugMode) debugPrint('BannerAd: failed to load — $err');
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
