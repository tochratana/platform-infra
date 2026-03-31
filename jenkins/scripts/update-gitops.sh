#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: update-gitops.sh \
  --gitops-repo <ssh-url> \
  --gitops-branch <branch> \
  --ssh-key <path> \
  --user-id <user-id> \
  --project-name <project-name> \
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

replace_image_tag() {
  local values_file="$1"
  local image_tag="$2"

  if ! awk -v tag="${image_tag}" '
    BEGIN { updated = 0 }
    /managed-by-jenkins-image-tag/ && updated == 0 {
      sub(/tag:[[:space:]]*[^#]+/, "tag: \"" tag "\"")
      updated = 1
    }
    { print }
    END { if (updated == 0) exit 1 }
  ' "${values_file}" > "${values_file}.tmp"; then
    rm -f "${values_file}.tmp"
    return 1
  fi

  mv "${values_file}.tmp" "${values_file}"
}

create_values_file() {
  local values_file="$1"
  local safe_user_id="$2"
  local safe_project_name="$3"
  local namespace="$4"
  local framework="$5"
  local image_repository="$6"
  local image_tag="$7"
  local app_port="$8"
  local domain="$9"

  cat > "${values_file}" <<VALUES
app:
  name: "${safe_project_name}"
  userId: "${safe_user_id}"
  projectName: "${safe_project_name}"
  namespace: "${namespace}"
  framework: "${framework}"
  containerPort: ${app_port}
  servicePort: 80
  domain: "${domain}"
  host: "${safe_project_name}.${domain}"

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

probes:
  readiness:
    enabled: true
    path: "/"
    initialDelaySeconds: 10
    periodSeconds: 10
  liveness:
    enabled: true
    path: "/"
    initialDelaySeconds: 30
    periodSeconds: 15

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
    platform.devops/user-namespace: "true"
NAMESPACE
}

commit_and_push() {
  local repo_dir="$1"
  local branch="$2"
  local project_path="$3"
  local namespace_file="$4"
  local commit_message="$5"

  (
    cd "${repo_dir}"
    git config user.email "jenkins@platform.local"
    git config user.name "Jenkins CI"

    git add "${project_path}" "${namespace_file}"

    if git diff --cached --quiet; then
      echo "No GitOps changes required. Requested image tag already present."
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
    --user-id)
      USER_ID="$2"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME="$2"
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

for required in GITOPS_REPO SSH_KEY USER_ID PROJECT_NAME IMAGE_REPOSITORY IMAGE_TAG APP_PORT PLATFORM_DOMAIN FRAMEWORK COMMIT_SHA BUILD_NUMBER CHART_SOURCE; do
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

# If Jenkins stores GitHub repo as HTTPS but we authenticate via SSH key,
# convert to SSH URL so git clone/push can use GIT_SSH_COMMAND.
if [[ "${GITOPS_REPO}" =~ ^https://github\.com/([^/]+)/([^/]+?)(\.git)?/?$ ]]; then
  GITOPS_REPO="git@github.com:${BASH_REMATCH[1]}/${BASH_REMATCH[2]}.git"
fi

SAFE_USER_ID="$(slugify "${USER_ID}" 30)"
SAFE_PROJECT_NAME="$(slugify "${PROJECT_NAME}" 40)"
NAMESPACE="user-${SAFE_USER_ID}"
APP_ROOT="apps/${SAFE_USER_ID}/${SAFE_PROJECT_NAME}"
USER_ROOT="apps/${SAFE_USER_ID}"
NAMESPACE_FILE="${USER_ROOT}/namespace.yaml"

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
  PROJECT_DIR="${REPO_DIR}/${APP_ROOT}"
  VALUES_FILE="${PROJECT_DIR}/values.yaml"

  mkdir -p "${PROJECT_DIR}" "${REPO_DIR}/${USER_ROOT}"

  ensure_namespace_manifest "${REPO_DIR}/${USER_ROOT}" "${NAMESPACE}"

  if [[ ! -f "${PROJECT_DIR}/Chart.yaml" ]]; then
    cp -R "${CHART_SOURCE}/." "${PROJECT_DIR}/"
  fi

  if [[ ! -f "${VALUES_FILE}" ]]; then
    create_values_file "${VALUES_FILE}" "${SAFE_USER_ID}" "${SAFE_PROJECT_NAME}" "${NAMESPACE}" "${FRAMEWORK}" "${IMAGE_REPOSITORY}" "${IMAGE_TAG}" "${APP_PORT}" "${PLATFORM_DOMAIN}"
  else
    replace_image_tag "${VALUES_FILE}" "${IMAGE_TAG}" || {
      echo "Unable to locate managed image tag marker in ${VALUES_FILE}." >&2
      exit 1
    }
  fi

  COMMIT_MESSAGE="deploy(${SAFE_USER_ID}/${SAFE_PROJECT_NAME}): image=${IMAGE_REPOSITORY}:${IMAGE_TAG} build=${BUILD_NUMBER} sha=${COMMIT_SHA}"

  set +e
  commit_and_push "${REPO_DIR}" "${GITOPS_BRANCH}" "${APP_ROOT}" "${NAMESPACE_FILE}" "${COMMIT_MESSAGE}"
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
