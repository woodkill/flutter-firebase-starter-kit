// 스플래시 로고를 runApp 전에 미리 디코딩하면 스플래시 틀의 첫 프레임부터 로고
// 칸이 원본 ÷ 4 크기라는 것을 고정한다 — 미리 디코딩하지 않으면 첫 프레임의
// 로고 칸은 0 × 0 이라 로고가 빠지고 아래 내용이 화면 가운데로 올라붙는다.
// 로고는 시험용 자산 묶음에서 읽으므로 내 로고 파일과 상관없다. 미리 디코딩은
// 실패하거나 멈춰도 throw 없이 상한 시간 안에 끝나야 한다 — 앱 시작이 그 뒤에
// runApp 을 부르기 때문이다.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_body.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_frame.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 로고 원본 픽셀을 화면 크기로 바꾸는 나눗수 — 네이티브 스플래시와 같은 ÷ 4.
const double _imageScale = 4;

/// 큰 로고 PNG 한 변 (px) — 화면에는 288.
const int _largePngPixels = 1152;

/// 작은 로고 PNG 한 변 (px) — 화면에는 128.
const int _smallPngPixels = 512;

/// 시험 화면 크기 (logical px) — 세로 폰.
const Size _portraitSize = Size(360, 800);

/// 디코딩이 되거나 곧바로 실패하는 경우에 넘기는 상한 시간 — 시험 기계가 느려도
/// 넘지 않는 값.
const Duration _decodeTimeout = Duration(seconds: 3);

/// 멈춘 자산 묶음 시험에 넘기는 짧은 상한 시간.
const Duration _stallTimeout = Duration(milliseconds: 100);

/// 시험이 미리 디코딩을 기다리는 한계 — 넘으면 끝나지 않은 것으로 본다.
const Duration _guard = Duration(seconds: 5);

/// 시험용 로고 아래 내용의 글자.
const String _bodyText = 'TEST_BODY';

/// 미리 디코딩 한 번의 결과 — 한계 안에 끝났는지 · 던진 것 · 디버그 로그.
typedef _PrecacheRun = ({bool finished, Object? thrown, List<String> logs});

