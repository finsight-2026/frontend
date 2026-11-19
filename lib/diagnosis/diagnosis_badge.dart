import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'comparison_labels.dart';

class DiagnosisBadge extends StatelessWidget {
  const DiagnosisBadge(this.type, {this.label, super.key});

  static const _assets = {
    'DEBT': 'debt',
    'INCOME': 'income',
    'EMERGENCY_FUND': 'emergency-fund',
    'FIXED_COST': 'fixed-cost',
    'FUTURE': 'future',
    'FAMILY': 'family',
  };

  final Object? type;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final originalLabel = diagnosisBadgeName(type);
    final caption = label ?? originalLabel;
    final asset = _assets[type];
    if (asset != null &&
        caption == originalLabel &&
        MediaQuery.textScalerOf(context).scale(16) == 16) {
      return Image.asset(
        'assets/badges/$asset.png',
        scale: 2,
        semanticLabel: caption,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: FinsightColors.neonLime900,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Text(
          caption,
          style: FinsightTypography.bodyM16.copyWith(
            color: FinsightColors.neonLime500,
          ),
        ),
      ),
    );
  }
}
