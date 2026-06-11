#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: update-gitops.sh \
  --domain-only \
  --gitops-repo <ssh-url> \
  --gitops-branch <branch> \
  --ssh-key <path> \
  --operation <deploy|rollback|delete> \
  --workspace-id <workspace-namespace> \
  --user-id <user-id> \
  --project-name <project-name> \
  --custom-domain <domain> \
  --env-json <json> \
  --vault-env-path <vault-kv-path> \
  --image-repository <repository> \
  --image-tag <tag> \
  --app-port <port> \
  --platform-domain <domain> \
  --framework <framework> \
  --commit-sha <sha> \
  --build-number <build-number> \
  --chart-source <path>
USAGE
}

slugify() {
  local raw="$1"
  local max_len="${2:-40}"

  local normalized
  normalized="$(echo "${raw}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"

  if [[ -z "${normalized}" ]]; then
    normalized="x"
  fi

  echo "${normalized}" | cut -c1-"${max_len}"
}

default_container_port_for_framework() {
  local framework="$1"

  case "${framework}" in
    nextjs|nodejs)
      echo "3000"
      ;;
    react|laravel|php|static|tailwind-static)
      echo "80"
      ;;
    springboot-maven|springboot-gradle|java-maven|java-gradle)
      echo "8080"
      ;;
    fastapi|flask|python)
      echo "8000"
      ;;
    *)
      echo "3000"
      ;;
  esac
}

probe_mode_for_framework() {
  local framework="$1"

  case "${framework}" in
    springboot-maven|springboot-gradle|java-maven|java-gradle)
      echo "tcp"
      ;;
    fastapi|flask|python)
      echo "tcp"
      ;;
    *)
      echo "http"
      ;;
  esac
}

startup_probe_enabled_for_framework() {
  local framework="$1"

  case "${framework}" in
    springboot-maven|springboot-gradle|java-maven|java-gradle)
      echo "true"
      ;;
    *)
      echo "false"
      ;;
  esac
}

indent_block_scalar() {
  local content="$1"
  local indent="${2:-2}"
  local prefix
  prefix="$(printf '%*s' "${indent}" '')"

  if [[ -z "${content}" ]]; then
    echo "${prefix}[]"
    return 0
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    echo "${prefix}${line}"
  done <<< "${content}"
}

resolve_container_port() {
  local framework="$1"
  local requested_port="$2"
  local default_port

  default_port="$(default_container_port_for_framework "${framework}")"

  if [[ -z "${requested_port}" || "${requested_port}" == "3000" ]]; then
    echo "${default_port}"
    return 0
  fi

  echo "${requested_port}"
}

