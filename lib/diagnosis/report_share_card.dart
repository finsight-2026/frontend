import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../design/status_message.dart';
import '../design/finsight_wordmark.dart';
import '../design/financial_score_ring.dart';
import '../design/tokens.dart';

String reportScoreChange(int change) => '${change > 0 ? '+' : ''}$change점';

class ReportShareCard extends StatefulWidget {
  const ReportShareCard({
    required this.month,
    required this.badge,
    required this.score,
    this.scoreChange,
    this.navigationBar,
    super.key,
  });

  final String month;
  final String badge;
  final int score;
  final int? scoreChange;
  final Widget? navigationBar;

  @override
  State<ReportShareCard> createState() => _ReportShareCardState();
}

class _ReportShareCardState extends State<ReportShareCard> {
  final _card = GlobalKey();
  bool _hideScore = false;
  bool _hideBadge = false;
  bool _sharing = false;
  String? _error;

  Future<void> _privacy() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheet) => StatefulBuilder(
      builder: (context, updateSheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                title: const Text('점수 가리기'),
                value: _hideScore,
                onChanged: (value) {
                  setState(() => _hideScore = value);
                  updateSheet(() {});
                },
              ),
              SwitchListTile(
                title: const Text('유형 가리기'),
                value: _hideBadge,
                onChanged: (value) {
                  setState(() => _hideBadge = value);
                  updateSheet(() {});
                },
              ),
              FilledButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('확인'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _share(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('카드가 준비되지 않았습니다.');
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (!mounted) return;
        if (bytes == null) throw StateError('카드 이미지 생성에 실패했습니다.');
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
                mimeType: 'image/png',
              ),
            ],
            fileNameOverrides: ['finsight-${widget.month}.png'],
            sharePositionOrigin: origin,
            downloadFallbackEnabled: false,
          ),
        );
        if (result.status == ShareResultStatus.unavailable) {
          _error = '이 환경에서는 공유 창을 열 수 없어요.';
        }
      } finally {
        image.dispose();
      }
    } on Exception {
      _error = '공유 창을 열지 못했어요. 다시 시도해주세요.';
    } on StateError {
      _error = '카드를 준비하지 못했어요. 다시 시도해주세요.';
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('나의 금융 카드'),
        centerTitle: true,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: _sharing ? null : _privacy,
            tooltip: '카드 표시 설정',
            icon: const Icon(Icons.tune, size: 20),
          ),
          Builder(
            builder: (anchor) => IconButton(
              onPressed: _sharing ? null : () => _share(anchor),
              tooltip: '공유하기',
              icon: const Icon(Icons.ios_share, size: 20),
            ),
          ),
        ],
      ),
      bottomNavigationBar: widget.navigationBar,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 36, 20, 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RepaintBoundary(
                    key: _card,
                    child: _FinancialCard(
                      month: widget.month,
                      badge: _hideBadge ? null : widget.badge,
                      score: _hideScore ? null : widget.score,
                      scoreChange: _hideScore ? null : widget.scoreChange,
                    ),
                  ),
                  StatusMessage(_error, reservedLines: 2),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _sharing
                        ? null
                        : () => Navigator.of(context).pop(0),
                    child: const Text('홈 화면으로 돌아가기'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FinancialCard extends StatelessWidget {
  const _FinancialCard({
    required this.month,
    required this.badge,
    required this.score,
    required this.scoreChange,
  });

  final String month;
  final String? badge;
  final int? score;
  final int? scoreChange;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      boxShadow: [
        BoxShadow(
          color: FinsightColors.gray700.withValues(alpha: .23),
          blurRadius: 24,
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FinsightColors.gray750),
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: .95,
            colors: [
              FinsightColors.neonLime900.withValues(alpha: .7),
              FinsightColors.gray1000,
            ],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(left: 32, top: 132, child: _CardOrb(31)),
            const Positioned(
              right: -22,
              top: 207,
              child: _CardOrb(86, rimOnRight: false),
            ),
            const Positioned(
              right: 51,
              top: 254,
              child: _CardOrb(23, rimOnRight: false),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FinsightWordmark(width: 62),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${month.replaceFirst('-', '.')} · FINANCIAL MIND REPORT',
                    style: FinsightTypography.captionR10.copyWith(
                      color: FinsightColors.gray600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    '나의 금융 마음 점수',
                    style: FinsightTypography.displaySb28,
                  ),
                  const SizedBox(height: 5),
                  Center(child: FinancialScoreRing(score: score, size: 192)),
                  if (scoreChange case final change?) ...[
                    const SizedBox(height: 3),
                    _CardPill(
                      change == 0
                          ? '지난달과 같아요'
                          : '지난달보다 ${change.abs()}점 ${change < 0 ? '낮아졌어요' : '높아졌어요'}',
                    ),
                  ],
                  if (badge case final badge?) ...[
                    const SizedBox(height: 12),
                    _CardPill(badge),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    '“조금씩,\n더 나은 내일을 만들고 있어요.”',
                    textAlign: TextAlign.center,
                    style: FinsightTypography.displaySb22,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '나의 금융 마음을 이해하는 습관',
                          style: FinsightTypography.captionR10.copyWith(
                            color: FinsightColors.gray600,
                          ),
                        ),
                      ),
                      Text(
                        'FINSIGHT',
                        style: FinsightTypography.captionR10.copyWith(
                          color: FinsightColors.gray600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CardPill extends StatelessWidget {
  const _CardPill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: FinsightColors.neonLime900.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: FinsightTypography.labelM12.copyWith(
            color: FinsightColors.neonLime400,
          ),
        ),
      ),
    ),
  );
}

class _CardOrb extends StatelessWidget {
  const _CardOrb(this.size, {this.rimOnRight = true});
  final double size;
  final bool rimOnRight;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(rimOnRight ? -.5 : .36, -.36),
          radius: .86,
          colors: const [
            FinsightColors.gray1000,
            FinsightColors.gray1000,
            FinsightColors.neonLime900,
            FinsightColors.neonLime500,
          ],
          stops: const [0, .43, .76, 1],
        ),
      ),
    ),
  );
}
