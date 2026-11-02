package com.slimpumpkin.flutter_starter_kit

// Phase 13 — see ROADMAP.md (Naver SDK 5.4.0+ Fragment 기반 BottomSheet 호환).
// FlutterActivity → FlutterFragmentActivity 마이그레이션 (Pitfall 10).
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.linecorp.linesdk.auth.internal.LineAuthenticationActivity
import com.linecorp.linesdk.auth.internal.LineAuthenticationCallbackActivity

/**
 * 킷의 유일한 Android 호스트 Activity.
 *
 * Phase 16.5 D-23: NAVER 앱 설치 판정 채널([NaverHostChannel]) 을 엔진 수명에 맞춰
 * 등록 · 해제만 한다. 판정 로직은 채널 클래스에 있다.
 *
 * LINE 로그인 콜백 뒤 앱 task 를 앞으로 가져오는 콜백([LineAuthTaskReturnCallbacks])도
 * 이 Activity 의 수명에 맞춰 등록 · 해제만 한다. 판단 로직은 그 클래스에 있다.
 */
class MainActivity : FlutterFragmentActivity() {
    private var naverHostChannel: NaverHostChannel? = null
    private val lineAuthTaskReturnCallbacks = LineAuthTaskReturnCallbacks(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        application.registerActivityLifecycleCallbacks(lineAuthTaskReturnCallbacks)
    }

