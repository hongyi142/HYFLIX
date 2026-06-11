import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/tmdb_service.dart';
import '../services/user_service.dart';
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
  String _defaultSource = '1080ZYK';
  bool _loadingSource = true;
  String? _expandedSection;

  @override
  void initState() {
    super.initState();
    _nameController.text = AuthService.displayName ?? '';
    _emailController.text = AuthService.email ?? '';
    _loadLanguage();
    _loadDefaultSource();
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

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _newEmailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
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
                    const SizedBox(height: 36),
                    _buildSectionHeader('Account', LucideIcons.userCog),
                    const SizedBox(height: 12),
                    _buildAccountSection(),
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