void main() {
  group('스플래시 로고 미리 디코딩', () {
    for (final pixels in <int>[_largePngPixels, _smallPngPixels]) {
      testWidgets('미리 디코딩하면 첫 프레임 로고 칸 = 원본 ÷ 4 · 아래 내용 위쪽 = '
          '로고 아래쪽 ($pixels px)', (tester) async {
        _restoreBrightnessAfterTest(tester);
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        final bundle = _PngAssetBundle(await _createLogoPng(tester, pixels));

        final run = await _runPrecache(
          tester,
          bundle: bundle,
          timeout: _decodeTimeout,
        );
        expect(run.finished, isTrue, reason: '한계 안에 끝남');
        expect(run.thrown, isNull, reason: 'throw 없음');
        expect(run.logs, isEmpty, reason: '실패 로그 없음');

        await _pumpFrameOnce(tester, bundle);
        final Rect logo = tester.getRect(find.byType(Image));
        expect(
          logo.size,
          Size.square(pixels / _imageScale),
          reason: '첫 프레임 로고 칸',
        );
        expect(
          logo.center,
          _portraitSize.center(Offset.zero),
          reason: '첫 프레임 로고 중심',
        );
        expect(
          tester.getTopLeft(find.text(_bodyText)).dy,
          logo.bottom,
          reason: '첫 프레임 아래 내용 위쪽',
        );
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('OS 밝기(${brightness.name})의 로고를 미리 디코딩해 그 밝기의 '
          '첫 프레임에 로고가 보인다', (tester) async {
        final String expected = brightness == Brightness.dark
            ? kSplashImageDark
            : kSplashImage;
        final String other = brightness == Brightness.dark
            ? kSplashImage
            : kSplashImageDark;
        _restoreBrightnessAfterTest(tester);
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        final bundle = _PngAssetBundle(
          await _createLogoPng(tester, _largePngPixels),
        );

        final run = await _runPrecache(
          tester,
          bundle: bundle,
          timeout: _decodeTimeout,
        );
        expect(run.finished, isTrue, reason: '한계 안에 끝남');
        expect(run.thrown, isNull, reason: 'throw 없음');
        expect(
          imageCache.statusForKey(_logoKey(bundle, expected)).keepAlive,
          isTrue,
          reason: '$expected 를 캐시에 넣음',
        );
        // 내 앱이 라이트 · 다크에 같은 로고를 쓰면 두 키가 같아 이 단언은 뜻이
        // 없다 — 그때는 건너뛴다.
        if (other != expected) {
          expect(
            imageCache.statusForKey(_logoKey(bundle, other)).untracked,
            isTrue,
            reason: '$other 는 디코딩하지 않음',
          );
        }

        await _pumpFrameOnce(tester, bundle);
        expect(
          tester.getSize(find.byType(Image)),
          const Size.square(_largePngPixels / _imageScale),
          reason: '첫 프레임 로고 칸',
        );
      });
    }

    testWidgets('밝기를 넘기면 OS 밝기 대신 그 밝기의 로고를 미리 '
        '디코딩한다', (tester) async {
      _restoreBrightnessAfterTest(tester);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      final bundle = _PngAssetBundle(
        await _createLogoPng(tester, _largePngPixels),
      );

      final run = await _runPrecache(
        tester,
        bundle: bundle,
        osBrightness: Brightness.dark,
        timeout: _decodeTimeout,
      );
      expect(run.finished, isTrue, reason: '한계 안에 끝남');
      expect(run.thrown, isNull, reason: 'throw 없음');
      expect(
        imageCache.statusForKey(_logoKey(bundle, kSplashImageDark)).keepAlive,
        isTrue,
        reason: '넘긴 밝기의 로고를 캐시에 넣음',
      );
      // 내 앱이 라이트 · 다크에 같은 로고를 쓰면 OS 라이트의 첫 프레임도 그
      // 로고라 이 단언은 뜻이 없다 — 그때는 건너뛴다.
      if (kSplashImage != kSplashImageDark) {
        await _pumpFrameOnce(tester, bundle);
        expect(
          tester.getSize(find.byType(Image)),
          Size.zero,
          reason: 'OS 라이트 첫 프레임의 로고는 디코딩 전',
        );
      }
    });

    testWidgets('로고 자산이 없으면 throw 없이 끝나고 경로가 든 디버그 로그를 '
        '남긴다', (tester) async {
      final run = await _runPrecache(
        tester,
        bundle: _MissingAssetBundle(),
        osBrightness: Brightness.light,
        timeout: _decodeTimeout,
      );
      expect(run.finished, isTrue, reason: '한계 안에 끝남');
      expect(run.thrown, isNull, reason: 'throw 없음');
      expect(tester.takeException(), isNull);
      expect(
        run.logs,
        contains(startsWith('splash_logo precache failed ($kSplashImage)')),
      );
    });

    testWidgets('로고를 디코딩하지 못하면 throw 없이 끝나고 경로가 든 디버그 '
        '로그를 남긴다', (tester) async {
      final run = await _runPrecache(
        tester,
        bundle: _BrokenImageBundle(),
        osBrightness: Brightness.light,
        timeout: _decodeTimeout,
      );
      expect(run.finished, isTrue, reason: '한계 안에 끝남');
      expect(run.thrown, isNull, reason: 'throw 없음');
      expect(tester.takeException(), isNull);
      expect(
        run.logs,
        contains(startsWith('splash_logo precache failed ($kSplashImage)')),
      );
    });

    testWidgets('자산 묶음이 멈추면 상한 시간 안에 throw 없이 끝나고 디버그 '
        '로그를 남긴다', (tester) async {
      final run = await _runPrecache(
        tester,
        bundle: _StalledAssetBundle(),
        osBrightness: Brightness.light,
        timeout: _stallTimeout,
      );
      expect(run.finished, isTrue, reason: '한계 안에 끝남');
      expect(run.thrown, isNull, reason: 'throw 없음');
      expect(tester.takeException(), isNull);
      expect(
        run.logs,
        contains(startsWith('splash_logo precache timed out ($kSplashImage)')),
      );
    });
  });
}

/// OS 밝기 시험 값을 시험이 끝나면 되돌리도록 등록한다.
void _restoreBrightnessAfterTest(WidgetTester tester) {
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

/// [precacheSplashLogo] 를 실제 비동기로 한 번 돌리고 결과를 모은다.
///
/// [_guard] 안에 끝나지 않으면 `finished` 가 false 다. [osBrightness] 가 null
/// 이면 함수의 기본 밝기(시험 OS 밝기)를 쓴다.
Future<_PrecacheRun> _runPrecache(
  WidgetTester tester, {
  required AssetBundle bundle,
  required Duration timeout,
  Brightness? osBrightness,
}) async {
  final logs = <String>[];
  Object? thrown;
  var finished = false;
  final DebugPrintCallback original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      logs.add(message);
    }
  };
  try {
    await tester.runAsync(() async {
      final guard = Completer<bool>();
      final timer = Timer(_guard, () => guard.complete(false));
      try {
        final Future<void> precache = precacheSplashLogo(
          timeout: timeout,
          bundle: bundle,
          osBrightness: osBrightness,
        );
        finished = await Future.any(<Future<bool>>[
          precache.then((_) => true),
          guard.future,
        ]);
      } on Object catch (error) {
        thrown = error;
      } finally {
        timer.cancel();
      }
    });
  } finally {
    debugPrint = original;
  }
  return (finished: finished, thrown: thrown, logs: logs);
}

/// [bundle] 에서 읽은 [asset] 로고의 이미지 캐시 키 — 스플래시 틀의 키와 같은 꼴.
AssetBundleImageKey _logoKey(AssetBundle bundle, String asset) =>
    AssetBundleImageKey(bundle: bundle, name: asset, scale: _imageScale);

/// [SplashFrame] 을 [bundle] 의 로고로 세로 폰 화면에 한 번만 그린다(첫 프레임).
Future<void> _pumpFrameOnce(WidgetTester tester, AssetBundle bundle) async {
  tester.view.physicalSize = _portraitSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DefaultAssetBundle(
        bundle: bundle,
        child: const SplashFrame(
          hasFailure: false,
          bodyBuilder: _buildTestBody,
        ),
      ),
    ),
  );
}

