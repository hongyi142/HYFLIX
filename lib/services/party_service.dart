import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';

const String _partyDbUrl =
    'https://hyflix-56557-default-rtdb.asia-southeast1.firebasedatabase.app';

/// Pin alphabet without look-alike characters (no 0/O, 1/I/L).
const String _pinAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// A party action failed. [message] is safe to show to the user.
class PartyException implements Exception {
  final String message;
  PartyException(this.message);

  @override
  String toString() => message;
}

/// The slice of a video player the watch-party sync needs. The native player
/// implements it over media_kit, so this file stays free of platform code.
abstract class PartyPlayer {
  bool get playing;
  bool get buffering;
  double get rate;
  Duration get position;
  Duration get duration;

  Stream<bool> get playingStream;
  Stream<double> get rateStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get bufferingStream;

  void play();
  void pause();
  void seek(Duration position);
  void setRate(double rate);
}

/// Describes what a room is playing. Guests use it to open the same title,
/// episode and (for torrents) the same release. It holds no stream URLs or
/// API keys, so every member resolves the stream with their own account.
class PartyMeta {
  final String title;
  final String posterUrl;
  final int? tmdbId;
  final String mediaType; // 'movie' or 'tv'
  final String sourceName; // VOD source name, or 'Torrent'
  final String? infoHash; // torrent identity (torrent rooms only)
  final int? fileIdx;
  final String year;
  // The host's stream mode ('torbox' or 'p2p') for torrent rooms. Guests must
  // match it, or they would silently stream a different way.
  final String? streamMode;

  const PartyMeta({
    required this.title,
    this.posterUrl = '',
    this.tmdbId,
    this.mediaType = 'movie',
    required this.sourceName,
    this.infoHash,
    this.fileIdx,
    this.year = '',
    this.streamMode,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'posterUrl': posterUrl,
        if (tmdbId != null) 'tmdbId': tmdbId,
        'mediaType': mediaType,
        'sourceName': sourceName,
        if (infoHash != null) 'infoHash': infoHash,
        if (fileIdx != null) 'fileIdx': fileIdx,
        'year': year,
        if (streamMode != null) 'streamMode': streamMode,
      };

  factory PartyMeta.fromJson(Map<String, dynamic> j) => PartyMeta(
        title: (j['title'] ?? '') as String,
        posterUrl: (j['posterUrl'] ?? '') as String,
        tmdbId: (j['tmdbId'] as num?)?.toInt(),
        mediaType: (j['mediaType'] ?? 'movie') as String,
        sourceName: (j['sourceName'] ?? '') as String,
        infoHash: j['infoHash'] as String?,
        fileIdx: (j['fileIdx'] as num?)?.toInt(),
        year: (j['year'] ?? '') as String,
        streamMode: j['streamMode'] as String?,
      );
}

/// REST helpers for the `parties` subtree of the Realtime Database.
class PartyService {
  static final Random _rng = Random.secure();

  static final ValueNotifier<PartySession?> _current = ValueNotifier(null);

  /// The party this device is currently in, if any. The app-wide badge
  /// listens to [currentListenable] so it stays visible for the whole session.
  static PartySession? get current => _current.value;
  static set current(PartySession? session) => _current.value = session;
  static ValueListenable<PartySession?> get currentListenable => _current;

  /// Shows an app-wide notice, for events the user should see on any page.
  static void Function(String message)? announce;

  /// Called when the host starts the show, or changes episode, while this
  /// device is not already watching it. The app opens the show for the guest.
  static void Function(PartySession session)? onRoomLive;

  /// Ends the party for everyone when hosting, or leaves it as a guest.
  static Future<void> endOrLeave(PartySession session) async {
    await session.close();
    if (identical(current, session)) current = null;
  }

  static String generatePin() => List.generate(
        8,
        (_) => _pinAlphabet[_rng.nextInt(_pinAlphabet.length)],
      ).join();

