import 'package:flutter/material.dart';

import 'tokens.dart';

enum StatusTone { notice, warning, error }

class StatusMessage extends StatelessWidget {
  const StatusMessage(
    this.message, {
    this.reservedLines = 0,
    this.textAlign,
    this.tone = StatusTone.error,
    super.key,
  });

  const StatusMessage.notice(
    this.message, {
    this.reservedLines = 0,
    this.textAlign,
    super.key,
  }) : tone = StatusTone.notice;

  final String? message;
  final int reservedLines;
  final TextAlign? textAlign;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final notice = tone == StatusTone.notice;
    final content = switch (message) {
      final String text => Semantics(
        liveRegion: true,
        child: Text(
          text,
          textAlign: textAlign ?? (notice ? TextAlign.center : null),
          style: FinsightTypography.bodyR14.copyWith(
            color: notice ? FinsightColors.noticeText : FinsightColors.error,
          ),
        ),
      ),
      null => const SizedBox.shrink(),
    };
    if (message == null && reservedLines == 0) return content;
    if (reservedLines == 0) {
      if (!notice) return content;
      return DecoratedBox(
        decoration: _noticeDecoration,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 45),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Align(
              alignment: Alignment.center,
              heightFactor: 1,
              child: content,
            ),
          ),
        ),
      );
    }
    final lineHeight = MediaQuery.textScalerOf(context).scale(14) * 1.4;
    final height = (lineHeight * reservedLines).ceilToDouble() + 4;
    final reserved = SizedBox(
      height: height,
      width: double.infinity,
      child: message == null
          ? null
          : SingleChildScrollView(
              primary: false,
              padding: notice
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 2)
                  : null,
              child: notice
                  ? ConstrainedBox(
                      constraints: BoxConstraints(minHeight: height - 4),
                      child: Center(heightFactor: 1, child: content),
                    )
                  : content,
            ),
    );
    return notice && message != null
        ? DecoratedBox(decoration: _noticeDecoration, child: reserved)
        : reserved;
  }
}

final _noticeDecoration = BoxDecoration(
  color: FinsightColors.noticeSurface,
  borderRadius: BorderRadius.circular(20),
);

SnackBar statusSnackBar(
  String message, {
  StatusTone tone = StatusTone.notice,
}) => SnackBar(
  content: Text(
    message,
    textAlign: TextAlign.center,
    style: FinsightTypography.bodyR14.copyWith(
      color: tone == StatusTone.notice
          ? FinsightColors.noticeText
          : FinsightColors.error,
    ),
  ),
);
