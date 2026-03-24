#!/usr/bin/env bash
set -euo pipefail

has_dependency_in_package_json() {
  local package_name="$1"

  if command -v node >/dev/null 2>&1; then
    PACKAGE_NAME="$package_name" node -e '
      const fs = require("fs");
      if (!fs.existsSync("package.json")) process.exit(1);
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      const deps = {
        ...(pkg.dependencies || {}),
        ...(pkg.devDependencies || {}),
        ...(pkg.peerDependencies || {})
      };
      process.exit(Object.prototype.hasOwnProperty.call(deps, process.env.PACKAGE_NAME) ? 0 : 1);
    ' >/dev/null 2>&1 && return 0
  fi

  grep -Eiq "\"${package_name}\"[[:space:]]*:" package.json
}

has_python_dependency() {
  local name="$1"
  if [[ -f requirements.txt ]] && grep -Eiq "(^|[[:space:]])${name}([<>=~!].*)?$" requirements.txt; then
    return 0
  fi

  if [[ -f pyproject.toml ]] && grep -Eiq "(^|[[:space:]\"'])${name}([[:space:]\"'=><~!]|$)" pyproject.toml; then
    return 0
  fi

  return 1
}

if [[ -f package.json ]]; then
  if has_dependency_in_package_json "next"; then
    echo "nextjs"
  elif has_dependency_in_package_json "react"; then
    echo "react"
  else
    echo "nodejs"
  fi
  exit 0
fi

if [[ -f pom.xml ]]; then
  if grep -Eiq "spring-boot" pom.xml; then
    echo "springboot-maven"
  else
    echo "java-maven"
  fi
  exit 0
fi

if [[ -f build.gradle || -f build.gradle.kts ]]; then
  if grep -Eiq "spring-boot|org\.springframework\.boot" build.gradle build.gradle.kts 2>/dev/null; then
    echo "springboot-gradle"
  else
    echo "java-gradle"
  fi
  exit 0
fi

if [[ -f composer.json ]]; then
  if grep -Eiq "\"laravel/framework\"[[:space:]]*:" composer.json; then
    echo "laravel"
  else
    echo "php"
  fi
  exit 0
fi

if [[ -f requirements.txt || -f pyproject.toml ]]; then
  if has_python_dependency "fastapi"; then
    echo "fastapi"
  elif has_python_dependency "flask"; then
    echo "flask"
  else
    echo "python"
  fi
  exit 0
fi

if [[ -f index.html || -f public/index.html || -f dist/index.html ]]; then
  echo "static"
  exit 0
fi

echo "static"
