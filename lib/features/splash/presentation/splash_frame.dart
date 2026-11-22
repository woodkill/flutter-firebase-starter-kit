// 스플래시 화면의 틀 — 킷 파일이다. 내 화면의 값(배경색 · 로고)과 로고 아래
// 내용은 `splash_body.dart` 에 둔다. 로고 자리 · 크기를 바꾸려면 이 파일을
// 고쳐야 하고, 킷 업데이트 때 생기는 충돌은 직접 푼다.
import 'dart:async';

import 'package:flutter/foundation.dart';
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
///   같은 규칙). 화면보다 커도 줄이지 않는다. 로고를 읽지 못하면 그 자리를
///   비우고 디버그 로그에 경로와 원인을 남긴다.
/// - 앱 시작이 [precacheSplashLogo] 로 로고를 미리 디코딩해 두므로 첫 프레임부터
///   로고가 그 크기로 보인다.
/// - 로고 아래 내용은 배경 밝기로 고른 라이트 · 다크 테마 아래에서 그린다.
///   테마는 본문 안쪽에만 씌운다 — 화면 위에 띄우는 대화상자 · 알림 막대는 앱
///   테마 그대로다.
/// - 상태 표시줄은 바탕을 투명으로 두고, 아이콘 밝기는 배경 밝기를 따른다.
///   내비게이션 바 값은 걸지 않는다.
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
    final ExactAssetImage logo = _buildSplashLogoImage(
      MediaQuery.platformBrightnessOf(context),
    );
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
      // 상태 표시줄 세 필드와 내비게이션 바 세 필드를 담는다. 상태 표시줄 바탕은
      // 투명이다 — 바탕색이 없으면 Android 14 이하에서 엔진이 상태 표시줄을 25%
      // 어둡게 칠하고, 투명은 M3 AppBar 가 쓰는 값이라 다음 화면에 남아도 그대로다.
      // 내비게이션 바는 투명 · 대비 강제 끔이다 — 3버튼 막을 꺼 배경색이 바
      // 아래까지 이어진다. 다음 화면은 앱 맨 바깥 영역(`AppSystemBarsRegion`)이
      // 같은 세 필드를 기본 값으로 되돌린다. SDK 프리셋
      // (`SystemUiOverlayStyle.light` · `.dark`)은 내비게이션 바를 불투명 검정으로
      // 담아 쓰지 않는다. 아이콘은 밝은 배경에 어둡게, 어두운 배경에 밝게 —
      // statusBarBrightness 는 iOS 용으로 반대 값이다.
      value: SystemUiOverlayStyle(
        // design-literal: 상태 표시줄 바탕은 투명이다 — 색 토큰 자리가 아니다
        statusBarColor: const Color(0x00000000),
        statusBarIconBrightness: isBackgroundDark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: isBackgroundDark
            ? Brightness.dark
            : Brightness.light,
        // design-literal: 내비게이션 바 바탕은 투명이다 — 색 토큰 자리가 아니다
        systemNavigationBarColor: const Color(0x00000000),
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: isBackgroundDark
            ? Brightness.light
            : Brightness.dark,
      ),
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
                    child: Image(
                      image: logo,
                      errorBuilder: (_, error, stackTrace) {
                        // 로고를 읽지 못하면 자리는 비우되 원인은 디버그 로그로
                        // 남긴다 — 경로가 pubspec.yaml 의 flutter: assets: 에
                        // 등록되지 않은 경우가 흔하다.
                        if (kDebugMode) {
                          debugPrint(
                            'splash_logo load failed (${logo.assetName}): '
                            '$error\n$stackTrace',
                          );
                        }
                        return const SizedBox.shrink();
                      },
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

/// 로고 원본 픽셀을 화면 크기로 바꾸는 나눗수다 — 네이티브 스플래시와 같은 ÷ 4.
const double _kSplashLogoScale = 4;

/// OS 밝기 [osBrightness] 에 맞는 스플래시 로고 그림 제공자를 만든다.
///
/// [SplashFrame] 의 로고와 [precacheSplashLogo] 가 이 함수 하나를 같이 쓴다 —
/// 자산 · 배율이 같아야 이미지 캐시 키가 같아서, 미리 디코딩한 그림을 첫
/// 프레임이 그대로 쓴다.
ExactAssetImage _buildSplashLogoImage(Brightness osBrightness) =>
    ExactAssetImage(
      osBrightness == Brightness.dark ? kSplashImageDark : kSplashImage,
      scale: _kSplashLogoScale,
    );

/// 스플래시 로고를 `runApp` 전에 디코딩해 이미지 캐시에 넣어 둔다.
///
/// Android 12 이상은 Flutter 첫 프레임에서 OS 스플래시를 걷는다. 그 프레임에
/// 로고가 아직 디코딩되지 않았으면 로고 칸이 0 × 0 이라 로고가 빠지고 아래
/// 내용이 화면 가운데로 올라붙는다. 미리 디코딩해 두면 [SplashFrame] 이 첫
/// 프레임부터 로고를 원본 ÷ 4 크기로 그린다.
///
/// - 지금 OS 밝기의 로고 하나만 디코딩한다. [osBrightness] 가 null 이면
///   [SplashFrame] 의 `MediaQuery` 와 같은 출처(바인딩의 platformDispatcher)의
///   밝기를 쓴다 — 앱에서는 [PlatformDispatcher.instance] 와 같은 객체다.
/// - [bundle] 이 null 이면 앱의 로고 `Image` 와 같은 [rootBundle] 에서 읽는다.
/// - throw 하지 않고 [timeout] 안에 끝난다. 자산이 없거나 디코딩에 실패하거나
///   자산 묶음이 멈추면 디버그 로그만 남긴다 — 그때 로고는 지금처럼 첫 프레임
///   뒤에 그려진다. 상한 시간의 값과 이유는 부르는 쪽(앱 시작)이 정한다.
Future<void> precacheSplashLogo({
  required Duration timeout,
  AssetBundle? bundle,
  Brightness? osBrightness,
}) async {
  final ExactAssetImage logo = _buildSplashLogoImage(
    osBrightness ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );
  final completer = Completer<void>();
  final listener = ImageStreamListener(
    (image, synchronousCall) {
      // 받은 그림은 이 리스너 몫의 사본이다 — 캐시의 그림은 그대로 남는다.
      image.dispose();
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
    onError: (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
  );
  ImageStream? stream;
  try {
    stream = logo.resolve(ImageConfiguration(bundle: bundle ?? rootBundle))
      ..addListener(listener);
    await completer.future.timeout(timeout);
  } on TimeoutException {
    if (kDebugMode) {
      debugPrint(
        'splash_logo precache timed out (${logo.assetName}) after '
        '${timeout.inMilliseconds}ms',
      );
    }
  } on Object catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint(
        'splash_logo precache failed (${logo.assetName}): '
        '$error\n$stackTrace',
      );
    }
  } finally {
    // 캐시에 든 그림은 리스너를 떼도 남는다 — 첫 프레임의 로고 Image 가 같은
    // 키로 바로 받아 간다.
    stream?.removeListener(listener);
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
