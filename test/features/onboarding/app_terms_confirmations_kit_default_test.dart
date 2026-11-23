// 킷 판 확인 행 자리를 보는 유지보수자 전용 시험 — adopter 가 사용자 파일을
// 채우면 SLOT-01 은 실패하는 것이 맞으므로 유지보수자 트리에서만 돈다.
import 'package:flutter/widgets.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/app_terms_confirmation_slot.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/app_terms_confirmations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/planning_docs.dart';
import '../../helpers/source_text.dart';

/// 온보딩 화면 소스 경로.
const _screenPath =
    'lib/features/onboarding/presentation/onboarding_screen.dart';

/// 사용자 파일 경로.
const _userFilePath =
    'lib/features/onboarding/presentation/app_terms_confirmations.dart';

/// 킷 파일 경로.
const _kitFilePath =
    'lib/features/onboarding/presentation/app_terms_confirmation_slot.dart';

void main() {
  group('약관 확인 행 자리 — 킷 판', () {
    // testWidgets 의 skip 은 bool 이라 건너뛸 이유를 실을 수 없다 — 이 시험
    // 하나만 감싼 group 에 skip 을 둔다.
    group(
      '사용자 파일 기본값',
      () {
        testWidgets(
          'T-33-SLOT-01: 킷 판 buildAppTermsConfirmations 는 빈 목록을 돌려준다',
          (tester) async {
            late List<AppTermsConfirmation> confirmations;
            await tester.pumpWidget(
              Builder(
                builder: (context) {
                  confirmations = buildAppTermsConfirmations(
                    AppTermsConfirmationsInput(context: context),
                  );
                  return const SizedBox.shrink();
                },
              ),
            );

            expect(confirmations, isEmpty);
          },
        );
      },
      // adopter 가 채우는 사용자 파일이라 유지보수자 트리에서만 본다.
      skip: skipUnlessMaintainerTree(),
    );

    test(
      'T-33-SLOT-02: onboarding_screen.dart 는 형을 적은 지역 변수로 '
      'buildAppTermsConfirmations 를 묶는다',
      () {
        final String code = stripSlashComments(readTrackedFile(_screenPath));

        expect(
          RegExp(
            r'final\s+AppTermsConfirmationsBuilder\s+\w+\s*=\s*widget\s*\.\s*termsConfirmationsBuilder\s*\?\?\s*buildAppTermsConfirmations\s*;',
          ).allMatches(code).length,
          1,
        );
      },
      // 사용자 파일 함수와 묶는 꼴을 보는 킷 소스 시험이라 유지보수자 트리에서만 본다.
      skip: skipUnlessMaintainerTree(),
    );

    test(
      'T-33-SLOT-03: 두 자리 파일의 첫 줄이 소유를 밝힌다',
      () {
        expect(
          readTrackedFile(_userFilePath).split('\n').first,
          '// 약관 동의 묶음에 더하는 필수 확인 행 목록 — 내 앱의 파일이다(킷 판은 빈 목록).',
        );
        expect(
          readTrackedFile(_kitFilePath).split('\n').first,
          '// 약관 동의 묶음 필수 확인 행 자리의 행 타입 · 입력 객체 · builder 꼴 — 킷 파일이다',
        );
      },
      // adopter 가 사용자 파일 머리를 고칠 수 있어 유지보수자 트리에서만 본다.
      skip: skipUnlessMaintainerTree(),
    );
  });
}
