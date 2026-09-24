package com.slimpumpkin.flutter_starter_kit

// Phase 16.5 — see ROADMAP.md (G-16.5-2 — flutter_web_auth_2 Custom Tab fallback 콜백 relay)
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.linusu.flutter_web_auth_2.FlutterWebAuth2Plugin

/**
 * flutter_web_auth_2 의 Custom Tab fallback 콜백을 받는 킷 소유 relay Activity (G-16.5-2).
 *
 * **왜** — upstream 콜백 Activity 의 Custom Tab 닫기는 인증 관리 Activity 를
 * CLEAR_TOP|SINGLE_TOP 으로 NEW_TASK 없이 다시 띄우는 **같은 task 전용** 설계다.
 * 킷의 MainActivity(Flutter 템플릿) 와 콜백 수신 Activity 는 둘 다 빈 taskAffinity 라
 * 브라우저가 띄운 콜백 Activity 는 항상 새 task 에 떨어지고, 원본 인증 관리 Activity 와
 * 그 위 Custom Tab 이 있는 main task 에 닿지 못해 tab 이 검은 화면으로 남는다.
 * upstream #158 OPEN · 5.1.0 = 6.0.0-alpha.8 = master 해당 파일 byte 동일 ·
 * SM-S942N Samsung Internet 30(Auth Tab 미지원) 실측.
 *
 * **무엇** —
 * 1. intent data 의 scheme 으로 플러그인 대기 호출을 꺼내 URL 을 success 로 넘긴다
 *    (upstream 콜백 Activity 와 같은 전달 경로).
 * 2. MainActivity 의 기존 task 를 NEW_TASK|CLEAR_TOP|SINGLE_TOP 으로 전면 복귀시킨다.
 *    NEW_TASK 가 task 검색을 켜고 MainActivity 가 root 인 main task 는 component 일치로
 *    찾아진다(affinity 가 비어 있어도 무관). CLEAR_TOP 이 그 위의 원본 인증 관리
 *    Activity 와 브라우저 tab 을 걷고, SINGLE_TOP + manifest singleTop 이 MainActivity
 *    재생성을 막아 Flutter 엔진과 대기 중인 로그인 상태를 유지한다.
 * 3. finish 한다.
 *
 * **순서가 계약이다** — success 전달이 MainActivity 전면 복귀보다 먼저여야 한다.
 * flutter_web_auth_2 Dart 의 resume observer 는 앱 resume 시 map 에 남은 대기 호출을
 * 전부 CANCELED 로 접는다 (T-16.5-NATIVE-09 가 소스 순서로 잠근다).
 *
 * **Chrome Auth Tab 경로는 이 Activity 를 기동하지 않는다** — 결과가 ActivityResult 로
 * 돌아오므로 이 변경의 영향이 없다 (plan 06 UAT 실측 콜백 Activity START 0).
 *
 * **로그 없음** — 콜백 URL 에 code · state 가 실린다 (C-01). 어떤 로그 호출도 두지 않는다.
 *
 * data 가 없는 intent 는 전달을 건너뛰되 전면 복귀는 한다 — 사용자가 tab 에 갇히지
 * 않게 한다 (AppAuth RedirectUriReceiverActivity 선례).
 *
 * try/catch 는 두지 않는다 — 앱 내부 명시 component 라 ActivityNotFound 가 없고,
 * 유일한 실패(BAL/ASM 차단)는 시스템 쪽 무음이라 plan 09 UAT 가 실측으로 판정한다.
 *
 * **유지보수** — flutter_web_auth_2 상향 시 upstream 콜백 Activity 와 플러그인 companion
 * 의 callbacks map 이 그대로인지 확인한다. callbacks 가 사라지면 이 파일의 빌드가
 * 실패한다(조용한 실패 아님 — P-03). upstream 이 #158 을 고치면 README 의 콜백 Activity
 * 선언으로 되돌리고 이 파일을 지울 수 있다.
 */
class WebAuthCallbackActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val url = intent?.data
        val scheme = url?.scheme

        // ① 대기 호출에 결과 전달 — 반드시 ② 보다 먼저 (Dart resume observer 경합)
        if (scheme != null) {
            FlutterWebAuth2Plugin.callbacks.remove(scheme)?.success(url.toString())
        }

        // ② MainActivity 기존 task 전면 복귀 — 그 위 인증 관리 Activity · 브라우저 tab 제거
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            ),
        )

        // ③ relay 자신은 남지 않는다
        finish()
    }
}