force_https_ingress() {
  local values_file="$1"

  if ! awk '
    BEGIN { in_ingress = 0; in_tls = 0 }
    {
      line = $0

      if (line ~ /^[[:space:]]*ingress:[[:space:]]*$/) {
        in_ingress = 1
        in_tls = 0
        print line
        next
      }

      if (in_ingress && line ~ /^[^[:space:]#][^:]*:[[:space:]]*$/) {
        in_ingress = 0
        in_tls = 0
      }

      if (in_ingress && line ~ /^[[:space:]]*tls:[[:space:]]*$/) {
        in_tls = 1
        print line
        next
      }

      if (in_ingress && in_tls && line ~ /^[[:space:]]*enabled:[[:space:]]*(true|false)[[:space:]]*$/) {
        sub(/enabled:[[:space:]]*(true|false)/, "enabled: true", line)
        print line
        next
      }

      print line
    }
  ' "${values_file}" > "${values_file}.tmp"; then
    rm -f "${values_file}.tmp"
    return 1
  fi

  mv "${values_file}.tmp" "${values_file}"
}

update_host_in_values_file() {
  local values_file="$1"
  local effective_host="$2"

  if ! awk -v host="${effective_host}" '
    BEGIN { in_app = 0; updated = 0 }
    {
      line = $0

      if (line ~ /^[[:space:]]*app:[[:space:]]*$/) {
        in_app = 1
        print line
        next
      }

      if (in_app && line ~ /^[^[:space:]#][^:]*:[[:space:]]*$/) {
        in_app = 0
      }

      if (in_app && line ~ /^[[:space:]]*host:[[:space:]]*/) {
        sub(/host:[[:space:]]*[^#]*/, "host: \"" host "\" ", line)
        sub(/[[:space:]]+$/, "", line)
        if (line !~ /managed-by-jenkins-host/) {
          line = line " # managed-by-jenkins-host"
        }
        updated = 1
        print line
        next
      }

      print line
    }
    END {
      if (updated == 0) {
        exit 2
      }
    }
  ' "${values_file}" > "${values_file}.tmp"; then
    rm -f "${values_file}.tmp"
    return 1
  fi

  mv "${values_file}.tmp" "${values_file}"
}

update_namespace_in_values_file() {
  local values_file="$1"
  local namespace="$2"

  if ! awk -v app_namespace="${namespace}" '
    BEGIN { in_app = 0; updated = 0 }
    {
      line = $0

      if (line ~ /^[[:space:]]*app:[[:space:]]*$/) {
        in_app = 1
        print line
        next
      }

      if (in_app && line ~ /^[^[:space:]#][^:]*:[[:space:]]*$/) {
        in_app = 0
      }

      if (in_app && line ~ /^[[:space:]]*namespace:[[:space:]]*/) {
        sub(/namespace:[[:space:]]*[^#]*/, "namespace: \"" app_namespace "\" ", line)
        sub(/[[:space:]]+$/, "", line)
        updated = 1
        print line
        next
      }

      print line
    }
    END {
      if (updated == 0) {
        exit 2
      }
    }
  ' "${values_file}" > "${values_file}.tmp"; then
    rm -f "${values_file}.tmp"
    return 1
  fi

  mv "${values_file}.tmp" "${values_file}"
}

read_app_host_from_values_file() {
  local values_file="$1"

  awk '
    BEGIN { in_app = 0 }
    {
      line = $0

      if (line ~ /^[[:space:]]*app:[[:space:]]*$/) {
        in_app = 1
        next
      }

      if (in_app && line ~ /^[^[:space:]#][^:]*:[[:space:]]*$/) {
        in_app = 0
      }

      if (in_app && line ~ /^[[:space:]]*host:[[:space:]]*/) {
        sub(/^[[:space:]]*host:[[:space:]]*/, "", line)
        sub(/[[:space:]]*#.*/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        gsub(/^"|"$/, "", line)
        print line
        exit
      }
    }
  ' "${values_file}"
}

create_values_file() {
  local values_file="$1"
  local safe_workspace_id="$2"
  local safe_user_id="$3"
  local safe_project_name="$4"
  local namespace="$5"
  local framework="$6"
  local image_repository="$7"
  local image_tag="$8"
  local app_port="$9"
  local domain="${10}"
  local custom_domain="${11}"
  local env_json="${12}"
  local vault_env_path="${13}"
  local effective_app_port
  local probe_mode
  local startup_probe_enabled

  local default_host_label
  default_host_label="$(slugify "${safe_project_name}-${safe_workspace_id}" 63)"
  effective_app_port="$(resolve_container_port "${framework}" "${app_port}")"
  probe_mode="$(probe_mode_for_framework "${framework}")"
  startup_probe_enabled="$(startup_probe_enabled_for_framework "${framework}")"

  local effective_host="${default_host_label}.${domain}"
  if [[ -n "${custom_domain}" ]]; then
    effective_host="${custom_domain}"
  fi

  if [[ -z "${env_json}" ]]; then
    env_json="[]"
  fi

  cat > "${values_file}" <<VALUES
app:
  name: "${safe_project_name}"
  userId: "${safe_user_id}"
  projectName: "${safe_project_name}"
  namespace: "${namespace}"
  framework: "${framework}"
  containerPort: ${effective_app_port}
  servicePort: 80
  domain: "${domain}"
  host: "${effective_host}" # managed-by-jenkins-host

image:
  repository: "${image_repository}"
  tag: "${image_tag}" # managed-by-jenkins-image-tag
  pullPolicy: "IfNotPresent"

replicaCount: 1

resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"

autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 4
  targetCPUUtilizationPercentage: 70

ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    enabled: true
    secretName: "${safe_project_name}-tls"

imagePullSecrets:
  - name: "registry-secret"

envJson: |
$(indent_block_scalar "${env_json}" 2)

vault:
  enabled: $([[ -n "${vault_env_path}" ]] && echo "true" || echo "false")
  secretStoreName: "vault-backend"
  secretStoreKind: "ClusterSecretStore"
  envPath: "${vault_env_path}"

probes:
  mode: "${probe_mode}"
  startup:
    enabled: ${startup_probe_enabled}
    path: "/"
    initialDelaySeconds: 0
    periodSeconds: 5
    failureThreshold: 24
  readiness:
    enabled: true
    path: "/"
    initialDelaySeconds: 10
    periodSeconds: 10
    failureThreshold: 3
  liveness:
    enabled: true
    path: "/"
    initialDelaySeconds: 30
    periodSeconds: 15
    failureThreshold: 3
VALUES
}

ensure_namespace_manifest() {
  local user_root="$1"
  local namespace="$2"

  cat > "${user_root}/namespace.yaml" <<NAMESPACE
apiVersion: v1
kind: Namespace
metadata:
  name: ${namespace}
  labels:
    app.kubernetes.io/managed-by: argocd
    platform.devops/workspace-namespace: "true"
NAMESPACE
}

describe_gitops_repo() {
  local repo="$1"

  if [[ "${repo}" =~ ^git@github\.com:([^/]+)/(.+)$ ]]; then
    echo "github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "${repo}" =~ ^https://github\.com/([^/]+)/(.+)$ ]]; then
    echo "github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    return 0
  fi

  echo "${repo}" | sed -E 's#^https?://##; s#^git@##; s#:#/#; s#/*$##'
}

commit_and_push() {
  local repo_dir="$1"
  local branch="$2"
  local project_path="$3"
  local namespace_file="$4"
  local commit_message="$5"
  local no_change_message="${6:-No GitOps changes required. Requested image tag already present.}"

  (
    cd "${repo_dir}"
    git config user.email "jenkins@platform.local"
    git config user.name "Jenkins CI"

    git add -A apps

    if git diff --cached --quiet; then
      echo "${no_change_message}"
      return 10
    fi

    git commit -m "${commit_message}" >/dev/null

    if git push origin "${branch}" >/dev/null; then
      echo "GitOps repository updated successfully."
      return 0
    fi

    return 1
  )
}

GITOPS_REPO=""
GITOPS_BRANCH="main"
SSH_KEY=""
OPERATION="deploy"
WORKSPACE_ID=""
USER_ID=""
PROJECT_NAME=""
IMAGE_REPOSITORY=""
IMAGE_TAG=""
APP_PORT=""
PLATFORM_DOMAIN=""
FRAMEWORK=""
COMMIT_SHA=""
BUILD_NUMBER=""
CHART_SOURCE=""
CUSTOM_DOMAIN=""
ENV_JSON="[]"
VAULT_ENV_PATH=""
DOMAIN_ONLY="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gitops-repo)
      GITOPS_REPO="$2"
      shift 2
      ;;
    --gitops-branch)
      GITOPS_BRANCH="$2"
      shift 2
      ;;
    --ssh-key)
      SSH_KEY="$2"
      shift 2
      ;;
    --operation)
      OPERATION="$2"
      shift 2
      ;;
    --workspace-id)
      WORKSPACE_ID="$2"
      shift 2
      ;;
    --user-id)
      USER_ID="$2"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --custom-domain)
      CUSTOM_DOMAIN="$2"
      shift 2
      ;;
    --env-json)
      ENV_JSON="$2"
      shift 2
      ;;
    --vault-env-path)
      VAULT_ENV_PATH="$2"
      shift 2
      ;;
    --image-repository)
      IMAGE_REPOSITORY="$2"
      shift 2
      ;;
    --image-tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --app-port)
      APP_PORT="$2"
      shift 2
      ;;
    --platform-domain)
      PLATFORM_DOMAIN="$2"
      shift 2
      ;;
    --framework)
      FRAMEWORK="$2"
      shift 2
      ;;
    --commit-sha)
      COMMIT_SHA="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --chart-source)
      CHART_SOURCE="$2"
      shift 2
      ;;
    --domain-only)
      DOMAIN_ONLY="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${OPERATION}" == "delete" ]]; then
  for required in GITOPS_REPO SSH_KEY WORKSPACE_ID USER_ID PROJECT_NAME; do
    if [[ -z "${!required}" ]]; then
      echo "Missing required argument: ${required}" >&2
      usage
      exit 1
    fi
  done
