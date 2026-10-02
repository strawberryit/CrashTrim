#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
사용법: ./scripts/create-dmg.sh [--skip-build]

기본: Release 앱을 빌드한 뒤 DMG를 생성합니다.
--skip-build: 기존 build/CrashTrim.app을 패키징합니다.
결과: build/CrashTrim.dmg
EOF
}

if [[ $# -gt 1 ]]; then
    usage >&2
    exit 2
fi
skip_build=false
case "${1:-}" in
    '') ;;
    --skip-build) skip_build=true ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
    printf '%s\n' '오류: DMG 생성에는 macOS가 필요합니다.' >&2
    exit 1
fi

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
build_dir="$project_root/build"
app_path="$build_dir/CrashTrim.app"
output_dmg="$build_dir/CrashTrim.dmg"

if [[ "$skip_build" == false ]]; then
    "$project_root/scripts/build.sh" Release
fi
if [[ ! -d "$app_path" ]]; then
    printf '오류: 앱이 없습니다: %s\n먼저 ./scripts/build.sh를 실행해 주세요.\n' "$app_path" >&2
    exit 1
fi

stage_root="$(/usr/bin/mktemp -d "$build_dir/.dmg.XXXXXX")"
trap 'rm -rf -- "$stage_root"' EXIT
mkdir -p "$stage_root/contents"
/usr/bin/ditto "$app_path" "$stage_root/contents/CrashTrim.app"
/usr/bin/codesign --verify --deep --strict "$stage_root/contents/CrashTrim.app"
ln -s /Applications "$stage_root/contents/Applications"

printf '\nCrashTrim DMG 생성 중…\n'
# Build the HFS+ filesystem without attaching a disk image or controlling Finder.
/usr/bin/hdiutil makehybrid \
    -hfs \
    -hfs-volume-name CrashTrim \
    -o "$stage_root/CrashTrim-uncompressed.dmg" \
    "$stage_root/contents"
/usr/bin/hdiutil convert \
    "$stage_root/CrashTrim-uncompressed.dmg" \
    -format UDZO \
    -o \
    "$stage_root/CrashTrim.dmg"
/usr/bin/hdiutil verify "$stage_root/CrashTrim.dmg"

# Preserve the previous image unless the new one has been created and verified.
mv -f -- "$stage_root/CrashTrim.dmg" "$output_dmg"
printf '\nDMG 생성 완료: %s\n' "$output_dmg"
