class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final int watchTimeSeconds;
  final DateTime? createdAt;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.watchTimeSeconds = 0,
    this.createdAt,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    DateTime? parsedCreatedAt;
    final raw = data['createdAt'];
    if (raw is String && raw.isNotEmpty) {
      try { parsedCreatedAt = DateTime.parse(raw); } catch (_) {}
    }

    return UserProfile(
      uid: uid,
      email: (data['email'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? '',
      watchTimeSeconds: (data['watchTimeSeconds'] as int?) ?? 0,
      createdAt: parsedCreatedAt,
    );
  }

  String get formattedWatchTime {
    final h = watchTimeSeconds ~/ 3600;
    final m = (watchTimeSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
