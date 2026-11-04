import 'package:flutter/widgets.dart';

import '../../theme/flucord_type.dart';

/// Lifts a block of text so its letters, not its line boxes, centre on the
/// picture beside it. [lines] are the roles of the lines shown, top to
/// bottom: a line left out changes the lift.
class OpticallyCentred extends StatelessWidget {
  const OpticallyCentred({required this.lines, required this.child, super.key})
    : assert(lines.length > 0);

  final List<FlucordTextRole> lines;
  final Widget child;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(0, -FlucordType.opticalLift(lines.first, lines.last)),
    child: child,
  );
}
