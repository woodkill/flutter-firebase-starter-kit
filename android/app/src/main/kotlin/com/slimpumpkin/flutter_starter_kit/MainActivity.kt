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
     * 자기 프로세스의 Activity 생성만 받는다 — 타 앱 개입은 구조적으로 불가
     * (T-16.4-12).
     */
    private val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
            if (activity.javaClass.name == NID_CUSTOM_TAB) {
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
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
