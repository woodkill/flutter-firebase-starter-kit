import 'dart:io';

import 'file_mode.dart';
import 'redactor.dart';

/// 위저드 실행 기록 — 명령 · 출력 · 판정을 종류별 줄로 남긴다.
///
/// 종류: `out`(화면 출력) · `in`(사용자 답) · `cmd`(실행한 명령) · `exit`(종료
/// 코드) · `stdout` · `stderr`(캡처한 출력) · `rest`(REST 요청 · 응답) ·
/// `check`(단계 검사 판정). 구현은 쓰기 전에 비밀 값을 가린다.
abstract interface class LogSink {
  /// [kind] 종류의 [text] 를 남긴다 — 여러 줄이면 줄마다 남긴다.
  void write(String kind, String text);

  /// 기록을 닫는다 — 닫은 뒤의 [write] 는 무시한다.
  Future<void> close();
}

/// [kind] 와 [text] 를 기록 줄 목록(`[<kind>] <text>`)으로 바꾼다.
///
/// [text] 의 줄마다 한 줄을 만들고, 끝의 줄바꿈 하나는 빈 줄로 세지 않는다.
List<String> formatLogLines(String kind, String text) {
  final String body = text.endsWith('\n')
      ? text.substring(0, text.length - 1)
      : text;
  return body
      .split('\n')
      .map((String line) => '[$kind] $line')
      .toList(growable: false);
}

/// 저장소 루트의 `.setup/logs/` 에 실행마다 파일 하나를 남기는 기록.
///
/// 디렉터리는 소유자만 열 수 있게(0700), 파일은 소유자만 읽고 쓸 수 있게(0600)
/// 만든다. 위치는 `build/` · `.dart_tool/` 밖이라 정리 명령에 지워지지 않고,
/// `.gitignore` 의 `/.setup/` 로 저장소에 들어가지 않는다.
final class FileLogSink implements LogSink {
  FileLogSink._(this.path, this._file, this._redactor);

  /// 기록 디렉터리의 저장소 루트 기준 경로.
  static const String logDirectory = '.setup/logs';

  /// 같은 초에 이미 파일이 있을 때 이름 뒤에 붙여 볼 번호의 상한.
  static const int maxNameAttempts = 100;

  /// 기록 파일의 절대 경로.
  final String path;

  final RandomAccessFile _file;
  final Redactor _redactor;
  bool _isClosed = false;

  /// [projectRoot] 아래에 [now] 시각 이름(`setup-<yyyyMMdd-HHmmss>.log`)의 새
  /// 기록 파일을 연다.
  ///
  /// 같은 이름의 파일이 이미 있으면 덮어쓰지 않고 `-2` · `-3` … 을 붙인 이름을
  /// 쓴다. 디렉터리 · 파일을 만들거나 권한을 좁히지 못하면
  /// [FileSystemException] 을 던진다.
  static Future<FileLogSink> open({
    required String projectRoot,
    required DateTime now,
    required Redactor redactor,
  }) async {
    final setupDir = Directory('$projectRoot/.setup');
    final logDir = Directory('$projectRoot/$logDirectory');
    await logDir.create(recursive: true);
    restrictFileMode(setupDir.path, ownerOnlyDirectoryMode);
    restrictFileMode(logDir.path, ownerOnlyDirectoryMode);

    final String stamp = formatLogTimestamp(now);
    for (var attempt = 1; attempt <= maxNameAttempts; attempt++) {
      final suffix = attempt == 1 ? '' : '-$attempt';
      final file = File('${logDir.path}/setup-$stamp$suffix.log');
      try {
        // exclusive — 같은 이름의 파일이 있으면 실패하므로 기존 기록을 덮지 않는다.
        file.createSync(exclusive: true);
      } on FileSystemException {
        if (file.existsSync()) continue;
        rethrow;
      }
      restrictFileMode(file.path, ownerOnlyFileMode);
      final RandomAccessFile handle = file.openSync(mode: FileMode.append);
      return FileLogSink._(file.path, handle, redactor);
    }
    throw FileSystemException('같은 시각의 기록 파일이 너무 많습니다', logDir.path);
  }

  /// [time] 을 기록 파일 이름의 시각 부분(`yyyyMMdd-HHmmss`)으로 바꾼다.
  static String formatLogTimestamp(DateTime time) {
    String pad(int value, int width) => value.toString().padLeft(width, '0');
    return '${pad(time.year, 4)}${pad(time.month, 2)}${pad(time.day, 2)}-'
        '${pad(time.hour, 2)}${pad(time.minute, 2)}${pad(time.second, 2)}';
  }

  @override
  void write(String kind, String text) {
    if (_isClosed) return;
    final String redacted = _redactor.apply(text);
    final buffer = StringBuffer();
    for (final String line in formatLogLines(kind, redacted)) {
      buffer.writeln(line);
    }
    _file.writeStringSync(buffer.toString());
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _file.close();
  }
}
