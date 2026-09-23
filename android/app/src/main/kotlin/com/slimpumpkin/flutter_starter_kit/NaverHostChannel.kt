package com.slimpumpkin.flutter_starter_kit

// Phase 16.5 — see ROADMAP.md (D-03 · D-23 — NAVER 앱 설치 판정 호스트 채널)
import android.content.Context
import com.navercorp.nid.core.util.NidApplicationUtil
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * NAVER 앱 설치 여부만 Dart 로 넘기는 호스트 채널 (Phase 16.5 D-23).
 *
 * 판정은 NAVER SDK 자신이 쓰는 `NidApplicationUtil.isExistNaverApp` 에 위임한다 —
 * SDK 가 1-tap(app-to-app) 을 시도하는 기준과 킷의 라우팅 기준이 같아야
 * 「설치됐다고 판정했는데 SDK 는 커스텀탭으로 간다」 는 어긋남이 생기지 않는다.
 *
 * 채널을 건너는 것은 Boolean 하나뿐이다 — intent · code · state · URI 는 읽지도
 * 넘기지도 않는다. 실패(채널 부재 · 예외)는 Dart 쪽이 `false`(= 킷 웹 경로) 로 접고,
 * 판정 호출 자체의 Throwable(LinkageError 포함)은 여기서 `false` 로 접는다.
 *
 * `MainActivity.configureFlutterEngine` 이 [attach] 하고 `cleanUpFlutterEngine` 이
 * [detach] 한다 (Phase 16.4 IN-04 — 엔진 해제 뒤 핸들러가 Activity 를 붙잡지 않게).
 */
class NaverHostChannel(private val appContext: Context) {
    private var channel: MethodChannel? = null

    /** 채널을 [messenger] 에 붙이고 설치 판정 메서드 핸들러를 등록한다. */
    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isNaverAppInstalled" -> {
                        // 16.5 review IN-03 — SDK 는 compileOnly 로 컴파일하고 런타임
                        // AAR 은 플러그인이 공급한다. 버전이 어긋나면
                        // NoClassDefFoundError · NoSuchMethodError(LinkageError =
                        // Error) 가 나는데, MethodChannel 은 RuntimeException 만
                        // error envelope 로 바꾸므로 그대로 두면 앱이 죽는다.
                        // Throwable 전부를 D-02 안전값 false(= 킷 웹 경로) 로 접는다.
                        val installed = try {
                            NidApplicationUtil.isExistNaverApp(appContext)
                        } catch (t: Throwable) {
                            false
                        }
                        result.success(installed)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** 핸들러를 떼고 채널 참조를 비운다 (16.4 IN-04 교훈 이식). */
    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    companion object {
        /** Dart `kNaverHostChannelName` 과 **같은 문자열**이어야 한다 (T-16.5-NATIVE 가 잠근다). */
        const val CHANNEL = "com.slimpumpkin.flutter_starter_kit/naver_host"
    }
}