    override fun onDestroy() {
        application.unregisterActivityLifecycleCallbacks(lineAuthTaskReturnCallbacks)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Phase 16.5 — see ROADMAP.md (D-23 — NAVER 앱 설치 판정 채널 등록 1줄 · 해제 1줄)
        naverHostChannel = NaverHostChannel(applicationContext).also {
            it.attach(flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        naverHostChannel?.detach()
        naverHostChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

/**
 * LINE 로그인 결과가 앱에 넘어간 직후 앱 task 를 앞으로 가져오는 수명주기 콜백.
 *
 * **왜** — LINE 앱이 「허용」 뒤 띄우는 SDK 콜백 Activity
 * ([LineAuthenticationCallbackActivity])는 LINE 앱의 task 에 열리고, 자신을 끝내기 전에
 * 인증 Activity([LineAuthenticationActivity])를 NEW_TASK|CLEAR_TOP 으로 다시 띄운다.
 * 킷의 MainActivity 는 빈 taskAffinity 라 다시 뜬 인증 Activity 는 앱 task 를 찾지 못하고
 * 늘 새 task 에 떨어진다. 그 Activity 는 결과를 SDK 컨트롤러에 저장(setIntent)한 뒤 바로
 * finish 하므로, 앱 task 를 앞으로 가져오는 주체가 없다 — LINE task 가 최근 앱에 남아
 * 있으면 그 메인 화면이 앞에 보이고 사용자가 직접 앱으로 돌아가야 한다. 로그인 자체는
 * 앱 task 의 대기 인증 Activity 가 resume 될 때 끝난다.
 *
 * **무엇** —
 * 1. 콜백 Activity 가 생성되면 표시만 한다(`hasPendingCallback`).
 * 2. 표시가 있고 인증 Activity 가 앱 task(`host.taskId`)와 **다른** task 에 생성되면
 *    표시를 지우고 main looper 에 작업을 post 한다.
 * 3. post 된 작업이 앱 task 를 `ActivityManager.AppTask.moveToFront()` 로 앞세운다.
 *    `onActivityCreated` 는 그 Activity 의 `super.onCreate` 안에서 불리므로, post 된
 *    작업은 그 `onCreate`(결과 저장 · finish)가 끝난 뒤에 돈다.
 *
 * **왜 콜백 Activity 생성 순간에 앞세우지 않는가** — 그 시점엔 다시 띄울 인증 Activity 가
 * 아직 만들어지지 않았다. 시스템은 새 Activity 를 앞 Activity 의 pause 뒤에 만들고, 그 전에
 * 앱 task 가 앞에 서면 보이지 않는 새 task 의 Activity 생성이 미뤄질 수 있다. 그러면 결과
 * 저장이 돌지 않고, 앱 task 의 대기 인증 Activity 가 resume 에서 결과 없음을 보고 취소로
 * 끝난다. 결과 저장 뒤에 앞세우면 그 경합이 없다.
 *
 * **왜 MainActivity.kt 안의 private class 인가** — 앱 패키지 경로를 바꾼 저장소에서 킷
 * 업데이트를 merge 하면, 패키지 디렉터리에 새로 생긴 Kotlin 파일은 위치 충돌로 멈추고
 * package 줄이 옛 값으로 남는다. 기존 파일의 수정은 git 이 옮긴 파일로 자동 병합된다.
 *
 * **하지 않는 것** —
 * - MainActivity 의 빈 taskAffinity 를 지우지 않는다 — StrandHogg 방어다.
 * - manifest 에서 SDK Activity 선언을 tools:replace 로 덮지 않는다.
 * - CLEAR_TOP 으로 앱 task 를 부르지 않는다 — 대기 인증 Activity 가 지워져 결과를 잃는다.
 * - MainActivity 를 새로 띄우지 않는다 — 앱 task top 이 대기 인증 Activity 라 singleTop 이
 *   걸리지 않아 MainActivity 가 하나 더 생기고 Flutter 엔진이 2개가 된다.
 *
 * **경합** — SDK 는 대기 인증 Activity 가 결과 없이 resume 되면 취소를 1000ms
 * (`CANCEL_DELAY_MILLIS`) 미룬다. 앞세우기는 결과 저장이 끝난 뒤라 그 지연과 겹치지 않는다.
 *
 * **백그라운드 Activity 시작 제한** — 앞세우는 순간 전경 task 의 top 은 이 앱의 Activity 라
 * 제한 대상이 아니다. 시스템이 막으면 결과는 시스템 쪽 무음이고 지금까지의 동작(사용자가
 * 직접 돌아옴)과 같다.
 *
 * **로그 없음 · try/catch 없음** — 콜백 intent data 에 code · state 가 실려 어떤 로그 호출도
 * 두지 않는다. task 조회는 main thread 에서 이어져 조회 중 새 task 가 사라질 수 없고, 앞세우기
 * 실패는 시스템 쪽 무음이다. 대신 host 가 이미 파괴됐거나 ActivityManager 가 없으면 돌아간다.
 *
 * **프로세스가 죽었다 살아난 경우** — MainActivity 가 아직 없으면 등록도 없어 지금까지의
 * 동작과 같다.
 *
 * **유지보수** — LINE SDK 를 올릴 때 두 Activity 클래스 이름과 콜백 Activity 의 재기동
 * 플래그를 확인한다. 이름이 바뀌면 이 파일의 빌드가 실패한다(조용한 실패 아님). 앱 gradle 의
 * compileOnly 버전은 플러그인이 링크하는 버전과 같아야 하고 시험이 잠근다. SDK 가 재기동
 * 대상 task 검색을 고치면 이 클래스와 MainActivity 의 등록 · 해제를 지운다.
 */
private class LineAuthTaskReturnCallbacks(private val host: Activity) : Application.ActivityLifecycleCallbacks {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var hasPendingCallback = false

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
        if (activity is LineAuthenticationCallbackActivity) {
            hasPendingCallback = true
            return
        }
        if (hasPendingCallback && activity is LineAuthenticationActivity && activity.taskId != host.taskId) {
            hasPendingCallback = false
            mainHandler.post { moveHostTaskToFront() }
        }
    }

    private fun moveHostTaskToFront() {
        if (host.isDestroyed) {
            return
        }
        val activityManager = host.getSystemService(ActivityManager::class.java) ?: return
        activityManager.appTasks.firstOrNull { taskIdOf(it.taskInfo) == host.taskId }?.moveToFront()
    }

    private fun taskIdOf(info: ActivityManager.RecentTaskInfo): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            info.taskId
        } else {
            @Suppress("DEPRECATION")
            info.id
        }

    override fun onActivityStarted(activity: Activity) {}

    override fun onActivityResumed(activity: Activity) {}

    override fun onActivityPaused(activity: Activity) {}

    override fun onActivityStopped(activity: Activity) {}

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}

    override fun onActivityDestroyed(activity: Activity) {}
}