  static String normalisePin(String pin) =>
      pin.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  static String _roomUrl(String pin, [String suffix = '']) =>
      '$_partyDbUrl/parties/$pin$suffix.json';

  static Future<String?> _token() async {
    if (!await AuthService.ensureValidToken()) return null;
    return AuthService.idToken;
  }

  /// Turns a failed database response into a message the user can act on.
  static PartyException _failure(String action, http.Response res) {
    debugPrint('[Party] $action failed: HTTP ${res.statusCode} ${res.body}');
    if (res.statusCode == 401 || res.statusCode == 403) {
      return PartyException(
        'Parties are not enabled in the database yet. Publish the parties '
        'rules in the Firebase console, then try again.',
      );
    }
    return PartyException('$action failed (HTTP ${res.statusCode}).');
  }

  /// Returns the room, null when there is no room with this pin. Throws
  /// [PartyException] when the database refuses or cannot be reached.
  static Future<Map<String, dynamic>?> _getRoom(String pin) async {
    final token = await _token();
    if (token == null) {
      throw PartyException('Sign in again to use parties.');
    }
    final http.Response res;
    try {
      res = await http
          .get(Uri.parse('${_roomUrl(pin)}?auth=$token'))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[Party] GET room failed: $e');
      throw PartyException('Could not reach the party service. Check your connection.');
    }
    if (res.statusCode != 200) throw _failure('Reading the party', res);
    final body = json.decode(res.body);
    return body is Map<String, dynamic> ? body : null;
  }

  /// Creates a room with a fresh pin and returns the pin. Throws
  /// [PartyException] with a message the user can act on.
  static Future<String> createRoom({
    required PartyMeta meta,
    required int episode,
  }) async {
    final token = await _token();
    final uid = AuthService.uid;
    if (token == null || uid == null) {
      throw PartyException('Sign in again to start a party.');
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      final pin = generatePin();
      if (await _getRoom(pin) != null) continue; // pin collision
      final now = DateTime.now().millisecondsSinceEpoch;
      try {
        final res = await http
            .put(
              Uri.parse('${_roomUrl(pin)}?auth=$token'),
              body: json.encode({
                'host': uid,
                'createdAt': now,
                'meta': meta.toJson(),
                'episode': {'n': episode, 'by': uid, 'ts': now},
                'state': {
                  'playing': false,
                  'pos': 0,
                  'rate': 1.0,
                  'ts': now,
                  'by': uid,
                  'seek': false,
                },
                'members': {
                  uid: {'name': AuthService.displayName ?? 'Host', 'ts': now},
                },
              }),
            )
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) return pin;
        throw _failure('Creating the party', res);
      } on PartyException {
        rethrow;
      } catch (e) {
        debugPrint('[Party] PUT room failed: $e');
        throw PartyException('Could not reach the party service. Check your connection.');
      }
    }
    throw PartyException('Could not find a free PIN. Try again.');
  }

  /// Returns the room's metadata, or null if no room has this pin.
  static Future<PartyMeta?> lookup(String pin) async {
    final room = await _getRoom(normalisePin(pin));
    final meta = room?['meta'];
    if (meta is! Map) return null;
    return PartyMeta.fromJson(Map<String, dynamic>.from(meta));
  }

