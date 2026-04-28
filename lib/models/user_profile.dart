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
    return UserProfile(
      uid: uid,
      email: (data['email'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? '',
      watchTimeSeconds: (data['watchTimeSeconds'] as int?) ?? 0,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as dynamic).toDate()
          : null,
    );
  }

  String get formattedWatchTime {
    final h = watchTimeSeconds ~/ 3600;
    final m = (watchTimeSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
