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
 *    (upstream 콜백 Activity 와 같은 전달 경로). 대기 호출을 실제로 꺼내 전달했는지를
 *    `delivered` 로 남긴다 (remove 결과에서 파생).
 * 2. MainActivity 의 기존 task 를 NEW_TASK|SINGLE_TOP 으로 전면 복귀시키고,
 *    **`delivered` 일 때만** CLEAR_TOP 을 더한다 (전달 시 0x34000000 · 미전달 시
 *    0x30000000). NEW_TASK 가 task 검색을 켜고 MainActivity 가 root 인 main task 는
 *    component 일치로 찾아진다(affinity 가 비어 있어도 무관). 전달 시 CLEAR_TOP 이 그
 *    위의 원본 인증 관리 Activity 와 브라우저 tab 을 걷고, SINGLE_TOP + manifest
 *    singleTop 이 MainActivity 재생성을 막아 Flutter 엔진과 로그인 상태를 유지한다.
 * 3. finish 한다.
 *
 * **CLEAR_TOP 을 조건부로 두는 이유 (16.5 review 2회차 IN-01)** — relay 는
 * exported + BROWSABLE 이라 누구나 콜백 scheme VIEW intent 로 띄울 수 있다. CLEAR_TOP 을
 * 무조건 걸면 로그인이 진행 중이 아닐 때도 외부 intent 하나로 MainActivity 위의
 * Activity(Kakao 인증 Activity · Firebase GenericIdpActivity · NAVER SDK 1-tap bridge ·
 * 이미지 picker 등)를 전부 finish 시킬 수 있다 — upstream 콜백 Activity 에는 없던 표면이다.
 * 그래서 대기 호출이 없으면(외부 기동 · 중복 콜백 · cold start) 전면 복귀만 한다.
 * **대가:** process death 뒤 도착한 콜백(대기 호출 없음 · 브라우저 tab 이 main task
 * top)은 더 이상 tab 을 걷지 못한다. 그 로그인은 어차피 Dart 쪽에 기다리는 호출이 없어
 * 사라지므로(D-45 취소와 같은 결과), 사용자가 tab 을 직접 닫는 한 단계가 늘 뿐이다.
 *
 * **계약 (16.5 review 2회차 IN-03)** — 대기 호출은 main thread 에서 **동기로 map 에서
 * 꺼낸 뒤** success 한다(`callbacks.remove(…)?.let { success }` 한 식). 그래서 이후
 * MainActivity resume 이 부르는 Dart resume observer 의 cleanUpDanglingCalls(map 에 남은
 * 대기 호출을 CANCELED 로 접는다) · 늦게 온 Auth Tab handleAuthResult 가 빈 map 을 보고,
 * CANCELED 경합 · double reply 가 구조적으로 없다. startActivity 는 비동기 IPC 이고
 * MainActivity onNewIntent/onResume 은 같은 main looper 에서 이 onCreate 가 반환한 뒤에야
 * 돈다 — 따라서 success 를 startActivity 보다 **소스상 먼저** 두는 것은 보호 장치가
 * 아니라 가독성 규칙이다 (T-16.5-NATIVE-09 가 한 식 구조를 잠근다).
 *
 * **Chrome Auth Tab 경로는 이 Activity 를 기동하지 않는다** — 결과가 ActivityResult 로
 * 돌아오므로 이 변경의 영향이 없다 (plan 06 UAT 실측 콜백 Activity START 0).
 *
 * **로그 없음** — 콜백 URL 에 code · state 가 실린다 (C-01). 어떤 로그 호출도 두지 않는다.
 *
 * data 가 없거나 대기 호출이 없는 intent 는 전달을 건너뛰되 전면 복귀는 한다(CLEAR_TOP
 * 없이) — 사용자가 tab 에 갇히지 않게 한다 (AppAuth RedirectUriReceiverActivity 선례).
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

        // ① 대기 호출을 main thread 에서 동기로 map 에서 꺼내 success 로 전달 — 이후
        //    cleanUpDanglingCalls · 늦은 handleAuthResult 는 빈 map 을 본다 (KDoc 계약).
        //    delivered = 대기 호출을 실제로 꺼내 전달했는지 (remove 결과에서 파생)
        val delivered = scheme != null &&
            FlutterWebAuth2Plugin.callbacks.remove(scheme)?.let { pending ->
                pending.success(url.toString())
                true
            } == true

        // ② MainActivity 기존 task 전면 복귀 — 전달했을 때만 CLEAR_TOP 으로 그 위
        //    인증 관리 Activity · 브라우저 tab 제거 (미전달 = 외부 기동은 걷지 않는다)
        val flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_SINGLE_TOP or
            (if (delivered) Intent.FLAG_ACTIVITY_CLEAR_TOP else 0)
        startActivity(Intent(this, MainActivity::class.java).addFlags(flags))

        // ③ relay 자신은 남지 않는다
        finish()
    }
}
