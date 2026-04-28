import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:mini_kickers/data/models/faq.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads FAQs from Firestore (`faqs` collection) and caches them locally.
///
/// Resolution order — same pattern as [SettingsService]:
///   1. Live Firestore data (latest fetch)
///   2. Cached JSON from a prior successful fetch
///   3. Hardcoded fallback in [_fallbackFaqs] (only used on a brand-new
///      install with no network — keeps the Guide screen functional
///      offline).
///
/// Documents are sorted ascending by their `order` field so editors can
/// control display order from the Firestore console.
class FaqService extends ChangeNotifier {
  FaqService._();

  static final FaqService instance = FaqService._();

  static const String _kFaqCache = 'pref.faqs.cache';

  SharedPreferences? _prefs;
  List<Faq>? _remote;
  bool _loading = false;

  /// `true` while the first network fetch is in flight (and no cache is
  /// available). UI can show a spinner during this window.
  bool get isLoadingFirstTime => _loading && _remote == null;

  /// Best-effort list of FAQs to render right now. Falls through cache
  /// → hardcoded fallback if no remote data has loaded yet.
  List<Faq> get faqs {
    if (_remote != null && _remote!.isNotEmpty) return _remote!;
    return _fallbackFaqs;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadCache();
  }

  void _loadCache() {
    final String? cached = _prefs?.getString(_kFaqCache);
    if (cached == null) return;
    try {
      final List<dynamic> raw = json.decode(cached) as List<dynamic>;
      _remote = raw
          .whereType<Map<String, dynamic>>()
          .map(Faq.fromMap)
          .toList()
        ..sort((final Faq a, final Faq b) => a.order.compareTo(b.order));
    } catch (e) {
      if (kDebugMode) debugPrint('FaqService: stale cache discarded ($e)');
    }
  }

  /// Pulls all docs from `faqs`, sorted by `order`. If a cache already
  /// exists the fetch runs in the background; otherwise the caller can
  /// `await` to delay UI until first results come in (with [timeout]
  /// guarding against hangs).
  Future<void> fetchRemote({
    final Duration timeout = const Duration(seconds: 5),
  }) async {
    final bool hasCache = _remote != null && _remote!.isNotEmpty;
    final Future<void> fetch = _runFetch(timeout);
    if (hasCache) {
      unawaited(fetch);
      return;
    }
    await fetch;
  }

  Future<void> _runFetch(final Duration timeout) async {
    _loading = true;
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection('faqs')
          .orderBy('order')
          .get()
          .timeout(timeout);

      final List<Faq> parsed = snap.docs
          .map((final QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              Faq.fromMap(d.data()))
          .toList();

      _remote = parsed;
      await _prefs?.setString(
        _kFaqCache,
        json.encode(parsed.map((final Faq f) => f.toMap()).toList()),
      );
      if (kDebugMode) {
        debugPrint('FaqService: loaded ${parsed.length} FAQs from Firestore');
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('FaqService: fetch failed ($e)');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Hardcoded fallback ────────────────────────────────────────────────
  // Only used when both the live network fetch and the local cache are
  // unavailable. Keep this list in sync with what's authoritative in
  // Firestore so a brand-new offline install still shows useful content.

  static const List<Faq> _fallbackFaqs = <Faq>[
    Faq(
      order: 1,
      question: 'How many players can play Mini Kickers?',
      answer:
          "Mini Kickers is designed strictly for 2 players — one Red, one Blue. There's no solo mode in the physical board game.",
    ),
    Faq(
      order: 2,
      question: 'What age group is this game for?',
      answer:
          'Recommended for kids aged 5–12, but the strategy is fun enough for parents and older players too.',
    ),
    Faq(
      order: 3,
      question: 'How long does a single match take?',
      answer:
          'A standard match lasts 15 minutes. In the app you can adjust this from Settings → Match Duration (5, 10, 15, or 20 minutes).',
    ),
    Faq(
      order: 4,
      question: 'Can I play Mini Kickers alone?',
      answer:
          'The physical board game requires two players. The mobile app is currently 2-player on the same device — pass the device on each turn.',
    ),
    Faq(
      order: 5,
      question: 'How does scoring work?',
      answer:
          "When you push the football into the opponent's goal mouth, you score 1 point. The board then resets — football back to the centre — and the conceded team kicks off the next play.",
    ),
    Faq(
      order: 6,
      question: "What if I roll a number I can't use?",
      answer:
          'If none of your tokens can make a legal move with the rolled value, your turn ends automatically and the opponent rolls.',
    ),
    Faq(
      order: 7,
      question: 'Can I customise team names and colours?',
      answer:
          'Yes! In the Settings screen you can rename both teams (e.g. Aarav vs Diya) and pick from 5 colour palettes including Fire vs Ice, Royal vs Gold, and more.',
    ),
  ];
}
