import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

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

  @override
  void initState() {
    super.initState();
    _nameController.text = AuthService.displayName ?? '';
    _emailController.text = AuthService.email ?? '';
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
          const SnackBar(content: Text('Display name updated'), backgroundColor: AppTheme.accent),
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
          const SnackBar(content: Text('Email updated'), backgroundColor: AppTheme.accent),
        );
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
        const SnackBar(content: Text('Passwords do not match'), backgroundColor: AppTheme.accent),
      );
      return;
    }
    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters'), backgroundColor: AppTheme.accent),
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
          const SnackBar(content: Text('Password updated'), backgroundColor: AppTheme.accent),
        );
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
        backgroundColor: AppTheme.cardDark,
        title: const Text('Clear Watch History', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to clear your entire watch history? This cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: AppTheme.accent)),
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
          const SnackBar(content: Text('Watch history cleared'), backgroundColor: AppTheme.accent),
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildDisplayNameSection()),
          SliverToBoxAdapter(child: _buildEmailSection()),
          SliverToBoxAdapter(child: _buildPasswordSection()),
          SliverToBoxAdapter(child: _buildClearHistorySection()),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
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
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'Settings',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
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
        hintStyle: const TextStyle(color: AppTheme.textSecondary),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildSaveButton({required String label, required bool loading, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          disabledBackgroundColor: AppTheme.accent.withOpacity(0.5),
        ),
        child: loading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildDisplayNameSection() {
    return _buildSection(
      title: 'Display Name',
      children: [
        _buildTextField(controller: _nameController, hint: 'Display Name', icon: LucideIcons.user),
        const SizedBox(height: 12),
        _buildSaveButton(label: 'Save Name', loading: _savingName, onTap: _saveDisplayName),
      ],
    );
  }

  Widget _buildEmailSection() {
    return _buildSection(
      title: 'Change Email',
      children: [
        _buildTextField(
          controller: _emailController,
          hint: 'Current Email',
          icon: LucideIcons.mail,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _newEmailController,
          hint: 'New Email',
          icon: LucideIcons.mail,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _currentPasswordController,
          hint: 'Current Password (required)',
          icon: LucideIcons.lock,
          obscure: true,
        ),
        const SizedBox(height: 12),
        _buildSaveButton(label: 'Update Email', loading: _savingEmail, onTap: _changeEmail),
      ],
    );
  }

  Widget _buildPasswordSection() {
    return _buildSection(
      title: 'Change Password',
      children: [
        _buildTextField(
          controller: _currentPasswordController,
          hint: 'Current Password',
          icon: LucideIcons.lock,
          obscure: true,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _newPasswordController,
          hint: 'New Password',
          icon: LucideIcons.lock,
          obscure: true,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _confirmPasswordController,
          hint: 'Confirm New Password',
          icon: LucideIcons.lock,
          obscure: true,
        ),
        const SizedBox(height: 12),
        _buildSaveButton(label: 'Update Password', loading: _savingPassword, onTap: _changePassword),
      ],
    );
  }

  Widget _buildClearHistorySection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Clear Watch History', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Remove all your watch history and continue watching data. This action cannot be undone.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: _clearingHistory ? null : _clearWatchHistory,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: const BorderSide(color: AppTheme.accent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _clearingHistory
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
                    : const Text('Clear History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
