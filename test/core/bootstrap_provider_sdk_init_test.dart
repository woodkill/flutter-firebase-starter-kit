import 'dart:io';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/bootstrap.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// [source] 에서 `//` 주석 줄을 뺀 코드 줄만 남긴다.
String _codeLines(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// 초기화 함수를 실행하지 않는 가짜 표 3줄(google · kakao · line)을 만든다.
List<ProviderSdkInit> _buildFakeTable() => <ProviderSdkInit>[
  (providerId: kProviderIdGoogle, label: 'google', init: () async {}),
  (providerId: kProviderIdKakao, label: 'kakao', init: () async {}),
  (providerId: kProviderIdLine, label: 'line', init: () async {}),
];

/// 표의 providerId 만 순서대로 뽑는다.
List<String> _collectProviderIds(List<ProviderSdkInit> entries) => <String>[
  for (final entry in entries) entry.providerId,
];

void main() {
  group('Phase 17.3 provider SDK 초기화 표 (D-02 · D-03)', () {
    test('T-173-INIT-01: 빈 CSV 면 초기화를 하나도 고르지 않는다', () {
      final selected = selectEnabledSdkInits(
        _buildFakeTable(),
        AppConfig.parseEnabledProviders(''),
      );
      expect(selected, isEmpty);
    });

    test('T-173-INIT-02: google 만 켜면 Google 초기화 1개만 고른다', () {
      final selected = selectEnabledSdkInits(
        _buildFakeTable(),
        AppConfig.parseEnabledProviders('google'),
      );
      expect(_collectProviderIds(selected), <String>[kProviderIdGoogle]);
    });

    test('T-173-INIT-03: 6개 전부 켜면 표의 3개를 표 순서대로 고른다', () {
      final selected = selectEnabledSdkInits(
        _buildFakeTable(),
        AppConfig.parseEnabledProviders(
          'google,apple,facebook,kakao,naver,line',
        ),
      );
      expect(_collectProviderIds(selected), <String>[
        kProviderIdGoogle,
        kProviderIdKakao,
        kProviderIdLine,
      ]);
    });

    test('T-173-INIT-04: Dart 초기화가 없는 provider 만 켜면 0개다', () {
      final selected = selectEnabledSdkInits(
        _buildFakeTable(),
        AppConfig.parseEnabledProviders('apple,facebook,naver'),
      );
      expect(selected, isEmpty);
    });

    test('T-173-INIT-05: 실 표는 google · kakao · line 3줄이고 label 이 기존 문구다', () {
      // 초기화 함수는 실행하지 않는다 — providerId · label 만 본다.
      final table = buildProviderSdkInits();
      final ids = _collectProviderIds(table);
      expect(ids, <String>[
        kProviderIdGoogle,
        kProviderIdKakao,
        kProviderIdLine,
      ]);
      for (final id in ids) {
        expect(kAllProviderIds, contains(id), reason: '$id 는 등록된 slug 여야 한다');
      }
      expect(ids.toSet().length, ids.length, reason: 'providerId 중복 0');
      expect(
        <String>[for (final entry in table) entry.label],
        <String>[
          'GoogleSignIn.initialize()',
          'KakaoSdk.init()',
          'LineSDK.setup()',
        ],
      );
    });

    test('T-173-INIT-06: 세 SDK 직접 호출은 표 안에만 1회씩 · 루프는 RC fetch 앞', () {
      final code = _codeLines(
        File('lib/core/bootstrap.dart').readAsStringSync(),
      );

      // 세 SDK 호출 — 각각 정확히 1회. Kakao 는 표 label 문자열
      // ('KakaoSdk.init()')을 세지 않도록 인자 이름까지 맞춘다.
      final googleCalls = 'GoogleSignIn.instance.initialize('.allMatches(code);
      final kakaoCalls = RegExp(
        r'KakaoSdk\.init\(\s*nativeAppKey',
      ).allMatches(code);
      final lineCalls = 'LineSDK.instance.setup('.allMatches(code);
      expect(googleCalls.length, 1, reason: 'GoogleSignIn 초기화는 표 안 1곳');
      expect(kakaoCalls.length, 1, reason: 'KakaoSdk 초기화는 표 안 1곳');
      expect(lineCalls.length, 1, reason: 'LineSDK 초기화는 표 안 1곳');

      // 세 호출 모두 표 선언과 선택 함수 선언 사이에 있다.
      final tableIdx = code.indexOf(
        'List<ProviderSdkInit> buildProviderSdkInits()',
      );
      final selectIdx = code.indexOf(
        'List<ProviderSdkInit> selectEnabledSdkInits(',
      );
      expect(tableIdx, greaterThan(0));
      expect(selectIdx, greaterThan(tableIdx));
      for (final match in <Match>[
        googleCalls.first,
        kakaoCalls.first,
        lineCalls.first,
      ]) {
        expect(match.start, greaterThan(tableIdx));
        expect(match.start, lessThan(selectIdx));
      }

      // 초기화 루프 — 정적 CSV 로 고르는 호출 1회, Firebase 분기 안 · RC
      // fetch 앞.
      final loopCalls = RegExp(
        r'selectEnabledSdkInits\(\s*buildProviderSdkInits\(\),\s*AppConfig\.authProviders,?\s*\)',
      ).allMatches(code).toList();
      expect(loopCalls, hasLength(1));
      final initIdx = code.indexOf('if (isFirebaseInitialized)');
      final fetchIdx = code.indexOf('fetchAndActivate');
      expect(initIdx, greaterThan(0));
      expect(loopCalls.single.start, greaterThan(initIdx));
      expect(loopCalls.single.start, lessThan(fetchIdx));
    });
  });
}
