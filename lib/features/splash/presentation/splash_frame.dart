// 스플래시 화면의 틀 — 킷 파일이다. 내 화면의 값(배경색 · 로고)과 로고 아래
// 내용은 `splash_body.dart` 에 둔다. 로고 자리 · 크기를 바꾸려면 이 파일을
// 고쳐야 하고, 킷 업데이트 때 생기는 충돌은 직접 푼다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import 'splash_body.dart';

/// 스플래시 로고 아래 내용을 만드는 함수 꼴이다.
///
/// [context] 는 [SplashFrame] 이 배경 밝기에 맞춰 씌운 테마 아래에 있다 — 글자 ·
/// 진행 표시 색을 이 [context] 의 테마에서 읽으면 배경에 맞는 색이 된다.
/// `hasFailure` 는 초기화가 실패해 대화상자를 띄운 뒤 true 다 — 진행 표시를
/// 숨기는 신호다.
typedef SplashBodyBuilder =
    Widget Function(BuildContext context, {required bool hasFailure});

/// 스플래시 화면의 틀 — 배경 · 로고 · 상태 표시줄을 네이티브 스플래시와 같게
/// 그리고, 로고 아래에 내용을 둔다.
///
/// - 배경 · 로고는 앱 테마가 아니라 OS 밝기를 따른다. OS 라이트면 [color]
///   (없으면 [kSplashColor]) 배경에 [kSplashImage], OS 다크면 [colorDark]
///   (없으면 [kSplashColorDark]) 배경에 [kSplashImageDark] 를 그린다 —
///   네이티브 스플래시가 앱 설정을 따를 수 없어서다.
/// - 로고는 화면 정가운데에 원본 픽셀 ÷ 4 크기로 그린다(네이티브 스플래시와
///   같은 규칙). 화면보다 커도 줄이지 않는다.
/// - 로고 아래 내용은 배경 밝기로 고른 라이트 · 다크 테마 아래에서 그린다.
///   테마는 본문 안쪽에만 씌운다 — 화면 위에 띄우는 대화상자 · 알림 막대는 앱
///   테마 그대로다.
/// - 상태 표시줄 아이콘 밝기도 배경 밝기를 따른다.
class SplashFrame extends StatelessWidget {
  /// [SplashFrame] 을 생성한다.
  const SplashFrame({
    required this.hasFailure,
    this.bodyBuilder,
    this.color,
    this.colorDark,
    super.key,
  });

  /// 초기화가 실패해 대화상자를 띄운 뒤인지 — 로고 아래 내용에 그대로 넘긴다.
  final bool hasFailure;

  /// 로고 아래 내용을 만드는 함수 — null 이면 [buildSplashBody] 를 쓴다.
  ///
  /// 킷 시험은 시험용 내용을 넘겨 내 화면이 섞이지 않게 그린다.
  final SplashBodyBuilder? bodyBuilder;

  /// OS 라이트일 때의 배경색 — null 이면 [kSplashColor] 다.
  final Color? color;

  /// OS 다크일 때의 배경색 — null 이면 [kSplashColorDark] 다.
  final Color? colorDark;

  @override
  Widget build(BuildContext context) {
    final isOsDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final Color background = isOsDark
        ? colorDark ?? kSplashColorDark
        : color ?? kSplashColor;
    final String logoAsset = isOsDark ? kSplashImageDark : kSplashImage;
    final isBackgroundDark =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
    // OS 가 대비를 높이면 앱의 대비 테마(lib/app.dart)와 같은 1.0 팔레트를 쓴다 —
    // 대비 값은 SDK 문서의 -1.0 ~ 1.0 꼴 그대로 소수로 적는다.
    final contrastLevel = MediaQuery.highContrastOf(context) ? 1.0 : 0.0;
    final ThemeData bodyTheme = isBackgroundDark
        ? AppTheme.dark(
            seedColor: AppTheme.brandColor,
            contrastLevel: contrastLevel,
          )
        : AppTheme.light(
            seedColor: AppTheme.brandColor,
            contrastLevel: contrastLevel,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 밝은 배경에는 어두운 아이콘, 어두운 배경에는 밝은 아이콘이다.
      value: isBackgroundDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: background,
        body: Theme(
          data: bodyTheme,
          child: Builder(
            builder: (themedContext) => DefaultTextStyle.merge(
              style: Theme.of(themedContext).textTheme.bodyMedium,
              child: CustomMultiChildLayout(
                delegate: _SplashLayoutDelegate(),
                children: <Widget>[
                  LayoutId(
                    id: _SplashSlot.logo,
                    child: Image.asset(
                      logoAsset,
                      scale: 4,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  LayoutId(
                    id: _SplashSlot.body,
                    // 상태 표시줄 쪽은 로고가 차지하므로 아래 여백만 피한다.
                    child: SafeArea(
                      top: false,
                      // 가로 화면 · 큰 글자에서 넘치면 스크롤한다.
                      child: SingleChildScrollView(
                        child: Builder(
                          builder: (bodyContext) =>
                              (bodyBuilder ?? buildSplashBody)(
                                bodyContext,
                                hasFailure: hasFailure,
                              ),
                        ),
                      ),
                    ),
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

/// [_SplashLayoutDelegate] 가 놓는 자리 이름이다.
enum _SplashSlot { logo, body }

/// 로고를 화면 정가운데에 놓고, 로고 아래부터 화면 아래까지를 내용 칸으로 놓는다.
class _SplashLayoutDelegate extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    // 로고는 제약 없이 놓아 디코딩된 크기(원본 ÷ 4) 그대로 둔다 — 화면보다 커도
    // 줄이지 않는다.
    final Size logoSize = layoutChild(_SplashSlot.logo, const BoxConstraints());
    final logoOffset = Offset(
      (size.width - logoSize.width) / 2,
      (size.height - logoSize.height) / 2,
    );
    positionChild(_SplashSlot.logo, logoOffset);

    final double bodyTop = logoOffset.dy + logoSize.height;
    final double bodyHeight = size.height > bodyTop ? size.height - bodyTop : 0;
    layoutChild(
      _SplashSlot.body,
      BoxConstraints.tight(Size(size.width, bodyHeight)),
    );
    positionChild(_SplashSlot.body, Offset(0, bodyTop));
  }

  @override
  bool shouldRelayout(_SplashLayoutDelegate oldDelegate) => false;
}