  static Future<void> put(String pin, String suffix, Object? data) async {
    final token = await _token();
    if (token == null) return;
    try {
      await http
          .put(
            Uri.parse('${_roomUrl(pin, suffix)}?auth=$token'),
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  static Future<void> closeRoom(String pin) => put(pin, '', null);

  static Future<void> setMember(String pin, bool present) async {
    final uid = AuthService.uid;
    if (uid == null) return;
    await put(
      pin,
      '/members/$uid',
      present
          ? {
              'name': AuthService.displayName ?? 'Guest',
              'ts': DateTime.now().millisecondsSinceEpoch,
            }
          : null,
    );
  }
}

/// A live watch-party connection. It listens to the room over the server's
/// event stream and, once attached to a [PartyPlayer], keeps playback in
/// sync with the other members. Anyone can play, pause, seek, change speed or
/// change episode; the most recent action wins.
class PartySession {
  PartySession({
    required this.pin,
    required this.meta,
    required this.isHost,
  });

  final String pin;
  final PartyMeta meta;
  final bool isHost;

  /// Display names of the members currently in the room.
  final ValueNotifier<List<String>> members = ValueNotifier(const []);

  /// True once the host has started the show. Guests wait until then.
  final ValueNotifier<bool> live = ValueNotifier(false);

  /// The episode the host is on, for screens that follow it.
  final ValueNotifier<int> episodeNotifier = ValueNotifier(0);

  /// True while this device's player is showing the party's episode.
  final ValueNotifier<bool> playerOpen = ValueNotifier(false);

  /// True while a show screen for this party is open, so it isn't opened twice.
  bool roomScreenOpen = false;
  bool _liveSeeded = false;

  /// Host: marks the show as started so guests are brought in.
  Future<void> markLive() async {
    if (!isHost || _closed || live.value) return;
    live.value = true;
    await PartyService.put(pin, '/live', true);
  }

  /// Opens the show for a guest, unless it is already on screen.
  void _bringGuestIn() {
    if (playerOpen.value || roomScreenOpen) return;
    PartyService.onRoomLive?.call(this);
  }

  /// The one line of status shown over the player, e.g. "Ana is buffering".
  /// A new status replaces the old one, so events never pile up on screen.
  final ValueNotifier<String?> status = ValueNotifier(null);
  Timer? _statusTimer;

  /// Shows [text] as the current status. It clears after [hold], or stays
  /// until replaced when [hold] is null.
  void showStatus(String text, {Duration? hold = const Duration(seconds: 3)}) {
    _statusTimer?.cancel();
    status.value = text;
    if (hold != null) {
      _statusTimer = Timer(hold, () => status.value = null);
    }
  }

  Map<String, String> _knownNames = {};
  bool _membersSeeded = false;
  String? _waitKey; // who we are waiting for, while playback is held

  /// Called when another member switches episode.
  void Function(int episode)? onRemoteEpisode;

  /// Called when the host ends the party.
  void Function()? onEnded;

  bool _closed = false;
  bool get isClosed => _closed;

  Map<String, dynamic>? _room;
  bool _roomSeen = false;
  int _lastStateTs = 0;
  int _lastEpisodeTs = 0;
  int _episode = 0;
  // Season and the episode number within that season, so guests can find the
  // same episode even when their list is laid out differently (multi-season).
  int episodeSeason = 1;
  int episodeNumber = 1;
  int get episode => _episode;
  http.Client? _client;

  // Sync bookkeeping
  PartyPlayer? _player;
  final List<StreamSubscription> _subs = [];
  Timer? _heartbeat;
  DateTime _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastPos = Duration.zero;
  DateTime _lastPosAt = DateTime.now();
  Map<String, dynamic>? _pendingCatchUp;
  DateTime? _pendingCatchUpAt;
  DateTime? _lastStateReceivedAt;
  bool? _lastPlaying;

  // Ready check: playback waits while a member is still loading or buffering.
  // Wait times are measured on this device's clock, so skew can't matter.
  static const Duration _readyTimeout = Duration(seconds: 30);
  final Map<String, DateTime> _unreadySince = {};
  final ValueNotifier<List<String>> waitingFor = ValueNotifier(const []);
  bool? _lastReadyWritten;
  bool _autoPaused = false;
  DateTime _autoPausedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _waitTimer;

  static const Duration _suppressWindow = Duration(milliseconds: 1500);
  static const Duration _driftTolerance = Duration(milliseconds: 1500);
  static const Duration _seekThreshold = Duration(milliseconds: 2000);
  static const Duration _heartbeatEvery = Duration(seconds: 5);

  String get _myUid => AuthService.uid ?? '';

  /// Starts the live connection and announces this user as a member.
  Future<void> connect() async {
    unawaited(_streamLoop());
    await PartyService.setMember(pin, true);
  }

  Future<void> _streamLoop() async {
    var backoff = const Duration(seconds: 1);
    while (!_closed) {
      try {
        await _openStream();
      } catch (e) {
        debugPrint('[Party] stream error: $e');
      }
      if (_closed) break;
      await Future.delayed(backoff);
      final next = backoff * 2;
      backoff = next < const Duration(seconds: 20)
          ? next
          : const Duration(seconds: 20);
    }
  }

  Future<void> _openStream() async {
    final token = await PartyService._token();
    if (token == null) throw StateError('not signed in');
    final client = http.Client();
    _client = client;
    try {
      final req = http.Request(
        'GET',
        Uri.parse('$_partyDbUrl/parties/$pin.json?auth=$token'),
      )..headers['Accept'] = 'text/event-stream';
      final res = await client.send(req).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');

      String? eventType;
      await for (final line
          in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (_closed) break;
        if (line.startsWith('event:')) {
          eventType = line.substring(6).trim();
        } else if (line.startsWith('data:') && eventType != null) {
          final payload = line.substring(5).trim();
          if (payload.isEmpty) continue;
          final data = json.decode(payload) as Map<String, dynamic>;
          _onServerEvent(eventType, data['path'] as String? ?? '/', data['data']);
        }
      }
    } finally {
      client.close();
      _client = null;
    }
  }

  // ── Room snapshot maintenance ──────────────────────────────────────

  void _onServerEvent(String type, String path, Object? data) {
    if (type == 'auth_revoked' || type == 'cancel') {
      _client?.close();
      return;
    }
    if (type != 'put' && type != 'patch') return;

    if (path == '/') {
      if (type == 'put') {
        _room = data is Map ? Map<String, dynamic>.from(data) : null;
      } else if (data is Map && _room != null) {
        _room!.addAll(Map<String, dynamic>.from(data));
      }
    } else {
      _applyAtPath(path, type, data);
    }
    _afterRoomChange();
  }

  /// Applies a put/patch at a nested path such as `/state` or `/members/uid`.
  void _applyAtPath(String path, String type, Object? data) {
    _room ??= <String, dynamic>{};
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    Map<String, dynamic> node = _room!;
    for (var i = 0; i < segments.length - 1; i++) {
      final key = segments[i];
      final child = node[key];
      if (child is! Map<String, dynamic>) {
        node[key] = <String, dynamic>{};
      }
      node = node[key] as Map<String, dynamic>;
    }
    final last = segments.last;
    if (type == 'put') {
      if (data == null) {
        node.remove(last);
      } else {
        node[last] = data;
      }
    } else if (data is Map) {
      final current = node[last];
      final merged = current is Map<String, dynamic>
          ? current
          : <String, dynamic>{};
      merged.addAll(Map<String, dynamic>.from(data));
      node[last] = merged;
    }
  }

  void _afterRoomChange() {
    final room = _room;
    if (room == null) {
      if (_roomSeen && !isHost && !_closed) {
        // The host ended the party: stop syncing and tell the player.
        _closed = true;
        detach();
        _client?.close();
        if (identical(PartyService.current, this)) PartyService.current = null;
        PartyService.announce?.call('The host ended the party');
        onEnded?.call();
      }
      _roomSeen = false;
      return;
    }
    _roomSeen = true;

    final membersRaw = room['members'];
    if (membersRaw is Map) {
      members.value = membersRaw.values
          .whereType<Map>()
          .map((m) => (m['name'] ?? 'Guest').toString())
          .toList();
    }

    // Track who is still loading or buffering (ignoring ourselves).
    final readyRaw = room['ready'];
    final readyMap = readyRaw is Map ? readyRaw : const {};
    final memberIds = membersRaw is Map
        ? membersRaw.keys.map((k) => k.toString()).toSet()
        : <String>{};

    // One line when someone joins or leaves. The first snapshot is just the
    // starting state, so it doesn't announce anyone.
    final names = <String, String>{};
    if (membersRaw is Map) {
      membersRaw.forEach((key, value) {
        final name = value is Map ? value['name'] : null;
        names[key.toString()] = (name ?? 'Guest').toString();
      });
    }
    if (_membersSeeded) {
      for (final e in names.entries) {
        if (e.key != _myUid && !_knownNames.containsKey(e.key)) {
          showStatus('${e.value} joined');
        }
      }
      for (final e in _knownNames.entries) {
        if (e.key != _myUid && !names.containsKey(e.key)) {
          showStatus('${e.value} left');
        }
      }
    }
    _knownNames = names;
    _membersSeeded = true;

    final now = DateTime.now();
    _unreadySince.removeWhere((uid, _) => !memberIds.contains(uid));
    for (final uid in memberIds) {
      if (uid == _myUid) continue;
      if (readyMap[uid] == false) {
        _unreadySince.putIfAbsent(uid, () => now);
      } else {
        _unreadySince.remove(uid);
      }
    }

    // Host start. Guests who join before this wait in the room; when it turns
    // true they are brought in. A room that is already live when they join
    // just opens normally.
    final isLive = room['live'] == true;
    final wasLive = live.value;
    if (isLive != wasLive) live.value = isLive;
    if (!_liveSeeded) {
      _liveSeeded = true;
      if (!isLive && !isHost) {
        showStatus('Waiting for the host to start', hold: null);
      }
    } else if (isLive && !wasLive && !isHost) {
      showStatus('The host has started', hold: const Duration(seconds: 2));
      _bringGuestIn();
    }

    final episodeRaw = room['episode'];
    if (episodeRaw is Map) {
      final n = (episodeRaw['n'] as num?)?.toInt() ?? 0;
      final ts = (episodeRaw['ts'] as num?)?.toInt() ?? 0;
      final by = episodeRaw['by'] as String?;
      if (ts > _lastEpisodeTs) {
        _lastEpisodeTs = ts;
        final season = (episodeRaw['season'] as num?)?.toInt() ?? episodeSeason;
        final number = (episodeRaw['num'] as num?)?.toInt() ?? episodeNumber;
        final changed = n != _episode || season != episodeSeason || number != episodeNumber;
        episodeSeason = season;
        episodeNumber = number;
        if (changed) {
          _episode = n;
          episodeNotifier.value = n;
          if (by != _myUid) {
            onRemoteEpisode?.call(n);
            if (live.value) _bringGuestIn();
          }
        }
      }
    }

    final stateRaw = room['state'];
    if (stateRaw is Map) {
      final ts = (stateRaw['ts'] as num?)?.toInt() ?? 0;
      final by = stateRaw['by'] as String?;
      if (ts >= _lastStateTs) {
        _lastStateTs = ts;
        _lastStateReceivedAt = DateTime.now();
        if (by != _myUid) {
          _applyRemote(Map<String, dynamic>.from(stateRaw),
              receivedAt: _lastStateReceivedAt);
        }
      }
    }

    _enforceWait();
  }

  List<String> _waitingNames() {
    final now = DateTime.now();
    final names = <String>[];
    _unreadySince.forEach((uid, since) {
      if (now.difference(since) < _readyTimeout) names.add(_nameFor(uid));
    });
    return names;
  }

  /// Pauses playback while others are loading, and resumes once everyone is
  /// ready. Only a pause this device made itself is undone automatically.
  void _enforceWait() {
    final player = _player;
    if (_closed || player == null || !_hasMedia) {
      _waitTimer?.cancel();
      _waitTimer = null;
      waitingFor.value = const [];
      return;
    }

    final waiting = _waitingNames();
    waitingFor.value = waiting;
    if (waiting.isNotEmpty) {
      // Re-check periodically so the wait ends when the timeout passes.
      _waitTimer ??=
          Timer.periodic(const Duration(seconds: 5), (_) => _enforceWait());
      if (player.playing) {
        _autoPaused = true;
        _autoPausedAt = DateTime.now();
        player.pause();
      }
      // Set the line only when the waiting group changes, not on every update.
      final key = waiting.join(',');
      if (key != _waitKey) {
        _waitKey = key;
        final who = waiting.join(', ');
        showStatus(
          waiting.length == 1 ? '$who is buffering' : '$who are buffering',
          hold: null,
        );
      }
    } else {
      _waitTimer?.cancel();
      _waitTimer = null;
      if (_autoPaused) {
        _autoPaused = false;
        player.play();
      }
      if (_waitKey != null) {
        _waitKey = null;
        showStatus('Back in sync', hold: const Duration(seconds: 2));
      }
    }
  }

  /// Publishes this device's readiness so the others can wait for it.
  void _setReady(bool ready) {
    if (_lastReadyWritten == ready) return;
    _lastReadyWritten = ready;
    if (_myUid.isEmpty) return;
    unawaited(PartyService.put(pin, '/ready/$_myUid', ready));
  }

  /// Ready means media is loaded and not buffering.
  void _updateReady() {
    final player = _player;
    if (player == null) return;
    _setReady(_hasMedia && !player.buffering);
  }

  // ── Local player → room ────────────────────────────────────────────

  /// Attaches [player]. Its local actions are published and
  /// remote actions are applied to it.
  void attach(PartyPlayer player) {
    detach();
    _player = player;
    playerOpen.value = true;
    _lastPos = player.position;
    _lastPosAt = DateTime.now();
    _lastPlaying = player.playing;
    _pendingCatchUp = _room?['state'] is Map
        ? Map<String, dynamic>.from(_room!['state'] as Map)
        : null;
    _pendingCatchUpAt = _lastStateReceivedAt;
    _setReady(false); // not loaded yet; others wait until it is

    _subs.add(player.bufferingStream.listen((_) => _updateReady()));
    _subs.add(player.durationStream.listen((_) => _updateReady()));

    _subs.add(player.playingStream.listen((playing) {
      // A pause the user makes cancels the automatic resume.
      if (!playing &&
          DateTime.now().difference(_autoPausedAt) > const Duration(seconds: 1)) {
        _autoPaused = false;
      }
      if (!_hasMedia || _isSuppressed) return;
      if (_lastPlaying == playing) return;
      _lastPlaying = playing;
      _publish();
    }));
    _subs.add(player.rateStream.listen((_) {
      if (!_hasMedia || _isSuppressed) return;
      _publish();
    }));
    _subs.add(player.positionStream.listen(_onLocalPosition));
    _subs.add(player.durationStream.listen((d) {
      final pending = _pendingCatchUp;
      if (d > Duration.zero && pending != null) {
        _pendingCatchUp = null;
        _applyRemote(pending, receivedAt: _pendingCatchUpAt);
      }
    }));

    _heartbeat = Timer.periodic(_heartbeatEvery, (_) {
      if (_hasMedia && player.playing) _publish();
    });
  }

  void detach() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _heartbeat?.cancel();
    _heartbeat = null;
    _waitTimer?.cancel();
    _waitTimer = null;
    _autoPaused = false;
    if (_lastReadyWritten != null && _myUid.isNotEmpty) {
      // No player here any more, so stop making others wait for us.
      unawaited(PartyService.put(pin, '/ready/$_myUid', null));
    }
    _lastReadyWritten = null;
    _player = null;
    playerOpen.value = false;
  }

  bool get _hasMedia =>
      (_player?.duration ?? Duration.zero) > Duration.zero;

  bool get _isSuppressed => DateTime.now().isBefore(_suppressUntil);

  void _onLocalPosition(Duration pos) {
    final player = _player;
    if (player == null || !_hasMedia) return;
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastPosAt).inMilliseconds;
    final expected = player.playing
        ? _lastPos +
            Duration(milliseconds: (elapsedMs * player.rate).round())
        : _lastPos;
    final jump = (pos - expected).abs();

    if (!_isSuppressed && !player.buffering && jump > _seekThreshold) {
      _publish(seek: true);
    }
    _lastPos = pos;
    _lastPosAt = now;
  }

  Future<void> _publish({bool seek = false}) async {
    final player = _player;
    if (player == null || _closed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastStateTs = max(_lastStateTs, now);
    await PartyService.put(pin, '/state', {
      'playing': player.playing,
      'pos': player.position.inMilliseconds,
      'rate': player.rate,
      'ts': now,
      'by': _myUid,
      'seek': seek,
    });
  }

  /// Shares a local episode change with the room.
  Future<void> publishEpisode(
    int episode, {
    int season = 1,
    int number = 1,
  }) async {
    if (_closed) return;
    if (episode == _episode && season == episodeSeason && number == episodeNumber) {
      return;
    }
    _episode = episode;
    episodeSeason = season;
    episodeNumber = number;
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastEpisodeTs = max(_lastEpisodeTs, now);
    await PartyService.put(pin, '/episode', {
      'n': episode,
      'season': season,
      'num': number,
      'by': _myUid,
      'ts': now,
    });
  }

  // ── Room → local player ───────────────────────────────────────────

  void _applyRemote(Map<String, dynamic> s, {DateTime? receivedAt}) {
    final player = _player;
    if (player == null || !_hasMedia) {
      _pendingCatchUp = s;
      _pendingCatchUpAt = receivedAt;
      return;
    }
    _suppressUntil = DateTime.now().add(_suppressWindow);

    final playing = s['playing'] == true;
    final rate = (s['rate'] as num?)?.toDouble() ?? 1.0;
    final forceSeek = s['seek'] == true;
    // While the host was playing, the stored position has moved on since we
    // received it. Advance it by the local time that has passed. This uses
    // only this device's clock, so clock skew between devices can't affect it.
    var target = Duration(milliseconds: (s['pos'] as num?)?.toInt() ?? 0);
    if (playing && !forceSeek && receivedAt != null) {
      final elapsedMs = DateTime.now().difference(receivedAt).inMilliseconds;
      if (elapsedMs > 0 && elapsedMs < 10 * 60 * 1000) {
        target += Duration(milliseconds: (elapsedMs * rate).round());
      }
    }
    final who = _nameFor(s['by'] as String?);
    final wasPlaying = player.playing;

    if (rate != player.rate) player.setRate(rate);
    if (playing != wasPlaying) {
      playing ? player.play() : player.pause();
    }
    final drift = (player.position - target).abs();
    if (forceSeek || drift > _driftTolerance) {
      player.seek(target);
      _lastPos = target;
      _lastPosAt = DateTime.now();
    }
    _lastPlaying = playing;

    if (forceSeek) {
      showStatus('$who skipped to ${_format(target)}');
    } else if (playing != wasPlaying && _waitKey == null) {
      // While someone is buffering, that line stays up instead of this one.
      showStatus(playing ? '$who resumed' : '$who paused');
    }
  }

  String _nameFor(String? uid) {
    final members = _room?['members'];
    if (uid != null && members is Map && members[uid] is Map) {
      return (members[uid] as Map)['name']?.toString() ?? 'Someone';
    }
    return 'Someone';
  }

  static String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  /// Room metadata as last seen from the server. The host can change the
  /// torrent release after the room is created, so guests read it live.
  PartyMeta get currentMeta {
    final raw = _room?['meta'];
    return raw is Map
        ? PartyMeta.fromJson(Map<String, dynamic>.from(raw))
        : meta;
  }

  /// Host publishes the torrent release being watched so guests match it.
  Future<void> shareRelease(String infoHash, int fileIdx) async {
    if (_closed || !isHost) return;
    await PartyService.put(pin, '/meta/infoHash', infoHash);
    await PartyService.put(pin, '/meta/fileIdx', fileIdx);
  }

  /// The host ends the party for everyone. Guests just leave.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _statusTimer?.cancel();
    detach();
    _client?.close();
    if (isHost) {
      await PartyService.closeRoom(pin);
    } else {
      await PartyService.setMember(pin, false);
    }
  }
}
