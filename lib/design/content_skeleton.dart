import 'package:flutter/material.dart';

import 'tokens.dart';

class ContentSkeleton extends StatelessWidget {
  const ContentSkeleton({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: MediaQuery.disableAnimationsOf(context)
            ? child
            : TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 260),
                curve: const Interval(.55, 1, curve: Curves.easeOut),
                builder: (_, opacity, placeholder) =>
                    Opacity(opacity: opacity, child: placeholder),
                child: child,
              ),
      ),
    ),
  );
}

class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    required this.height,
    this.width,
    this.radius = 6,
    super.key,
  });
  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: FinsightColors.gray800,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: SizedBox(height: height, width: width ?? double.infinity),
  );
}

class SkeletonLine extends StatelessWidget {
  const SkeletonLine(this.fraction, {this.fontSize = 14, super.key});
  final double fraction;
  final double fontSize;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: fraction,
    alignment: AlignmentDirectional.centerStart,
    child: SkeletonBlock(
      height: MediaQuery.textScalerOf(context).scale(fontSize),
      radius: 4,
    ),
  );
}

class SkeletonPanel extends StatelessWidget {
  const SkeletonPanel({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: FinsightColors.gray900,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class SkeletonRows extends StatelessWidget {
  const SkeletonRows({
    this.count = 3,
    this.showLeading = false,
    this.showSubtitle = true,
    super.key,
  });
  final int count;
  final bool showLeading;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < count; index++) ...[
        if (index > 0) const SizedBox(height: 8),
        SkeletonPanel(
          child: Row(
            children: [
              if (showLeading) ...[
                const SkeletonBlock(width: 34, height: 34, radius: 8),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(index.isEven ? .68 : .53),
                    if (showSubtitle) ...[
                      const SizedBox(height: 7),
                      const SkeletonLine(.45, fontSize: 12),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}
