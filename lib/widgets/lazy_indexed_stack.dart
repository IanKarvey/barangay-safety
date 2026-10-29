import 'package:flutter/material.dart';

/// [IndexedStack] that only builds a tab once it has actually been visited.
///
/// A plain IndexedStack mounts **every** child immediately and merely hides the
/// ones that aren't selected. On the officials' home screen that meant logging
/// in built the dashboard (two charts + entrance animations), a full FlutterMap
/// with live tile fetching, the incidents list, and the users tab — which loads
/// every user in `initState` — all in the same frame. On a mid-range phone that
/// blocks the main thread long enough for Android to raise "app not responding"
/// and kill the process.
///
/// Once a tab has been visited it stays mounted, so scroll position, map
/// camera and loaded data survive tab switches exactly as before. The only
/// behaviour that changes is *when* a tab is first built.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late final List<bool> _visited;

  @override
  void initState() {
    super.initState();
    _visited = List<bool>.filled(widget.children.length, false);
    _visited[widget.index] = true;
  }

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mark on rebuild rather than in the tap handler so the flag can never
    // drift out of sync with the index actually being rendered.
    if (widget.index < _visited.length) _visited[widget.index] = true;
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        for (int i = 0; i < widget.children.length; i++)
          if (_visited[i]) widget.children[i] else const SizedBox.shrink(),
      ],
    );
  }
}
