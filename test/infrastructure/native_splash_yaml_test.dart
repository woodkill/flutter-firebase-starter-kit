import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flutter_native_splash.yaml 존재 + 필수 키 포함', () {
    final file = File('flutter_native_splash.yaml');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('flutter_native_splash:'));
    expect(content, contains('image: assets/images/splash/logo.png'));
    expect(content, contains('android_12:'));
  });
}
