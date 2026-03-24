#!/usr/bin/env bash
set -euo pipefail

FRAMEWORK="${1:-static}"
SCRIPTS_DIR="${2:-$(pwd)}"
TEMPLATES_DIR="${SCRIPTS_DIR}/../../docker/dockerfiles"

if [[ -f Dockerfile ]]; then
  echo "User-provided Dockerfile detected. Skipping template generation."
  exit 0
fi

template_for_framework() {
  case "$1" in
    nextjs) echo "Dockerfile.nextjs" ;;
    react) echo "Dockerfile.react" ;;
    nodejs) echo "Dockerfile.nodejs" ;;
    springboot-maven|java-maven|springboot) echo "Dockerfile.springboot" ;;
    springboot-gradle|java-gradle|gradle) echo "Dockerfile.gradle" ;;
    fastapi) echo "Dockerfile.fastapi" ;;
    flask) echo "Dockerfile.flask" ;;
    python) echo "Dockerfile.python" ;;
    laravel) echo "Dockerfile.laravel" ;;
    php) echo "Dockerfile.php" ;;
    static) echo "Dockerfile.static" ;;
    *) echo "Dockerfile.static" ;;
  esac
}

SELECTED_TEMPLATE="$(template_for_framework "${FRAMEWORK}")"
SOURCE_FILE="${TEMPLATES_DIR}/${SELECTED_TEMPLATE}"

if [[ ! -f "${SOURCE_FILE}" ]]; then
  echo "Template ${SELECTED_TEMPLATE} was not found. Falling back to Dockerfile.static."
  SOURCE_FILE="${TEMPLATES_DIR}/Dockerfile.static"
fi

cp "${SOURCE_FILE}" Dockerfile

echo "Generated Dockerfile from template: ${SELECTED_TEMPLATE}"
