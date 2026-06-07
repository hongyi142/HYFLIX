class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final int watchTimeSeconds;
  final DateTime? createdAt;
  final String? photoBase64;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.watchTimeSeconds = 0,
    this.createdAt,
    this.photoBase64,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    DateTime? parsedCreatedAt;
    final raw = data['createdAt'];
    if (raw is String && raw.isNotEmpty) {
      try { parsedCreatedAt = DateTime.parse(raw); } catch (_) {}
    }

    final photoRaw = (data['photoBase64'] as String?) ?? '';

    return UserProfile(
      uid: uid,
      email: (data['email'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? '',
      watchTimeSeconds: (data['watchTimeSeconds'] as int?) ?? 0,
      createdAt: parsedCreatedAt,
      photoBase64: photoRaw.isEmpty ? null : photoRaw,
    );
  }

  String get formattedWatchTime {
    final h = watchTimeSeconds ~/ 3600;
    final m = (watchTimeSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
