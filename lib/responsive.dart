import 'package:flutter/widgets.dart';

/// A watch / very small screen. Wear OS devices report a small shortestSide.
bool isWatch(BuildContext context) =>
    MediaQuery.of(context).size.shortestSide < 320;

/// Wraps content so it is vertically centered when there's room, but becomes
/// scrollable (never overflows) when there isn't — the key fix for tiny
/// watch screens.
class CenterScroll extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const CenterScroll({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - padding.vertical,
              ),
              child: Center(child: child),
            ),
          );
        },
      ),
    );
  }
}
