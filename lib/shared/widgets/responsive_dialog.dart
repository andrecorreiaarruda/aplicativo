import 'package:flutter/material.dart';

Future<T?> showResponsiveDialog<T>({
  required BuildContext context,
  required Widget child,
  double maxWidth = 780,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: MediaQuery.sizeOf(context).height - 32,
        ),
        child: child,
      ),
    ),
  );
}
