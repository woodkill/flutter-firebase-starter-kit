// Phase 16.10 — see ROADMAP.md
//
// provider 측 연결 끊기 레지스트리 (C-08 · RESEARCH Pattern 3).
//
// 레지스트리는 const 목록이다 — step 은 stateless 이고 Firebase · SDK
// 인스턴스는 [disconnectDeps] 가 `run` 시점에만 넘긴다. 그래서 행 종류만
// 읽는 해제 다이얼로그 · golden · widget 테스트는 Firebase 초기화 없이
// [disconnectSteps] 를 읽을 수 있다(Firebase 미초기화 assert 회피).
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/auth/provider_id.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../auth/data/line_sdk_client.dart';
import '../../../auth/data/naver_sdk_client.dart';
import 'apple_disconnect_step.dart';
import 'disconnect_step.dart';
import 'google_disconnect_step.dart';
import 'line_disconnect_step.dart';
import 'naver_disconnect_step.dart';
import 'server_disconnect_step.dart';

part 'disconnect_steps.g.dart';

/// 등록된 provider 측 끊기 step 목록.
///
/// 목록 순서는 표시 순서가 아니다 — 진행 화면은 provider 표시 순서 상수로
/// 정렬하고 서버 행을 먼저 둔다(plan 07). provider 추가 = step 1줄(재로그인
/// 행이면 step 파일 1개 추가) · 제거 = 이 목록의 그 줄 + (재로그인 행이면)
/// step 파일 삭제. 목록에 없는 provider(email 등)는 끊을 연결이 없는 행이다.
const List<DisconnectStep> kDisconnectSteps = <DisconnectStep>[
  ServerDisconnectStep(
    provider: AccountProvider.kakao,
    callableName: 'disconnectKakaoProvider',
  ),
  ServerDisconnectStep(
    provider: AccountProvider.facebook,
    callableName: 'disconnectFacebookProvider',
  ),
  GoogleDisconnectStep(),
  AppleDisconnectStep(),
  NaverDisconnectStep(),
  LineDisconnectStep(),
];

/// 끊기 step 레지스트리를 제공한다 — Firebase 를 읽지 않는다.
@riverpod
List<DisconnectStep> disconnectSteps(Ref ref) => kDisconnectSteps;

/// 끊기 step 의 실행 의존을 제공한다 (keepAlive — 인프라 묶음).
///
/// 인프라 provider 를 여기서만 읽는다 — `run` 을 호출하는 시점(진행 화면 ·
/// 해제 다이얼로그 확인 뒤)에만 평가되므로 Firebase 미초기화 화면은 이
/// provider 를 읽지 않는다.
@Riverpod(keepAlive: true)
DisconnectDeps disconnectDeps(Ref ref) => DisconnectDeps(
  auth: ref.watch(firebaseAuthProvider),
  functions: ref.watch(firebaseFunctionsProvider),
  googleSignIn: ref.watch(googleSignInProvider),
  lineSdkClient: ref.watch(lineSdkClientProvider),
  naverSdkClient: ref.watch(naverSdkClientProvider),
  platform: defaultTargetPlatform,
);