elif [[ "${DOMAIN_ONLY}" == "true" ]]; then
  for required in GITOPS_REPO SSH_KEY WORKSPACE_ID USER_ID PROJECT_NAME PLATFORM_DOMAIN; do
    if [[ -z "${!required}" ]]; then
      echo "Missing required argument: ${required}" >&2
      usage
      exit 1
    fi
  done
else
  for required in GITOPS_REPO SSH_KEY WORKSPACE_ID USER_ID PROJECT_NAME IMAGE_REPOSITORY IMAGE_TAG APP_PORT PLATFORM_DOMAIN FRAMEWORK COMMIT_SHA BUILD_NUMBER CHART_SOURCE; do
    if [[ -z "${!required}" ]]; then
      echo "Missing required argument: ${required}" >&2
      usage
      exit 1
    fi
  done

  if [[ ! -d "${CHART_SOURCE}" ]]; then
    echo "Chart source directory does not exist: ${CHART_SOURCE}" >&2
    exit 1
  fi
fi

if [[ -n "${CUSTOM_DOMAIN}" ]]; then
  CUSTOM_DOMAIN="$(echo "${CUSTOM_DOMAIN}" | tr '[:upper:]' '[:lower:]' | sed -E 's#^https?://##; s#/.*$##; s/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ -n "${CUSTOM_DOMAIN}" ]]; then
    if [[ "${CUSTOM_DOMAIN}" == *":"* ]]; then
      echo "Custom domain must not include a port: ${CUSTOM_DOMAIN}" >&2
      exit 1
    fi
    if [[ "${CUSTOM_DOMAIN}" == \*.* ]]; then
      echo "Wildcard custom domain is not supported: ${CUSTOM_DOMAIN}" >&2
      exit 1
    fi
    if [[ ! "${CUSTOM_DOMAIN}" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]; then
      echo "Invalid custom domain format: ${CUSTOM_DOMAIN}" >&2
      exit 1
    fi
  fi
fi

if [[ ! -f "${SSH_KEY}" ]]; then
  echo "SSH key file not found: ${SSH_KEY}" >&2
  echo "Verify Jenkins credential 'gitops-ssh' is configured as 'SSH Username with private key'." >&2
  exit 1
fi

chmod 600 "${SSH_KEY}" || true

if ! ssh-keygen -y -f "${SSH_KEY}" >/dev/null 2>&1; then
  echo "Invalid SSH private key provided by Jenkins credential 'gitops-ssh'." >&2
  echo "Expected a real private key (OpenSSH/PEM), not a GitHub token/password." >&2
  echo "Use username 'git' and paste the private key content in Jenkins credentials." >&2
  exit 1
fi

# If Jenkins stores GitHub repo as HTTPS but we authenticate via SSH key,
# convert to SSH URL so git clone/push can use GIT_SSH_COMMAND.
if [[ "${GITOPS_REPO}" =~ ^https://github\.com/([^/]+)/([^/]+)/?$ ]]; then
  GITHUB_OWNER="${BASH_REMATCH[1]}"
  GITHUB_REPO="${BASH_REMATCH[2]%.git}"
  GITOPS_REPO="git@github.com:${GITHUB_OWNER}/${GITHUB_REPO}.git"
fi

echo "[GitOps] Target repository: $(describe_gitops_repo "${GITOPS_REPO}") | branch=${GITOPS_BRANCH}"

SAFE_WORKSPACE_ID="$(slugify "${WORKSPACE_ID}" 63)"
SAFE_USER_ID="$(slugify "${USER_ID}" 30)"
SAFE_PROJECT_NAME="$(slugify "${PROJECT_NAME}" 40)"
# WORKSPACE_ID is the namespace created by backend onboarding, e.g. ns-username-1234abcd.
NAMESPACE="${SAFE_WORKSPACE_ID}"
DEFAULT_HOST_LABEL="$(slugify "${SAFE_PROJECT_NAME}-${SAFE_WORKSPACE_ID}" 63)"
EFFECTIVE_HOST="${DEFAULT_HOST_LABEL}.${PLATFORM_DOMAIN}"
if [[ -n "${CUSTOM_DOMAIN}" ]]; then
  EFFECTIVE_HOST="${CUSTOM_DOMAIN}"
fi

export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"

MAX_ATTEMPTS=5
ATTEMPT=1

while [[ "${ATTEMPT}" -le "${MAX_ATTEMPTS}" ]]; do
  WORK_DIR="$(mktemp -d)"

  cleanup() {
    cd /tmp || true
    rm -rf "${WORK_DIR}"
  }
  trap cleanup EXIT

  echo "[GitOps] Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: cloning ${GITOPS_REPO}"
  git clone --branch "${GITOPS_BRANCH}" --depth 1 "${GITOPS_REPO}" "${WORK_DIR}/gitops" >/dev/null

  REPO_DIR="${WORK_DIR}/gitops"
  LEGACY_APP_ROOT="apps/${SAFE_USER_ID}/${SAFE_PROJECT_NAME}"
  NEW_APP_ROOT="apps/${SAFE_WORKSPACE_ID}/${SAFE_USER_ID}/${SAFE_PROJECT_NAME}"

  if [[ -d "${REPO_DIR}/${LEGACY_APP_ROOT}" && ! -d "${REPO_DIR}/${NEW_APP_ROOT}" ]]; then
    APP_ROOT="${LEGACY_APP_ROOT}"
    USER_ROOT="apps/${SAFE_USER_ID}"
    echo "[GitOps] Legacy layout detected, writing to ${APP_ROOT}"
  else
    APP_ROOT="${NEW_APP_ROOT}"
    USER_ROOT="apps/${SAFE_WORKSPACE_ID}/${SAFE_USER_ID}"
  fi

  NAMESPACE_FILE="${USER_ROOT}/namespace.yaml"
  PROJECT_DIR="${REPO_DIR}/${APP_ROOT}"
  VALUES_FILE="${PROJECT_DIR}/values.yaml"

  if [[ "${OPERATION}" == "delete" ]]; then
    echo "[GitOps] Delete operation: removing ${APP_ROOT}"
    if [[ -d "${PROJECT_DIR}" ]]; then
      rm -rf "${PROJECT_DIR}"
    fi

    if [[ -d "${REPO_DIR}/${USER_ROOT}" ]] && ! find "${REPO_DIR}/${USER_ROOT}" -mindepth 1 -maxdepth 1 | grep -q .; then
      rm -rf "${REPO_DIR}/${USER_ROOT}"
    fi
  else
    mkdir -p "${PROJECT_DIR}" "${REPO_DIR}/${USER_ROOT}"

    ensure_namespace_manifest "${REPO_DIR}/${USER_ROOT}" "${NAMESPACE}"
  fi

  if [[ "${OPERATION}" == "delete" ]]; then
    :
  elif [[ "${DOMAIN_ONLY}" == "true" ]]; then
    if [[ ! -f "${VALUES_FILE}" ]]; then
      echo "Cannot apply domain-only update because values file does not exist yet: ${VALUES_FILE}" >&2
      echo "Run a full deployment once before using domain-only updates." >&2
      exit 1
    fi

    CURRENT_HOST="$(read_app_host_from_values_file "${VALUES_FILE}")"
    echo "[GitOps] Domain-only host update: current=${CURRENT_HOST:-<missing>} desired=${EFFECTIVE_HOST}"

    update_host_in_values_file "${VALUES_FILE}" "${EFFECTIVE_HOST}" || {
      echo "Unable to update app.host in ${VALUES_FILE}." >&2
      exit 1
    }
    update_namespace_in_values_file "${VALUES_FILE}" "${NAMESPACE}" || {
      echo "Unable to update app.namespace in ${VALUES_FILE}." >&2
      exit 1
    }

    UPDATED_HOST="$(read_app_host_from_values_file "${VALUES_FILE}")"
    if [[ "${UPDATED_HOST}" != "${EFFECTIVE_HOST}" ]]; then
      echo "Domain-only update did not set expected host. current=${UPDATED_HOST:-<missing>} desired=${EFFECTIVE_HOST}" >&2
      exit 1
    fi
  else
    if [[ ! -f "${PROJECT_DIR}/Chart.yaml" ]]; then
      cp -R "${CHART_SOURCE}/." "${PROJECT_DIR}/"
    fi

    create_values_file "${VALUES_FILE}" "${SAFE_WORKSPACE_ID}" "${SAFE_USER_ID}" "${SAFE_PROJECT_NAME}" "${NAMESPACE}" "${FRAMEWORK}" "${IMAGE_REPOSITORY}" "${IMAGE_TAG}" "${APP_PORT}" "${PLATFORM_DOMAIN}" "${CUSTOM_DOMAIN}" "${ENV_JSON}" "${VAULT_ENV_PATH}"
  fi

  if [[ "${OPERATION}" != "delete" ]]; then
    force_https_ingress "${VALUES_FILE}" || {
      echo "Unable to force HTTPS ingress mode in ${VALUES_FILE}." >&2
      exit 1
    }
  fi

  if [[ "${DOMAIN_ONLY}" == "true" ]]; then
    COMMIT_MESSAGE="domain(${SAFE_USER_ID}/${SAFE_PROJECT_NAME}): host=${EFFECTIVE_HOST}"
    NO_CHANGE_MESSAGE="No GitOps changes required. Domain host already set to ${EFFECTIVE_HOST}."
  elif [[ "${OPERATION}" == "delete" ]]; then
    COMMIT_MESSAGE="delete(${SAFE_USER_ID}/${SAFE_PROJECT_NAME}): remove monolith resources"
    NO_CHANGE_MESSAGE="No GitOps changes required. Project resources were already absent."
  elif [[ "${OPERATION}" == "rollback" ]]; then
    COMMIT_MESSAGE="rollback(${SAFE_USER_ID}/${SAFE_PROJECT_NAME}): image=${IMAGE_REPOSITORY}:${IMAGE_TAG} build=${BUILD_NUMBER} sha=${COMMIT_SHA}"
    NO_CHANGE_MESSAGE="No GitOps changes required. Requested image tag already present."
  else
    COMMIT_MESSAGE="deploy(${SAFE_USER_ID}/${SAFE_PROJECT_NAME}): image=${IMAGE_REPOSITORY}:${IMAGE_TAG} build=${BUILD_NUMBER} sha=${COMMIT_SHA}"
    NO_CHANGE_MESSAGE="No GitOps changes required. Requested image tag already present."
  fi

  set +e
  commit_and_push "${REPO_DIR}" "${GITOPS_BRANCH}" "${APP_ROOT}" "${NAMESPACE_FILE}" "${COMMIT_MESSAGE}" "${NO_CHANGE_MESSAGE}"
  RESULT=$?
  set -e

  if [[ "${RESULT}" -eq 0 ]]; then
    trap - EXIT
    cleanup
    exit 0
  fi

  if [[ "${RESULT}" -eq 10 ]]; then
    trap - EXIT
    cleanup
    exit 0
  fi

  echo "[GitOps] Push conflict detected, retrying..."
  ATTEMPT=$((ATTEMPT + 1))
  trap - EXIT
  cleanup
  sleep 2
done

echo "Failed to update GitOps repository after ${MAX_ATTEMPTS} attempts." >&2
exit 1
