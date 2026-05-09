import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Wraps a horizontal [ListView] so that vertical mouse wheel scrolling
/// is converted to horizontal scrolling. Essential for desktop/web UX.
class HorizontalScrollWrapper extends StatefulWidget {
  final Widget child;
  final ScrollController? controller;

  const HorizontalScrollWrapper({
    super.key,
    required this.child,
    this.controller,
  });

  @override
  State<HorizontalScrollWrapper> createState() => _HorizontalScrollWrapperState();
}

class _HorizontalScrollWrapperState extends State<HorizontalScrollWrapper> {
  ScrollController? _scrollController;

  ScrollController get _effectiveController =>
      widget.controller ?? _scrollController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _scrollController = ScrollController();
    }
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final controller = _effectiveController;
          if (!controller.hasClients) return;
          final delta = event.scrollDelta.dy;
          final newOffset = (controller.offset + delta).clamp(
            0.0,
            controller.position.maxScrollExtent,
          );
          controller.jumpTo(newOffset);
        }
      },
      child: widget.child,
    );
  }
}
