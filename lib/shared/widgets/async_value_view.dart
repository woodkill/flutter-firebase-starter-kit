import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../core/error/app_exception.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/theme/theme_extensions.dart';
import 'error_banner.dart';

/// [AsyncValue] 의 loading · error · data 3상태를 그리는 공용 위젯
/// (Phase 17 D-23).
///
/// - [data] 는 필수, [loading] · [error] builder 는 선택 — 생략하면 기본값을
///   그린다.
/// - 기본 loading: `Padding(all: lg) › Center › CircularProgressIndicator`.
/// - 기본 error: [ErrorBanner] (비-[AppException] 은 [UnknownException] 으로
///   감싼다) + [onRetry] 가 있으면 「재시도」 버튼.
/// - 값이 있는 상태의 재로딩 중에는 [data] 를 계속 그린다
///   (`skipLoadingOnReload`).
///
/// 좌우 padding 은 호출부 책임이다.
class AsyncValueView<T> extends StatelessWidget {
  /// [AsyncValueView] 를 생성한다.
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.loading,
    this.error,
    this.onRetry,
  });

  /// 그릴 비동기 상태.
  final AsyncValue<T> value;

  /// data 상태 builder.
  final Widget Function(T data) data;

  /// loading 상태 builder. null 이면 기본 진행 표시를 그린다.
  final Widget Function()? loading;

  /// error 상태 builder. null 이면 기본 오류 배너 (+ 재시도) 를 그린다.
  final Widget Function(Object error, StackTrace stackTrace)? error;

  /// 기본 error 표시의 「재시도」 콜백. null 이면 버튼을 그리지 않는다.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnReload: true,
      data: data,
      loading: loading ?? () => const _DefaultLoadingView(),
      error:
          error ??
          (error, stackTrace) =>
              _DefaultErrorView(error: error, onRetry: onRetry),
    );
  }
}

/// [AsyncValueView] loading 기본값 — 가운데 진행 표시.
class _DefaultLoadingView extends StatelessWidget {
  const _DefaultLoadingView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.appSpacing.lg),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// [AsyncValueView] error 기본값 — 오류 배너 + 선택적 「재시도」.
class _DefaultErrorView extends StatelessWidget {
  const _DefaultErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final err = error;
    final exception = err is AppException ? err : UnknownException(cause: err);
    final retry = onRetry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ErrorBanner(exception: exception),
        Gap(context.appSpacing.sm),
        if (retry != null)
          TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.commonRetry),
          ),
      ],
    );
  }
}
