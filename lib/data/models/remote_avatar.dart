import 'package:cloud_firestore/cloud_firestore.dart';

/// One entry in the editor-curated `avatars/` Firestore collection.
///
/// Schema (every field has a safe default — minimal Firestore docs
/// like `{display_name, emoji}` work without specifying `order`,
/// `enabled`, `is_default`, or `category`):
///
///   • doc ID                 — avatar id, lowercased (e.g. "tiger")
///   • display_name (string)  — UI label ("Tiger")
///   • emoji (string)         — fallback glyph rendered when image_url
///                              is missing or fails to load
///   • image_url (string?)    — optional CDN/Storage PNG; preferred
///                              over emoji when present
///   • order (int?)           — display order in picker; missing →
///                              treated as 999 (sorted to end)
///   • enabled (bool?)        — show in picker + use in random pool;
///                              missing → true (default visible)
///   • is_default (bool?)     — included in handle-generator's random
///                              pool; missing → true (default in pool)
///   • category (string?)     — grouping for future segmented pickers
///                              ("animal", "sport", "holiday"); missing
///                              → "animal"
///   • created_at (timestamp?) — when added; lets the client show a
///                              "NEW" badge on recent additions
class RemoteAvatar {
  const RemoteAvatar({
    required this.id,
    required this.displayName,
    required this.emoji,
    this.imageUrl,
    this.order = 999,
    this.enabled = true,
    this.isDefault = true,
    this.category = 'animal',
    this.createdAt,
  });

  final String id;
  final String displayName;
  final String emoji;
  final String? imageUrl;
  final int order;
  final bool enabled;
  final bool isDefault;
  final String category;
  final Timestamp? createdAt;

  /// Bulletproof factory — every field has a fallback so a partially-
  /// configured Firestore doc (e.g. just `display_name + emoji`) never
  /// crashes the parser. The user's existing docs missing `order` and
  /// `is_default` will get sensible defaults.
  factory RemoteAvatar.fromMap(
    final String id,
    final Map<String, dynamic> data,
  ) {
    return RemoteAvatar(
      id: id,
      displayName: (data['display_name'] as String?) ?? _capitalize(id),
      emoji: (data['emoji'] as String?) ?? '⚽',
      imageUrl: data['image_url'] as String?,
      order: (data['order'] as num?)?.toInt() ?? 999,
      enabled: (data['enabled'] as bool?) ?? true,
      isDefault: (data['is_default'] as bool?) ?? true,
      category: (data['category'] as String?) ?? 'animal',
      createdAt: data['created_at'] as Timestamp?,
    );
  }

  static String _capitalize(final String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
