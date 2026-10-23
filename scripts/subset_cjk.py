#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ko/ja golden 용 CJK 시험 글꼴 subset 을 만든다.

실행 (저장소 루트, fonttools 필요 — 임시 venv 권장):
    uv venv /tmp/ftenv && uv pip install --python /tmp/ftenv/bin/python fonttools==4.66.0
    /tmp/ftenv/bin/python -X utf8 scripts/subset_cjk.py "<NotoSansCJK-Regular.ttc 경로>"

원본 = AOSP Android 시스템 CJK fallback 폰트 `NotoSansCJK-Regular.ttc` v2.004
(Android Studio 2025.3 layoutlib `plugins/design-tools/resources/layoutlib/data/fonts/`,
sha256 3e7e5afaac2c6d872592d76abedac03a51c6f0fc42d11e311ff2816a6c368afe).
face index = AOSP fonts.xml 과 같다 — ko → 1 (Noto Sans CJK KR), ja → 0 (JP).

출력은 결정적이다 (recalcTimestamp=False) — 같은 원본 · fonttools 버전이면 byte 동일.
절차 · 확인 방법은 docs/maintainer/brand-assets.md 「시험 글꼴 subset 다시 만들기」 에 있다.
"""
import hashlib
import json
import os
import sys

try:
    from fontTools import subset
    from fontTools.ttLib import TTFont
except ModuleNotFoundError:
    # venv 밖(시스템 python3 · `./scripts/subset_cjk.py` 직접 실행)이면 traceback 대신 안내로 끝낸다
    sys.exit("fonttools 가 없다 — 머리 주석의 venv 명령으로 설치한 뒤 그 python 으로 돌린다.")

SRC_SHA256 = "3e7e5afaac2c6d872592d76abedac03a51c6f0fc42d11e311ff2816a6c368afe"
L10N = "lib/l10n"
OUT = "assets/test_fonts"

# ARB 와 별도로 subset 에 늘 넣는 golden 문자열 · fixture 이름. ARB 에 새 한자가
# 들어오면 이 스크립트를 다시 돌린다 (없는 글자는 golden 에서 tofu 로 드러난다).
FIXTURE_EXTRA = "가입 수단 연결된 계정 없음 登録方法 連携済みアカウント なし 홍길동 山田太郎"

ASCII = set(range(0x20, 0x7F))
HANGUL = set(range(0xAC00, 0xD7A4)) | set(range(0x3130, 0x3190))  # 완성형 전 음절 + 호환 자모
KANA = set(range(0x3000, 0x3100)) | set(range(0xFF00, 0xFFF0))  # CJK 기호 · 히라가나 · 가타카나 · 전각


def arb_path(locale):
    """[locale] 의 ARB 파일 경로."""
    return f"{L10N}/app_{locale}.arb"


def arb_codepoints(locale):
    """ARB 값 문자열(메타 `@` 키 제외)에 쓰인 code point 집합."""
    with open(arb_path(locale), encoding="utf-8") as fp:
        data = json.load(fp)
    return {ord(c) for k, v in data.items() if not k.startswith("@") and isinstance(v, str) for c in v}


def build(src, index, out, unicodes):
    """TTC 의 [index] face 를 [unicodes] 로 subset 해 [out] 에 저장한다."""
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    font = TTFont(src, fontNumber=index, recalcTimestamp=False)
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=sorted(unicodes))
    sub.subset(font)
    font.save(out)
    with open(out, "rb") as fp:
        digest = hashlib.sha256(fp.read()).hexdigest()
    glyphs = len(font.getBestCmap())
    print(f"{out} {os.path.getsize(out)} bytes cmap={glyphs} sha256={digest}")


def main():
    """인자 · 원본 · 작업 위치 · ARB 를 확인하고 ko(KR) · ja(JP) subset 두 개를 만든다.

    검사와 두 ARB 읽기는 모두 첫 쓰기(build) 전이다 — 하나라도 어긋나면 아무것도 쓰지 않고 멈춘다.
    """
    if len(sys.argv) != 2:
        sys.exit(f"사용법: python -X utf8 {sys.argv[0]} <NotoSansCJK-Regular.ttc 경로>")
    src = sys.argv[1]
    if not os.path.isfile(src):
        sys.exit(f"원본 파일이 없다: {src}")
    if not (os.path.isdir(L10N) and os.path.isdir(OUT)):
        sys.exit(f"{L10N} · {OUT} 가 없다 — 저장소 루트에서 돌린다.")
    missing = [p for p in (arb_path("ko"), arb_path("ja")) if not os.path.isfile(p)]
    if missing:
        sys.exit("ARB 파일이 없다: " + " · ".join(missing))
    with open(src, "rb") as fp:
        actual = hashlib.sha256(fp.read()).hexdigest()
    if actual != SRC_SHA256:
        sys.exit(f"원본 sha256 불일치: {actual}")
    extra = {ord(c) for c in FIXTURE_EXTRA}
    # 두 ARB 를 다 읽은 뒤에 첫 build — ja 를 읽다 실패해도 KR 만 남는 부분 쓰기가 없다
    ko = arb_codepoints("ko")
    ja = arb_codepoints("ja")
    build(src, 1, f"{OUT}/NotoSansCJKKR-Regular-Subset.otf", ASCII | HANGUL | ko | extra)
    build(src, 0, f"{OUT}/NotoSansCJKJP-Regular-Subset.otf", ASCII | KANA | ja | extra)


if __name__ == "__main__":
    main()
