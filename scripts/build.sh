#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
사용법: ./scripts/build.sh [Release|Debug]

인자 없이 실행하면 Release로 빌드합니다.
결과: build/CrashTrim.app
로그: build/build.log
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

configuration="${1:-Release}"
if [[ $# -gt 1 || ( "$configuration" != "Release" && "$configuration" != "Debug" ) ]]; then
    usage >&2
    exit 2
fi

if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
    printf '%s\n' '오류: macOS와 Xcode가 필요합니다.' >&2
    exit 1
fi
if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
    printf '%s\n' '오류: Xcode를 설치하고 활성 개발자 디렉터리로 선택해 주세요.' \
        '예: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer' >&2
    exit 1
fi

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
build_dir="$project_root/build"
output_app="$build_dir/CrashTrim.app"
mkdir -p "$build_dir"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$build_dir/ModuleCache.noindex}"

printf 'CrashTrim %s 빌드 중…\n' "$configuration"
if ! /usr/bin/xcodebuild \
    -quiet \
    -project "$project_root/CrashTrim.xcodeproj" \
    -scheme CrashTrim \
    -configuration "$configuration" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$build_dir/DerivedData" \
    ONLY_ACTIVE_ARCH=NO \
    build 2>&1 | /usr/bin/tee "$build_dir/build.log"; then
    printf '빌드 실패. 로그: %s\n' "$build_dir/build.log" >&2
    exit 1
fi

# Prepare and verify a complete bundle before replacing the previous build.
stage_root="$(/usr/bin/mktemp -d "$build_dir/.stage.XXXXXX")"
trap 'rm -rf -- "$stage_root"' EXIT
source_app="$build_dir/DerivedData/Build/Products/$configuration/CrashTrim.app"
/usr/bin/ditto "$source_app" "$stage_root/CrashTrim.app"
/usr/bin/codesign --verify --deep --strict "$stage_root/CrashTrim.app"
rm -rf -- "$output_app"
mv -- "$stage_root/CrashTrim.app" "$output_app"

printf '\n빌드 완료: %s\n' "$output_app"
printf '실행: open "%s"\n' "$output_app"
