import '../flavor.dart';
import '../step.dart';
import 'flavor_steps.dart';

/// 개발(dev) 환경 · 켠 로그인 수단 0개의 기본 단계 목록을 순서대로 만든다.
///
/// 기본 순서를 확인하는 테스트용이다 — 실제 진입은 config 의 로그인 수단을 읽어
/// [buildSteps] 를 부른다.
List<Step> buildDevSteps() =>
    buildSteps(flavor: Flavor.dev, enabledProviders: const <String>{});
