package com.slimpumpkin.flutter_starter_kit

// Phase 13 — see ROADMAP.md (Naver SDK 5.4.0+ Fragment 기반 BottomSheet 호환).
// FlutterActivity → FlutterFragmentActivity 마이그레이션 (Pitfall 10).
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import com.linecorp.linesdk.auth.internal.LineAuthenticationActivity

/**
 * 킷의 유일한 Android 호스트 Activity.
 *
 * Phase 16.5 D-23: NAVER 앱 설치 판정 채널([NaverHostChannel]) 을 엔진 수명에 맞춰
 * 등록 · 해제만 한다. 판정 로직은 채널 클래스에 있다.
 */
class MainActivity : FlutterFragmentActivity() {
    private var naverHostChannel: NaverHostChannel? = null

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
 * LINE 로그인 콜백(`lineauth` scheme)을 받아 앱 task 의 대기 인증 Activity 에 넘기는 킷 소유
 * relay Activity.
 *
 * **왜** — SDK 콜백 Activity 는 대기 인증 Activity 를 NEW_TASK|CLEAR_TOP 으로 다시 띄운다.
 * 앱 task 를 찾아 그 위의 브라우저 탭을 걷고 대기 인증 Activity 의 onNewIntent 로 결과를
 * 보내는 설계다. 그런데 킷의 MainActivity 는 빈 taskAffinity 라 재기동이 앱 task 를 찾지
 * 못하고 새 task 로 빠진다. 그래서 LINE 앱 경로에서는 LINE 메인 화면이 앞에 남고, 웹
 * 경로에서는 브라우저 탭이 앱 위에 남아 사용자가 직접 돌아오거나 탭을 닫아야 한다.
 *
 * **무엇** —
 * 1. 콜백 intent 의 data 와 로그인을 기다리는 앱 task 를 확인한다.
 * 2. [ActivityManager.AppTask.startActivity] 로 앱 task 안에서 대기 인증 Activity 를
 *    CLEAR_TOP|SINGLE_TOP 으로 부른다. 대기 인증 Activity 위의 탭이 걷히고 앱 task 가 앞에
 *    오며, onNewIntent 가 결과를 처리한다.
 * 3. finish 한다.
 *
 * **왜 SDK 콜백 Activity 를 manifest 에서 제거하는가** — 재기동을 남겨 두면 SDK 가 결과를
 * static 에 넣는데 onNewIntent 경로는 그것을 지우지 않는다. 그러면 다음 로그인을 취소할 때
 * 낡은 결과가 내부 오류로 나온다. 수신자가 둘이면 chooser 도 뜬다.
 *
 * **왜 [ActivityManager.AppTask.startActivity] 인가** — 앱 task 를 앞세우기만 하면 그 위의
 * 탭이 걷히지 않고, 대기 인증 Activity 의 finishActivity 는 삼성 인터넷 탭을 닫지 못한다.
 * 이 호출은 지정한 task 안에서 Activity 를 시작하므로 빈 taskAffinity 의 영향을 받지 않는다.
 *
 * **CLEAR_TOP 의 대상** — 대기 인증 Activity 는 singleTop 이라 지워지지 않고 그 위만 걷힌다.
 * MainActivity 를 CLEAR_TOP 으로 부르면 대기 인증 Activity 가 지워져 결과를 잃는다. 그래서
 * MainActivity 는 task 판정의 비교에만 쓴다.
 *
 * **왜 data 만 넘기는가** — 이 Activity 는 exported 라 누구나 띄울 수 있다. 들어온 intent 를
 * 그대로 넘기면 비공개 인증 Activity 로 임의의 값이 들어간다. data 만 새 명시 intent 에
 * 싣는다. 위조 data 는 SDK 의 state 검사에서 실패로 끝난다.
 *
 * **대기 Activity 판정의 한계** — base 가 MainActivity 이고 Activity 가 2개 이상이면 대기
 * 중으로 본다. 인증 Activity 가 아닌 다른 Activity 가 MainActivity 위에 있으면 인증 Activity
 * 가 새로 떠서 결과만 저장하고 끝난다. SDK 콜백 Activity 때도 있던 표면이다.
 *
 * **외부 기동 · 로그인 없음** — data 가 없거나 대기 중인 task 가 없으면 아무것도 하지 않고
 * 끝난다.
 *
 * **프로세스가 죽었다 살아난 경우** — 대기 인증 Activity 가 복원된 뒤 결과를 받아도 기다리는
 * Dart 호출이 없어 그 로그인은 사라진다. 이전과 같은 결과다.
 *
 * **로그 없음** — 콜백 data 에 code · state 가 실린다. 어떤 로그 호출도 두지 않는다.
 *
 * **왜 catch 가 이것 하나인가** — 조회와 시작 사이에 task 가 사라지면 두 호출 모두
 * IllegalArgumentException 을 던진다. 그 밖의 예외는 숨길 이유가 없다.
 *
 * **왜 MainActivity.kt 안인가** — 앱 패키지 경로를 바꾼 저장소에서 킷 업데이트를 merge 하면,
 * 패키지 디렉터리에 새로 생긴 Kotlin 파일은 위치 충돌로 멈추고 package 줄이 옛 값으로 남는다.
 * 기존 파일의 수정은 git 이 옮긴 파일로 자동 병합된다.
 *
 * **유지보수** — LINE SDK 를 올릴 때 대기 인증 Activity 의 onNewIntent 분기와 manifest 의
 * 제거 대상 이름을 확인한다. 인증 Activity 이름이 바뀌면 이 파일의 빌드가 실패한다. 제거 대상
 * 이름이 바뀌면 merged manifest 에 수신자가 2개가 되므로 시험과 함께 고친다. SDK 가 재기동의
 * task 검색을 고치면 이 class 와 manifest 의 두 선언, gradle 의 compileOnly 를 지운다.
 */
class LineAuthCallbackActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.data?.let { data -> deliverToWaitingLogin(data) }
        finish()
    }

    private fun deliverToWaitingLogin(data: Uri) {
        try {
            val appTask = getSystemService(ActivityManager::class.java)
                ?.appTasks
                ?.firstOrNull { isLoginWaiting(it.taskInfo) }
                ?: return
            appTask.startActivity(
                this,
                Intent(this, LineAuthenticationActivity::class.java)
                    .setData(data)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                null,
            )
        } catch (ignored: IllegalArgumentException) {
            // task 가 조회와 시작 사이에 사라진 경우다 — 넘길 곳이 없으므로 할 일이 없다.
        }
    }

    private fun isLoginWaiting(info: ActivityManager.RecentTaskInfo): Boolean =
        info.baseActivity?.className == MainActivity::class.java.name && info.numActivities >= 2
}
