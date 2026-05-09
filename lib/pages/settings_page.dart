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
  String _defaultSource = 'Hong Niu';
  bool _loadingSource = true;

  // Track which section is expanded
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
            backgroundColor: AppTheme.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            backgroundColor: AppTheme.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            backgroundColor: AppTheme.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            backgroundColor: AppTheme.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            backgroundColor: AppTheme.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        backgroundColor: const Color(0xFF1A1F2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear Watch History', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text(
          'This will permanently remove your entire watch history and continue watching data. This action cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.accent.withOpacity(0.15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Clear', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
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
            backgroundColor: AppTheme.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);
    final maxWidth = layout.isDesktop ? 680.0 : double.infinity;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildProfileCard()),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  children: [
                    _buildSectionLabel('Content Preferences'),
                    _buildLanguageSection(),
                    _buildSourceSection(),
                    const SizedBox(height: 8),
                    _buildSectionLabel('Account'),
                    _buildAccountSection(),
                    const SizedBox(height: 8),
                    _buildSectionLabel('Data & Privacy'),
                    _buildClearHistorySection(),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding + 12, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'Settings',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final name = AuthService.displayName ?? 'User';
    final email = AuthService.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.accent.withOpacity(0.15),
                  AppTheme.cardDark,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.accent, AppTheme.accent.withOpacity(0.7)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
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
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Member',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  // ── Language Section ─────────────────────────────────────────────────

  Widget _buildLanguageSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingRow(
            icon: LucideIcons.globe,
            title: 'Language',
            subtitle: _language == 'zh' ? '中文 (Chinese)' : 'English',
            trailing: SizedBox(
              width: 130,
              child: _buildSegmentedToggle(
                options: const ['English', '中文'],
                selectedIndex: _language == 'en' ? 0 : 1,
                onSelected: (i) => _saveLanguage(i == 0 ? 'en' : 'zh'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Default Source Section ───────────────────────────────────────────

  Widget _buildSourceSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingRow(
            icon: LucideIcons.server,
            title: 'Default Source',
            subtitle: 'Choose which provider to load content from',
          ),
          const SizedBox(height: 16),
          if (_loadingSource)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                ),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: ApiService.sources.map((source) {
                final isActive = _defaultSource == source.name;
                return GestureDetector(
                  onTap: () => _saveDefaultSource(source.name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.accent.withOpacity(0.15) : AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive ? AppTheme.accent : Colors.white10,
                        width: isActive ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isActive ? AppTheme.accent : AppTheme.textSecondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          source.name,
                          style: TextStyle(
                            color: isActive ? Colors.white : AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          const Icon(LucideIcons.check, color: AppTheme.accent, size: 14),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ── Account Section (collapsible sub-sections) ───────────────────────

  Widget _buildAccountSection() {
    return _buildCard(
      child: Column(
        children: [
          _buildExpandableTile(
            icon: LucideIcons.user,
            title: 'Display Name',
            subtitle: AuthService.displayName ?? '',
            sectionKey: 'name',
            child: Column(
              children: [
                const SizedBox(height: 16),
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
          const Divider(color: Colors.white10, height: 1),
          _buildExpandableTile(
            icon: LucideIcons.mail,
            title: 'Email',
            subtitle: AuthService.email ?? '',
            sectionKey: 'email',
            child: Column(
              children: [
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _newEmailController,
                  hint: 'New email address',
                  icon: LucideIcons.mail,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
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
          const Divider(color: Colors.white10, height: 1),
          _buildExpandableTile(
            icon: LucideIcons.lock,
            title: 'Password',
            subtitle: '••••••••',
            sectionKey: 'password',
            child: Column(
              children: [
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _currentPasswordController,
                  hint: 'Current password',
                  icon: LucideIcons.lock,
                  obscure: true,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _newPasswordController,
                  hint: 'New password',
                  icon: LucideIcons.lock,
                  obscure: true,
                ),
                const SizedBox(height: 12),
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
        ],
      ),
    );
  }

  // ── Clear History Section ────────────────────────────────────────────

  Widget _buildClearHistorySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(LucideIcons.trash2, color: AppTheme.accent, size: 18),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Clear Watch History',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Remove all watch history and continue watching data',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _clearingHistory ? null : _clearWatchHistory,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      side: BorderSide(color: AppTheme.accent.withOpacity(0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _clearingHistory
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                          )
                        : const Text(
                            'Clear History',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared Widgets ───────────────────────────────────────────────────

  Widget _buildCard({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.accent, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
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
    return AnimatedCrossFade(
      crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 250),
      firstChild: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expandedSection = sectionKey),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppTheme.accent, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                color: AppTheme.textSecondary.withOpacity(0.5),
                size: 18,
              ),
            ],
          ),
        ),
      ),
      secondChild: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expandedSection = null),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4, top: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: AppTheme.accent, size: 18),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronDown,
                    color: AppTheme.textSecondary.withOpacity(0.5),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildSegmentedToggle({
    required List<String> options,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: List.generate(options.length, (i) {
          final isActive = i == selectedIndex;
          return GestureDetector(
            onTap: () => onSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isActive ? AppTheme.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                options[i],
                style: TextStyle(
                  color: isActive ? Colors.white : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        }),
      ),
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
        hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 18),
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          disabledBackgroundColor: AppTheme.accent.withOpacity(0.5),
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
