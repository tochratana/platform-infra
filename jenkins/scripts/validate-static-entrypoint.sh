#!/usr/bin/env bash
set -euo pipefail

FRAMEWORK_NAME="${1:-${FRAMEWORK:-static}}"

case "${FRAMEWORK_NAME}" in
  static|tailwind-static) ;;
  *) exit 0 ;;
esac

if [[ -f Dockerfile && "${FORCE_PLATFORM_DOCKERFILE:-false}" != "true" ]]; then
  echo "[preflight] User-provided Dockerfile detected; skipping platform static entrypoint validation." >&2
  exit 0
fi

ENTRYPOINTS=("index.html" "dist/index.html" "build/index.html" "public/index.html")
if [[ "${FRAMEWORK_NAME}" == "tailwind-static" ]]; then
  ENTRYPOINTS+=("src/index.html")
fi

for entrypoint in "${ENTRYPOINTS[@]}"; do
  if [[ -f "${entrypoint}" ]]; then
    echo "[preflight] Static entrypoint found: ${entrypoint}" >&2
    exit 0
  fi
done

html_files=()
html_count=0
while IFS= read -r -d '' file_path; do
  relative_path="${file_path#./}"
  if (( html_count < 5 )); then
    html_files+=("${relative_path}")
  fi
  html_count=$((html_count + 1))
done < <(
  find . -maxdepth 3 -type f -iname '*.html' \
    ! -path './node_modules/*' \
    ! -path './.git/*' \
    ! -path './.next/*' \
    ! -path './vendor/*' \
    -print0
)

expected="$(printf '%s, ' "${ENTRYPOINTS[@]}")"
expected="${expected%, }"
message="Static deploy could not find an index.html entrypoint. This platform expects one of: ${expected}. Add or rename the page you want to serve as index.html, then deploy again."

if (( html_count > 0 )); then
  found="$(printf '%s, ' "${html_files[@]}")"
  found="${found%, }"
  message="${message} Found HTML file(s): ${found}."
  if (( html_count > ${#html_files[@]} )); then
    message="${message} And $((html_count - ${#html_files[@]})) more."
  fi
fi

echo "[preflight] ${message}" >&2
printf '%s\n' "${message}"
exit 1
