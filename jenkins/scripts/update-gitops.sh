#!/bin/bash
set -e

APP_NAME=$1
IMAGE_TAG=$2
APP_PORT=$3
GITOPS_REPO=$4
SSH_KEY=$5
PLATFORM_DOMAIN=${6:-yourplatform.com}
USER_ID=${7:-unknown}
VERSION_LABEL=${8:-unknown}
APP_COMMIT_SHA=${9:-unknown}

SAFE_USER_ID=$(echo "$USER_ID" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9.-]+/-/g; s/^-+//; s/-+$//; s/^$/unknown/; s/^(.{1,63}).*$/\1/')
SAFE_VERSION=$(echo "$VERSION_LABEL" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9.-]+/-/g; s/^-+//; s/-+$//; s/^$/unknown/; s/^(.{1,63}).*$/\1/')
SAFE_COMMIT=$(echo "$APP_COMMIT_SHA" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9.-]+/-/g; s/^-+//; s/-+$//; s/^$/unknown/; s/^(.{1,63}).*$/\1/')

GITOPS_DIR="gitops-tmp-${APP_NAME}"

export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no"

echo "Cloning GitOps repo..."
git clone "$GITOPS_REPO" "$GITOPS_DIR"

APP_DIR="${GITOPS_DIR}/apps/${APP_NAME}"
mkdir -p "$APP_DIR"

# ── deployment.yaml ──────────────────────────────────────────────────
cat > "${APP_DIR}/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: apps
  labels:
    app: ${APP_NAME}
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/version: ${SAFE_VERSION}
    cloudflow.dev/user-id: ${SAFE_USER_ID}
    cloudflow.dev/commit-sha: ${SAFE_COMMIT}
  annotations:
    cloudflow.dev/version: ${VERSION_LABEL}
    cloudflow.dev/commit-sha: ${APP_COMMIT_SHA}
    cloudflow.dev/requested-by: ${USER_ID}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        app.kubernetes.io/name: ${APP_NAME}
        app.kubernetes.io/version: ${SAFE_VERSION}
        cloudflow.dev/user-id: ${SAFE_USER_ID}
        cloudflow.dev/commit-sha: ${SAFE_COMMIT}
      annotations:
        cloudflow.dev/version: ${VERSION_LABEL}
        cloudflow.dev/commit-sha: ${APP_COMMIT_SHA}
        cloudflow.dev/requested-by: ${USER_ID}
    spec:
      imagePullSecrets:
        - name: registry-secret
      containers:
        - name: ${APP_NAME}
          image: ${IMAGE_TAG}
          ports:
            - containerPort: ${APP_PORT}
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          readinessProbe:
            httpGet:
              path: /
              port: ${APP_PORT}
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /
              port: ${APP_PORT}
            initialDelaySeconds: 30
            periodSeconds: 10
EOF

# ── service.yaml ─────────────────────────────────────────────────────
cat > "${APP_DIR}/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: apps
  labels:
    app: ${APP_NAME}
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/version: ${SAFE_VERSION}
    cloudflow.dev/user-id: ${SAFE_USER_ID}
    cloudflow.dev/commit-sha: ${SAFE_COMMIT}
  annotations:
    cloudflow.dev/version: ${VERSION_LABEL}
    cloudflow.dev/commit-sha: ${APP_COMMIT_SHA}
    cloudflow.dev/requested-by: ${USER_ID}
spec:
  selector:
    app: ${APP_NAME}
  ports:
    - name: http
      port: 80
      targetPort: ${APP_PORT}
  type: ClusterIP
EOF

# ── ingress.yaml ──────────────────────────────────────────────────────
cat > "${APP_DIR}/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${APP_NAME}
  namespace: apps
  labels:
    app: ${APP_NAME}
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/version: ${SAFE_VERSION}
    cloudflow.dev/user-id: ${SAFE_USER_ID}
    cloudflow.dev/commit-sha: ${SAFE_COMMIT}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: letsencrypt-prod
    cloudflow.dev/version: ${VERSION_LABEL}
    cloudflow.dev/commit-sha: ${APP_COMMIT_SHA}
    cloudflow.dev/requested-by: ${USER_ID}
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - ${APP_NAME}.${PLATFORM_DOMAIN}
      secretName: ${APP_NAME}-tls
  rules:
    - host: ${APP_NAME}.${PLATFORM_DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${APP_NAME}
                port:
                  number: 80
EOF

# ── commit & push ─────────────────────────────────────────────────────
cd "$GITOPS_DIR"
git config user.email "jenkins@yourplatform.com"
git config user.name "Jenkins CI"
git add .

if git diff --cached --quiet; then
    echo "No changes to commit — image tag unchanged."
else
    git commit -m "deploy(${APP_NAME}): user=${USER_ID} version=${VERSION_LABEL} image=${IMAGE_TAG}"
    git push origin main
    echo "GitOps repo updated. ArgoCD will sync shortly."
fi

cd ..
rm -rf "$GITOPS_DIR"
