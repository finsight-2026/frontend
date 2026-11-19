import 'package:flutter/material.dart';

class FinsightCheckboxTile extends StatelessWidget {
  const FinsightCheckboxTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.labelStyle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return MergeSemantics(
      child: Semantics(
        checked: value,
        child: ListTile(
          title: Text(label, style: labelStyle),
          enabled: change != null,
          onTap: change == null ? null : () => change(!value),
          internalAddSemanticForOnTap: false,
          contentPadding: EdgeInsets.zero,
          minLeadingWidth: 24,
          minTileHeight: 44,
          horizontalTitleGap: 12,
          leading: Image.asset(
            value
                ? 'assets/controls/checkbox-checked.png'
                : 'assets/controls/checkbox-unchecked.png',
            width: 24,
            height: 24,
            opacity: change == null ? const AlwaysStoppedAnimation(.38) : null,
            excludeFromSemantics: true,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}
