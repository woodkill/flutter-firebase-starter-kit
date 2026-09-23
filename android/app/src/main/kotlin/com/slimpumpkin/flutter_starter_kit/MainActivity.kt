package com.slimpumpkin.flutter_starter_kit

// Phase 13 — see ROADMAP.md (Naver SDK 5.4.0+ Fragment 기반 BottomSheet 호환).
// FlutterActivity → FlutterFragmentActivity 마이그레이션 (Pitfall 10).
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

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
