import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/party_service.dart';
import '../services/tmdb_service.dart';
import '../services/torbox_service.dart';
import '../services/user_service.dart';
import 'auth_page.dart';
import 'home_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _newEmailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _savingName = false;
  bool _savingEmail = false;
  bool _savingPassword = false;
  bool _clearingHistory = false;
  String _language = 'en';
  String _defaultSource = 'HHZY (Luxury)';
  bool _loadingSource = true;
  String _torrentMode = UserService.torrentMode;
  bool _loadingTorrentSetting = true;
  bool _savingTorBoxKey = false;
  final TextEditingController _torBoxKeyController = TextEditingController();
  final TextEditingController _customSourceNameController =
      TextEditingController();
  final TextEditingController _customSourceUrlController =
      TextEditingController();
  bool _validatingSource = false;
  bool _addingSource = false;
  String? _sourceValidationMessage;
  bool _sourceValidationOk = false;
  String? _expandedSection;

  @override
  void initState() {
    super.initState();
    _nameController.text = AuthService.displayName ?? '';
    _emailController.text = AuthService.email ?? '';
    _loadLanguage();
    _loadDefaultSource();
    _loadTorrentSetting();
    _hydrateCustomSources();
  }

  Future<void> _hydrateCustomSources() async {
    if (!AuthService.isLoggedIn) return;
    try {
      await ApiService.ensureCustomSourcesLoaded();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadLanguage() async {
    try {
      final lang = await UserService.getLanguage();
      if (mounted) setState(() => _language = lang);
    } catch (_) {}
  }

  Future<void> _loadDefaultSource() async {
    try {
      final source = await UserService.getDefaultSource();
      if (mounted) {
        setState(() {
          _defaultSource = source;
          _loadingSource = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSource = false);
    }
  }

  Future<void> _loadTorrentSetting() async {
    try {
      await UserService.loadTorrentSettings();
      if (mounted) {
        setState(() {
          _torrentMode = UserService.torrentMode;
          _torBoxKeyController.text = TorBoxService.apiKey;
          _loadingTorrentSetting = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTorrentSetting = false);
    }
  }

  Future<void> _saveTorrentMode(String mode) async {
    setState(() => _torrentMode = mode);
    try {
      await UserService.saveTorrentMode(mode);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving preference: $e'),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
    }
  }

  Future<void> _saveTorBoxApiKey() async {
    setState(() => _savingTorBoxKey = true);
    try {
      await UserService.saveTorBoxApiKey(_torBoxKeyController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('TorBox API key saved'),
            backgroundColor: Color(0xFF1A1A1A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving API key: $e'),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingTorBoxKey = false);
    }
  }

  Future<void> _saveLanguage(String lang) async {
    setState(() => _language = lang);
    TmdbService.setLanguage(lang);
    ApiService.clearAllCache();
    try {
      await UserService.saveLanguage(lang);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lang == 'zh' ? '语言已切换为中文' : 'Language set to English'),
            backgroundColor: const Color(0xFF1A1A1A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
        );
        HomePage.refreshFromLanguageChange();
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.accent),
        );
      }
    }
  }

  Future<void> _saveDefaultSource(String sourceName) async {
    setState(() => _defaultSource = sourceName);
    ApiService.setDefaultSourceByName(sourceName);
    try {
      await UserService.saveDefaultSource(sourceName);
      ApiService.clearAllCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Default source set to $sourceName'),
            backgroundColor: const Color(0xFF1A1A1A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
        );
        HomePage.refreshFromSourceChange();
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.accent),
        );
      }
    }
  }

  bool _nameExists(String name) => ApiService.sources
      .any((s) => s.name.toLowerCase() == name.trim().toLowerCase());

  Future<void> _validateSource() async {
    final url = _customSourceUrlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _validatingSource = true;
      _sourceValidationMessage = null;
    });
    final r = await ApiService.validateSourceUrl(url);
    if (!mounted) return;
    setState(() {
      _validatingSource = false;
      _sourceValidationOk = r.ok;
      _sourceValidationMessage = r.ok
          ? 'OK — ${r.itemCount} items, ${r.latencyMs}ms'
          : (r.error ?? 'Validation failed');
    });
  }

  Future<void> _addCustomSource() async {
    final name = _customSourceNameController.text.trim();
    final url = _customSourceUrlController.text.trim();
    if (name.isEmpty || url.isEmpty) {
      setState(() {
        _sourceValidationOk = false;
        _sourceValidationMessage = 'Name and URL are required';
      });
      return;
    }
    if (name.toLowerCase() == 'torrent' || _nameExists(name)) {
      setState(() {
        _sourceValidationOk = false;
        _sourceValidationMessage = 'That name is already taken';
      });
      return;
    }
    setState(() => _addingSource = true);
    try {
      await UserService.saveCustomSource(name, url);
      ApiService.setCustomSources([
        ...ApiService.customSources,
        VideoSource(name: name, baseUrl: url),
      ]);
      ApiService.clearAllCache();
      _customSourceNameController.clear();
      _customSourceUrlController.clear();
      if (mounted) {
        setState(() {
          _sourceValidationOk = true;
          _sourceValidationMessage = 'Added "$name"';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Custom source "$name" added'),
            backgroundColor: const Color(0xFF1A1A1A),
          ),
        );
        HomePage.refreshFromSourceChange();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sourceValidationOk = false;
          _sourceValidationMessage = 'Error: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _addingSource = false);
    }
  }

  bool _builtIn(VideoSource s) => ApiService.isBuiltIn(s);

  Future<void> _removeCustomSource(VideoSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        title: const Text('Remove source?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${source.name}"? This cannot be undone.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await UserService.removeCustomSource(source.name);
    final remaining =
        ApiService.customSources.where((s) => s.name != source.name);
    ApiService.setCustomSources([...remaining]);
    ApiService.clearAllCache();

    // If the removed source was the default, fall back to HHZY.
    if (_defaultSource == source.name) {
      _defaultSource = 'HHZY (Luxury)';
      ApiService.setDefaultSourceByName(_defaultSource);
      await UserService.saveDefaultSource(_defaultSource);
    }
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${source.name}"'),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
      HomePage.refreshFromSourceChange();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _newEmailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _torBoxKeyController.dispose();
    _customSourceNameController.dispose();
    _customSourceUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveDisplayName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _savingName = true);
    try {
      await AuthService.updateDisplayName(name);
      await UserService.updateDisplayName(name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Display name updated'),
            backgroundColor: const Color(0xFF1A1A1A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.accent),
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changeEmail() async {
    final newEmail = _newEmailController.text.trim();
    final password = _currentPasswordController.text;
    if (newEmail.isEmpty || !newEmail.contains('@')) return;
    if (password.isEmpty) return;

    setState(() => _savingEmail = true);
    try {
      await AuthService.updateEmail(newEmail, password);
      await UserService.updateEmail(newEmail);
      _emailController.text = newEmail;
      _newEmailController.clear();
      _currentPasswordController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Email updated'),
            backgroundColor: const Color(0xFF1A1A1A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
        );
        setState(() => _expandedSection = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.accent),
        );
      }
    } finally {
      if (mounted) setState(() => _savingEmail = false);
    }
  }

  Future<void> _changePassword() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;
    if (currentPassword.isEmpty || newPassword.isEmpty) return;
    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Passwords do not match'),
          backgroundColor: AppTheme.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }
    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Password must be at least 6 characters'),
          backgroundColor: AppTheme.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    setState(() => _savingPassword = true);
    try {
      await AuthService.updatePassword(newPassword, currentPassword);
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Password updated'),
            backgroundColor: const Color(0xFF1A1A1A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
        );
        setState(() => _expandedSection = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.accent),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _clearWatchHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
        title: const Text(
          'Clear Watch History',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: Text(
          'This will permanently remove your entire watch history and continue watching data. This action cannot be undone.',
          style: TextStyle(color: Colors.white.withOpacity(0.5), height: 1.6, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Text('Clear', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _clearingHistory = true);
    try {
      await UserService.clearWatchHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Watch history cleared'),
            backgroundColor: const Color(0xFF1A1A1A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.accent),
        );
      }
    } finally {
      if (mounted) setState(() => _clearingHistory = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);
    final maxWidth = layout.isDesktop ? 680.0 : double.infinity;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileCard(),
                    const SizedBox(height: 36),
                    _buildSectionHeader('Preferences', LucideIcons.settings2),
                    const SizedBox(height: 12),
                    _buildLanguageTile(),
                    const SizedBox(height: 10),
                    _buildSourceTile(),
                    const SizedBox(height: 10),
                    _buildTorrentToggleTile(),
                    const SizedBox(height: 36),
                    _buildSectionHeader('Account', LucideIcons.userCog),
                    const SizedBox(height: 12),
                    _buildAccountSection(),
                    const SizedBox(height: 10),
                    _buildLogoutTile(),
                    const SizedBox(height: 36),
                    _buildSectionHeader('Danger Zone', LucideIcons.alertTriangle),
                    const SizedBox(height: 12),
                    _buildClearHistoryTile(),
                    const SizedBox(height: 64),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, topPadding + 16, 24, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: const Icon(LucideIcons.arrowLeft, color: Colors.white70, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile Card ───────────────────────────────────────────────────

  Widget _buildProfileCard() {
    final name = AuthService.displayName ?? 'User';
    final email = AuthService.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.accent, AppTheme.accent.withOpacity(0.7)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    email,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section Headers ────────────────────────────────────────────────

  Widget _buildSectionHeader(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent, size: 16),
          const SizedBox(width: 10),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Language Tile ──────────────────────────────────────────────────

  Widget _buildLanguageTile() {
    return _buildCard(
      child: Column(
        children: [
          _SettingsTile(
            icon: LucideIcons.globe,
            title: 'Language',
            subtitle: _language == 'zh' ? '中文 (Chinese)' : 'English',
            trailing: _SegmentedToggle(
              options: const ['EN', '中文'],
              selectedIndex: _language == 'en' ? 0 : 1,
              onSelected: (i) => _saveLanguage(i == 0 ? 'en' : 'zh'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Source Tile ────────────────────────────────────────────────────

  Widget _buildSourceTile() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SettingsTile(
            icon: LucideIcons.server,
            title: 'Default Source',
            subtitle: 'Content provider for Chinese videos',
          ),
          if (_loadingSource)
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 24, 24),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 24, 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ApiService.sources.map((source) {
                  final isActive = _defaultSource == source.name;
                  return GestureDetector(
                    onTap: () => _saveDefaultSource(source.name),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive ? AppTheme.accent : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isActive ? AppTheme.accent : Colors.white.withOpacity(0.06),
                        ),
                      ),
                      child: Text(
                        source.name,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white.withOpacity(0.5),
                          fontSize: 12,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          if (!AuthService.isLoggedIn)
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 24, 24),
              child: Text(
                'Sign in to add & sync custom sources',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 12,
                ),
              ),
            )
          else ...[
            if (ApiService.sources.any((s) => !_builtIn(s)))
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Custom sources',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...ApiService.sources
                        .where((s) => !_builtIn(s))
                        .map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.name,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    LucideIcons.trash2,
                                    size: 16,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                  onPressed: () => _removeCustomSource(s),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTextField(
                    controller: _customSourceNameController,
                    hint: 'Source name (e.g. HongNiu)',
                    icon: LucideIcons.server,
                  ),
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: _customSourceUrlController,
                    hint: 'Base URL (macCMS JSON API)',
                    icon: LucideIcons.link,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSaveButton(
                          label: 'Validate',
                          loading: _validatingSource,
                          onTap: _validateSource,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildSaveButton(
                          label: 'Add Source',
                          loading: _addingSource,
                          onTap: _addCustomSource,
                        ),
                      ),
                    ],
                  ),
                  if (_sourceValidationMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _sourceValidationMessage!,
                        style: TextStyle(
                          color: _sourceValidationOk
                              ? Colors.greenAccent
                              : AppTheme.accent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Torrent Toggle Tile ─────────────────────────────────────────────

  Widget _buildTorrentToggleTile() {
    const modes = ['off', 'p2p', 'torbox'];
    final modeIndex = modes.indexOf(_torrentMode).clamp(0, 2);
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsTile(
            icon: LucideIcons.play,
            title: 'Torrent Streaming',
            subtitle: _torrentMode == 'off'
                ? 'Torrent streaming is disabled'
                : _torrentMode == 'p2p'
                    ? 'Stream via peer-to-peer (libtorrent)'
                    : 'Stream via TorBox debrid',
            trailing: _loadingTorrentSetting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
                    ),
                  )
                : _SegmentedToggle(
                    options: const ['Off', 'P2P', 'TorBox'],
                    selectedIndex: modeIndex,
                    onSelected: (i) => _saveTorrentMode(modes[i]),
                  ),
          ),
          if (_torrentMode == 'torbox') ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTextField(
                    controller: _torBoxKeyController,
                    hint: 'TorBox API key (stored privately in your account)',
                    icon: LucideIcons.key,
                  ),
                  const SizedBox(height: 12),
                  _buildSaveButton(
                    label: 'Save API Key',
                    loading: _savingTorBoxKey,
                    onTap: _saveTorBoxApiKey,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Account Section ────────────────────────────────────────────────

  Widget _buildAccountSection() {
    return _buildCard(
      child: Column(
        children: [
          _buildExpandableTile(
            icon: LucideIcons.user,
            title: 'Display Name',
            subtitle: AuthService.displayName ?? '',
            sectionKey: 'name',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 24, 24),
              child: Column(
                children: [
                  _buildTextField(
                    controller: _nameController,
                    hint: 'Enter display name',
                    icon: LucideIcons.user,
                  ),
                  const SizedBox(height: 12),
                  _buildSaveButton(
                    label: 'Save Name',
                    loading: _savingName,
                    onTap: _saveDisplayName,
                  ),
                ],
              ),
            ),
          ),
          _buildExpandableTile(
            icon: LucideIcons.mail,
            title: 'Email',
            subtitle: AuthService.email ?? '',
            sectionKey: 'email',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 24, 24),
              child: Column(
                children: [
                  _buildTextField(
                    controller: _newEmailController,
                    hint: 'New email address',
                    icon: LucideIcons.mail,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: _currentPasswordController,
                    hint: 'Current password (required)',
                    icon: LucideIcons.lock,
                    obscure: true,
                  ),
                  const SizedBox(height: 12),
                  _buildSaveButton(
                    label: 'Update Email',
                    loading: _savingEmail,
                    onTap: _changeEmail,
                  ),
                ],
              ),
            ),
          ),
          _buildExpandableTile(
            icon: LucideIcons.lock,
            title: 'Password',
            subtitle: '••••••••',
            sectionKey: 'password',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 24, 24),
              child: Column(
                children: [
                  _buildTextField(
                    controller: _currentPasswordController,
                    hint: 'Current password',
                    icon: LucideIcons.lock,
                    obscure: true,
                  ),
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: _newPasswordController,
                    hint: 'New password',
                    icon: LucideIcons.lock,
                    obscure: true,
                  ),
                  const SizedBox(height: 10),
                  _buildTextField(
                    controller: _confirmPasswordController,
                    hint: 'Confirm new password',
                    icon: LucideIcons.lock,
                    obscure: true,
                  ),
                  const SizedBox(height: 12),
                  _buildSaveButton(
                    label: 'Update Password',
                    loading: _savingPassword,
                    onTap: _changePassword,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Log Out ────────────────────────────────────────────────────────

  Widget _buildLogoutTile() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.logOut, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Log Out',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AuthService.email ?? 'Sign out of this device',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 36,
            child: OutlinedButton(
              onPressed: _confirmLogout,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Log Out'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        title: const Text('Log out of HYFLIX?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'You will need to sign in again to watch.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out',
                style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Leave any watch party first so others don't keep waiting on this device.
    final party = PartyService.current;
    if (party != null) await PartyService.endOrLeave(party);

    await AuthService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
  }

  // ── Clear History Tile ─────────────────────────────────────────────

  Widget _buildClearHistoryTile() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(LucideIcons.trash2, color: AppTheme.accent, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clear Watch History',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Remove all watch data permanently',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 36,
            child: OutlinedButton(
              onPressed: _clearingHistory ? null : _clearWatchHistory,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: BorderSide(color: AppTheme.accent.withOpacity(0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: _clearingHistory
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                    )
                  : const Text('Clear', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared Widgets ─────────────────────────────────────────────────

  Widget _buildCard({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: child,
      ),
    );
  }

  Widget _buildExpandableTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String sectionKey,
    required Widget child,
  }) {
    final isExpanded = _expandedSection == sectionKey;
    return Column(
      children: [
        _SettingsTile(
          icon: icon,
          title: title,
          subtitle: subtitle,
          trailing: AnimatedRotation(
            turns: isExpanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 250),
            child: Icon(
              LucideIcons.chevronDown,
              color: Colors.white.withOpacity(0.3),
              size: 18,
            ),
          ),
          onTap: () => setState(() => _expandedSection = isExpanded ? null : sectionKey),
        ),
        AnimatedCrossFade(
          crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
          firstChild: const SizedBox.shrink(),
          secondChild: child,
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(color: Colors.white.withOpacity(0.06), height: 1),
          ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.25), size: 16),
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _buildSaveButton({
    required String label,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          disabledBackgroundColor: AppTheme.accent.withOpacity(0.4),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ── Settings Tile ──────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(icon, color: Colors.white.withOpacity(0.4), size: 18),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

// ── Segmented Toggle ───────────────────────────────────────────────

class _SegmentedToggle extends StatelessWidget {
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _SegmentedToggle({
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(options.length, (i) {
          final isActive = i == selectedIndex;
          return GestureDetector(
            onTap: () => onSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isActive ? AppTheme.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                options[i],
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
