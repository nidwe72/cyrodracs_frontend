import 'dart:async';

/// Debounces a callback so that rapid invocations only fire once after a
/// quiet period. Used by per-column text/numeric filter inputs to delay
/// refetching until the user stops typing.
class Debouncer {
  Debouncer({this.duration = const Duration(milliseconds: 300)});

  final Duration duration;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
