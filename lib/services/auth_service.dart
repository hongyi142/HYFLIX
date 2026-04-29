import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static const String _apiKey = 'AIzaSyC7MxOV-w0rEejih4KAlxW-W7fnUYuC_aU';
  static const String _authBase = 'https://identitytoolkit.googleapis.com/v1/accounts';

  static String? _idToken;
  static String? _refreshToken;
  static String? _uid;
  static String? _email;
  static String? _displayName;

  // ── Getters ──────────────────────────────────────────────────────────

  static String? get uid => _uid;
  static String? get email => _email;
  static String? get displayName => _displayName;
  static String? get idToken => _idToken;
  static bool get isLoggedIn => _uid != null && _idToken != null;

  // ── Init ─────────────────────────────────────────────────────────────

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _idToken = prefs.getString('fb_idToken');
    _refreshToken = prefs.getString('fb_refreshToken');
    _uid = prefs.getString('fb_uid');
    _email = prefs.getString('fb_email');
    _displayName = prefs.getString('fb_displayName');

    // Try to refresh token if it exists
    if (_refreshToken != null) {
      await _refreshIdToken();
    }
  }

  static Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (_idToken != null) prefs.setString('fb_idToken', _idToken!);
    if (_refreshToken != null) prefs.setString('fb_refreshToken', _refreshToken!);
    if (_uid != null) prefs.setString('fb_uid', _uid!);
    if (_email != null) prefs.setString('fb_email', _email!);
    if (_displayName != null) prefs.setString('fb_displayName', _displayName!);
  }

  static Future<void> _clearPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fb_idToken');
    await prefs.remove('fb_refreshToken');
    await prefs.remove('fb_uid');
    await prefs.remove('fb_email');
    await prefs.remove('fb_displayName');
  }

  // ── Auth State ───────────────────────────────────────────────────────

  static final List<void Function(bool)> _listeners = [];

  static void addAuthListener(void Function(bool isLoggedIn) listener) {
    _listeners.add(listener);
  }

  static void removeAuthListener(void Function(bool isLoggedIn) listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    for (final l in _listeners) {
      l(isLoggedIn);
    }
  }

  // ── Sign Up ──────────────────────────────────────────────────────────

  static Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final res = await http.post(
      Uri.parse('$_authBase:signUp?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );

    if (res.statusCode != 200) {
      final body = json.decode(res.body);
      throw Exception(body['error']?['message'] ?? 'Sign up failed');
    }

    final body = json.decode(res.body);
    _idToken = body['idToken'];
    _refreshToken = body['refreshToken'];
    _uid = body['localId'];
    _email = email;
    _displayName = displayName;

    await _saveToPrefs();
    _notifyListeners();
  }

  // ── Sign In ──────────────────────────────────────────────────────────

  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$_authBase:signInWithPassword?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );

    if (res.statusCode != 200) {
      final body = json.decode(res.body);
      throw Exception(body['error']?['message'] ?? 'Sign in failed');
    }

    final body = json.decode(res.body);
    _idToken = body['idToken'];
    _refreshToken = body['refreshToken'];
    _uid = body['localId'];
    _email = email;

    // Fetch display name from user info
    await _fetchUserInfo();
    await _saveToPrefs();
    _notifyListeners();
  }

  // ── Sign In with Google ──────────────────────────────────────────────

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  static Future<void> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google sign-in was cancelled');

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) throw Exception('Failed to get Google ID token');

    final res = await http.post(
      Uri.parse('$_authBase:signInWithIdp?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'postBody': 'id_token=$idToken&providerId=google.com',
        'requestUri': 'http://localhost',
        'returnSecureToken': true,
        'returnIdpCredential': true,
      }),
    );

    if (res.statusCode != 200) {
      final body = json.decode(res.body);
      throw Exception(body['error']?['message'] ?? 'Google sign-in failed');
    }

    final body = json.decode(res.body);
    _idToken = body['idToken'];
    _refreshToken = body['refreshToken'];
    _uid = body['localId'];
    _email = body['email'] ?? googleUser.email;
    _displayName = body['displayName'] ?? googleUser.displayName;

    await _saveToPrefs();
    _notifyListeners();
  }

  // ── Refresh Token ────────────────────────────────────────────────────

  static Future<void> _refreshIdToken() async {
    if (_refreshToken == null) return;
    try {
      final res = await http.post(
        Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken,
        }),
      );

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        _idToken = body['id_token'];
        _refreshToken = body['refresh_token'];
        _uid = body['user_id'];
        // Restore email and displayName from SharedPreferences if not set
        if (_email == null || _displayName == null) {
          final prefs = await SharedPreferences.getInstance();
          _email ??= prefs.getString('fb_email');
          _displayName ??= prefs.getString('fb_displayName');
        }
        // Fetch fresh user info from Firebase Auth if still missing
        if (_email == null || _displayName == null) {
          await _fetchUserInfo();
        }
        await _saveToPrefs();
      } else {
        // Token refresh failed, clear session
        await _clearPrefs();
        _idToken = null;
        _refreshToken = null;
        _uid = null;
        _email = null;
        _displayName = null;
      }
    } catch (_) {
      // Network error, keep existing token
    }
  }

  // ── Fetch User Info ──────────────────────────────────────────────────

  static Future<void> _fetchUserInfo() async {
    if (_idToken == null) return;
    try {
      final res = await http.post(
        Uri.parse('$_authBase:lookup?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'idToken': _idToken}),
      );

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        final users = body['users'] as List?;
        if (users != null && users.isNotEmpty) {
          _displayName = users[0]['displayName'];
          _email = users[0]['email'];
        }
      }
    } catch (_) {}
  }

  // ── Sign Out ─────────────────────────────────────────────────────────

  static Future<void> signOut() async {
    _idToken = null;
    _refreshToken = null;
    _uid = null;
    _email = null;
    _displayName = null;
    await _clearPrefs();
    _notifyListeners();
  }

  // ── Ensure valid token ───────────────────────────────────────────────

  static Future<bool> ensureValidToken() async {
    if (_idToken != null) return true;
    if (_refreshToken != null) {
      await _refreshIdToken();
      return _idToken != null;
    }
    return false;
  }
}