/// 킷 시험용 로고 아래 내용 — 내 화면의 내용이 섞이지 않게 글자 하나만 둔다.
Widget _buildTestBody(BuildContext context, {required bool hasFailure}) =>
    const Text(_bodyText);

/// 한 변 [pixels] px 정사각 불투명 PNG 바이트를 만든다(`runAsync` 안에서 인코딩).
Future<ByteData> _createLogoPng(WidgetTester tester, int pixels) async {
  final png = await tester.runAsync<ByteData?>(() async {
    final recorder = ui.PictureRecorder();
    final side = pixels.toDouble();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, side, side),
      Paint()..color = const Color(0xFF1A2340),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(pixels, pixels);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data;
  });
  if (png == null) {
    throw TestFailure('$pixels px 로고 PNG 를 만들지 못했다.');
  }
  return png;
}

/// 모든 자산 키에 같은 PNG 바이트를 돌려주는 시험용 자산 묶음이다.
///
/// 이미지 캐시 키는 묶음 인스턴스까지 비교하므로 시험마다 새 인스턴스를 주면
/// 앞 시험이 디코딩한 로고를 다시 쓰지 않는다.
class _PngAssetBundle extends CachingAssetBundle {
  _PngAssetBundle(this._png);

  final ByteData _png;

  @override
  Future<ByteData> load(String key) async => _png;
}

/// 모든 자산 키에서 읽기 실패를 던지는 시험용 자산 묶음이다 — 등록되지 않은
/// 로고 경로와 같은 실패다.
class _MissingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('Unable to load asset: "$key".');
}

/// 그림이 아닌 바이트를 돌려주는 시험용 자산 묶음이다 — 디코딩이 실패한다.
class _BrokenImageBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(List<int>.filled(16, 0)));
}

/// 읽기가 끝나지 않는 시험용 자산 묶음이다 — 멈춘 자산 읽기와 같다.
class _StalledAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Completer<ByteData>().future;
}
