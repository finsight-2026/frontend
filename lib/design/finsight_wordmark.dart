import 'package:flutter/material.dart';

class FinsightWordmark extends StatelessWidget {
  const FinsightWordmark({this.width, super.key});

  final double? width;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/illustrations/finsight-wordmark.png',
    width: width ?? (DefaultTextStyle.of(context).style.fontSize ?? 18) * 4.25,
    fit: BoxFit.contain,
    semanticLabel: 'FINSIGHT',
  );
}
