import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isLogin = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final _nameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      if (_isLogin) {
        await AuthService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await AuthService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
        );
        await UserService.createProfile(
          email: _emailController.text.trim(),
          displayName: _nameController.text.trim(),
        );
      }
    } catch (e) {
      if (mounted) setState(() { _error = _humanizeError(e); _loading = false; });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.signInWithGoogle();
      // Create RTDB profile if it doesn't exist yet (Google users)
      final existing = await UserService.getProfile();
      if (existing == null) {
        await UserService.createProfile(
          email: AuthService.email ?? '',
          displayName: AuthService.displayName ?? '',
        );
      }
    } catch (e) {
      if (mounted) setState(() { _error = _humanizeError(e); _loading = false; });
    }
  }

  String _humanizeError(Object e) {
    final msg = e.toString();
    if (msg.contains('user-not-found')) return 'No account found with this email.';
    if (msg.contains('wrong-password') || msg.contains('INVALID_LOGIN_CREDENTIALS')) return 'Incorrect email or password.';
    if (msg.contains('email-already-in-use')) return 'An account already exists with this email.';
    if (msg.contains('weak-password')) return 'Password must be at least 6 characters.';
    if (msg.contains('invalid-email')) return 'Please enter a valid email address.';
    return 'Something went wrong. Please check your internet connection and try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Logo ────────────────────────────────────
                  Image.asset('assets/Logo.png', height: 60),
                  const SizedBox(height: 12),
                  Text(
                    _isLogin ? 'Sign In' : 'Create Account',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLogin
                        ? 'Welcome back to HYFLIX'
                        : 'Start watching today',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 36),

                  // ── Display Name (signup only) ──────────────
                  if (!_isLogin) ...[
                    _buildTvField(
                      controller: _nameController,
                      focusNode: _nameFocusNode,
                      hint: 'Display Name',
                      icon: LucideIcons.user,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Email ──────────────────────────────────
                  _buildTvField(
                    controller: _emailController,
                    focusNode: _emailFocusNode,
                    hint: 'Email',
                    icon: LucideIcons.mail,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!v.contains('@') || !v.contains('.')) return 'Invalid email';
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),

                  // ── Password ───────────────────────────────
                  _buildTvField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    hint: 'Password',
                    icon: LucideIcons.lock,
                    obscure: true,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v.length < 6) return 'Min 6 characters';
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),

                  // ── Error ──────────────────────────────────
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                      ),
                      child: Text(_error!, style: const TextStyle(color: AppTheme.accent, fontSize: 13)),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Submit ─────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        disabledBackgroundColor: AppTheme.accent.withOpacity(0.5),
                      ),
                      child: _loading
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(
                              _isLogin ? 'Sign In' : 'Sign Up',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Divider ───────────────────────────────
                  Row(
                    children: [
                      const Expanded(child: Divider(color: Colors.white24)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('OR', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ),
                      const Expanded(child: Divider(color: Colors.white24)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Google Sign-In ────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(LucideIcons.chrome, size: 20),
                      label: const Text('Continue with Google', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Toggle ─────────────────────────────────
                  _TvToggleLink(
                    isLogin: _isLogin,
                    onTap: () => setState(() { _isLogin = !_isLogin; _error = null; }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTvField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    String? Function(String?)? validator,
    void Function(String)? onFieldSubmitted,
  }) {
    return _TvFieldWrapper(
      controller: controller,
      focusNode: focusNode,
      hint: hint,
      icon: icon,
      keyboardType: keyboardType,
      obscure: obscure,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
    );
  }
}

class _TvFieldWrapper extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;

  const _TvFieldWrapper({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.validator,
    this.onFieldSubmitted,
  });

  @override
  State<_TvFieldWrapper> createState() => _TvFieldWrapperState();
}

class _TvFieldWrapperState extends State<_TvFieldWrapper> {
  bool _isFocused = false;
  bool _isEditing = false;
  final FocusNode _fieldFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _fieldFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!widget.focusNode.hasFocus && _isEditing) {
      _stopEditing();
    }
    setState(() {
      _isFocused = widget.focusNode.hasFocus;
    });
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
    });
    // Defer focus + keyboard show to the next frame so Flutter first rebuilds
    // the TextFormField with readOnly: false — otherwise the IME show request
    // is silently ignored because EditableText is still in read-only mode.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isEditing && mounted) {
        _fieldFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });
  }

  void _stopEditing() {
    setState(() {
      _isEditing = false;
    });
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        // Pressing OK / Select / Enter when focused activates editing (opens keyboard)
        if (!_isEditing &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.numpadEnter ||
             event.logicalKey == LogicalKeyboardKey.space ||
             event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          _startEditing();
          return KeyEventResult.handled;
        }

        // Pressing Back / Escape when editing exits editing mode (closes keyboard)
        if (_isEditing &&
            (event.logicalKey == LogicalKeyboardKey.escape ||
             event.logicalKey == LogicalKeyboardKey.goBack ||
             event.logicalKey == LogicalKeyboardKey.gameButtonB)) {
          _stopEditing();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          if (!_isEditing) {
            _startEditing();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: _isFocused
                ? [BoxShadow(color: AppTheme.accent.withOpacity(0.4), blurRadius: 12)]
                : null,
          ),
          child: TextFormField(
            focusNode: _fieldFocusNode,
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            obscureText: widget.obscure,
            validator: widget.validator,
            onFieldSubmitted: (val) {
              _stopEditing();
              if (widget.onFieldSubmitted != null) {
                widget.onFieldSubmitted!(val);
              }
            },
            readOnly: !_isEditing,
            showCursor: _isEditing,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              prefixIcon: Icon(
                widget.icon,
                color: _isFocused ? AppTheme.accent : AppTheme.textSecondary,
                size: 18,
              ),
              filled: true,
              fillColor: _isFocused
                  ? AppTheme.cardDark.withOpacity(0.9)
                  : AppTheme.cardDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: _isFocused
                    ? const BorderSide(color: AppTheme.accent, width: 2)
                    : BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.accent, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.accent),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.accent, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _TvToggleLink extends StatefulWidget {
  final bool isLogin;
  final VoidCallback onTap;

  const _TvToggleLink({
    required this.isLogin,
    required this.onTap,
  });

  @override
  State<_TvToggleLink> createState() => _TvToggleLinkState();
}

class _TvToggleLinkState extends State<_TvToggleLink> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (hasFocus) => setState(() => _isFocused = hasFocus),
      onShowHoverHighlight: (hasHover) => setState(() => _isFocused = hasHover),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: _isFocused ? AppTheme.accent.withOpacity(0.15) : Colors.transparent,
            border: _isFocused ? Border.all(color: AppTheme.accent, width: 1) : null,
          ),
          child: RichText(
            text: TextSpan(
              text: widget.isLogin ? "Don't have an account? " : 'Already have an account? ',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              children: [
                TextSpan(
                  text: widget.isLogin ? 'Sign Up' : 'Sign In',
                  style: TextStyle(
                    color: _isFocused ? AppTheme.accent : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
