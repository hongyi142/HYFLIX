import 'package:flutter/material.dart';
import '../core/theme.dart';

class HoverButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color backgroundColor;
  final bool hasShadow;
  final FocusNode? focusNode;

  const HoverButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.backgroundColor,
    this.hasShadow = false,
    this.focusNode,
  });

  @override
  State<HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<HoverButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onShowFocusHighlight: (hasFocus) => setState(() => _isHovered = hasFocus),
      onShowHoverHighlight: (hasHover) => setState(() => _isHovered = hasHover),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: AppTheme.radiusButton,
            boxShadow: widget.hasShadow && _isHovered ? AppTheme.softShadow : [],
            border: _isHovered ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const PrimaryButton({
    super.key,
    required this.text,
    required this.onTap,
    this.icon,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return HoverButton(
      focusNode: focusNode,
      onTap: onTap,
      backgroundColor: Colors.white,
      hasShadow: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppTheme.surface, size: 20),
              const SizedBox(width: AppTheme.spacing8),
            ],
            Text(
              text,
              style: const TextStyle(
                color: AppTheme.surface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const SecondaryButton({
    super.key,
    required this.text,
    required this.onTap,
    this.icon,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return HoverButton(
      focusNode: focusNode,
      onTap: onTap,
      backgroundColor: Colors.transparent,
      hasShadow: false,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppTheme.radiusButton,
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.0),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppTheme.textPrimary, size: 20),
              const SizedBox(width: AppTheme.spacing8),
            ],
            Text(
              text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
