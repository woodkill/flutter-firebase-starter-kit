package com.slimpumpkin.flutter_starter_kit

// Phase 13 — see ROADMAP.md (Naver SDK 5.4.0+ Fragment 기반 BottomSheet 호환).
// FlutterActivity → FlutterFragmentActivity 마이그레이션 (Pitfall 10).
// Phase 16.4 — see ROADMAP.md (레버 2 — 커스텀탭 Activity 생성 계수 · D-19)
import android.app.Activity
import android.app.Application
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 킷의 유일한 Android 호스트 Activity.
 *
 * Phase 16.4 D-19: Naver 로그인 중 커스텀탭 Activity 가 **같은 프로세스**에서
 * 다시 열리는지(재개방)를 세어 Dart 로 정수 하나만 노출한다. 콜백 intent 의
 * extras · code · state · URI 는 읽지도 넘기지도 않는다 (T-16.4-11) — OAuth
 * 완결은 전적으로 NAVER SDK 에 둔다.
 */
class MainActivity : FlutterFragmentActivity() {

    companion object {
        /** Dart `NaverCustomTabProbe._channel` 과 **같은 문자열**이어야 한다. */
        private const val CHANNEL =
            "com.slimpumpkin.flutter_starter_kit/naver_custom_tab"

        /** 계수 대상 — SDK 커스텀탭 Activity 의 완전 수식 클래스 이름. */
        private const val NID_CUSTOM_TAB =
            "com.navercorp.nid.oauth.activity.NidOAuthCustomTabActivity"
    }

    /** 마지막 `resetCount` 이후 생성된 커스텀탭 Activity 수. */
    private var customTabCreateCount = 0

    /**
     * 자기 프로세스의 Activity 생성만 **관측**한다. 채널로 나가는 것은 정수
     * 하나뿐이고 콜백 intent 의 extras · code · state · URI 는 읽지 않는다
     * (T-16.4-11) — 데이터 유출 · 권한 상승 경로는 없다.
     *
     * 다만 「자기 프로세스의 생성만 관측한다」 가 「외부가 그 생성을 유발할 수
     * 없다」 를 함의하지는 않는다. 계수 대상 Activity 는 병합 manifest 상
     * `exported="true"` + `BROWSABLE` + `naver3rdpartylogin://authorize/`
     * intent-filter 로 선언돼 있어(AAR 선언, 실측: devDebug merged manifest),
     * 임의의 설치 앱 · 웹페이지가 그 scheme 을 던지면 킷 프로세스 안에
     * 인스턴스가 생성되고 계수가 올라간다. 그 경우 「재개방」 오탐이 나지만
     * 영향은 **정상 취소가 오류 배너로 보이는 것까지**로 한정된다.
     *
     * 아래 `savedInstanceState == null` 가드는 이 경로를 막지 못한다 — 외부
     * 기동도 fresh launch 다.
     *
     * 계수 창(window)은 **이미** Dart 가 `resetCount()` → `_login()` →
     * `readCount()` 로 좁혀 놓았다 (`naver_sdk_client.dart:399` · `:401` ·
     * `:413`, 그 순서는 `T-16.4-NAVER-DISCRIM-03` 이 잠근다). 따라서 창을 더
     * 좁히는 호스트 측 변경으로는 얻는 것이 없다 — 남는 노출은 **그 창 안에서의
     * 외부 기동**이라 창의 폭과 무관하다. 없애려면 기동 **주체**(호출 intent 의
     * 출처)를 가려야 하는데, 그것은 SDK Activity 의 intent 를 읽는 일이라
     * T-16.4-11 prohibition 과 정면 충돌한다. 그래서 오탐 가능성을 감수하는
     * 것이 이 phase 의 선택이다 (16.4 code review IN-06 — 종전 주석은 존재하지
     * 않는 처방을 「별건」 으로 예약해 두고 있었다).
     */
    private val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
            // savedInstanceState != null 은 구성 변경 · 프로세스 복원으로 인한
            // **재생성**이다. 재개방(새 인스턴스 기동)이 아니므로 세지 않는다.
            // NidOAuthCustomTabActivity 의 configChanges 에는 uiMode · locale ·
            // fontScale · density 가 없어 다크 모드 전환 · 폰트 크기 변경만으로도
            // 파괴·재생성되며(AAR 선언), 그것을 세면 정상 취소가 재개방 오탐으로
            // 뒤집혀 D-45(취소 silent) 가 깨진다. RESEARCH §1 ② 의 실제 재개방
            // 경로는 intent 기동이라 savedInstanceState == null 이므로 검출력
            // 손실은 없다 (16.4 code review WR-02).
            if (savedInstanceState == null && activity.javaClass.name == NID_CUSTOM_TAB) {
                customTabCreateCount++
            }
        }

        override fun onActivityStarted(activity: Activity) = Unit

        override fun onActivityResumed(activity: Activity) = Unit

        override fun onActivityPaused(activity: Activity) = Unit

        override fun onActivityStopped(activity: Activity) = Unit

        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

        override fun onActivityDestroyed(activity: Activity) = Unit
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        application.registerActivityLifecycleCallbacks(lifecycleCallbacks)
    }

    override fun onDestroy() {
        application.unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
        super.onDestroy()
    }

    /**
     * 계수 채널 — 핸들러 람다가 `customTabCreateCount` 를 통해 이 Activity 를
     * 캡처하므로 [cleanUpFlutterEngine] 에서 반드시 떼어 준다 (16.4 code
     * review IN-04). 현재는 엔진이 Activity 와 수명을 같이 해 실해가 없지만,
     * 스타터 킷이 흔히 도입하는 `FlutterEngineCache` 가 들어오면 파괴된
     * Activity 의 낡은 계수를 계속 읽는 **조용한** 실패가 된다.
     */
    private var customTabChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        customTabChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "resetCount" -> {
                            customTabCreateCount = 0
                            result.success(null)
                        }
                        "getCount" -> result.success(customTabCreateCount)
                        else -> result.notImplemented()
                    }
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        customTabChannel?.setMethodCallHandler(null)
        customTabChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
