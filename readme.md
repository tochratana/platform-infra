# platform-infra

CI/CD templates and scripts used by Jenkins to build user applications and update the GitOps repository.

## What this repo does

- Detect application framework
- Generate Dockerfile template when app repo does not include one
- Build and push container images
- Update GitOps manifests (`deployment.yaml`, `service.yaml`, `ingress.yaml`)

## Repo structure

- `jenkins/Jenkinsfile`: main deployment pipeline
- `jenkins/scripts/`: helper scripts used by the pipeline
- `docker/dockerfiles/`: Dockerfile templates per framework
- `helm/app-template/`: app Helm chart template
- `kubernetes/`: cluster bootstrap manifests (namespace, registry secret, ingress values)
- `argocd/`: ArgoCD bootstrap manifests

## Supported frameworks

- `nextjs`
- `nodejs`
- `springboot`
- `gradle`
- `go`
- `fastapi`
- `python`
- `static`

## Clone and use

1. Clone:

```bash
git clone <your-infra-repo-url>
cd plateform-infra
```

2. In Jenkins, create a pipeline job that uses `jenkins/Jenkinsfile` from this repo.

3. Configure required Jenkins credentials (IDs must match exactly):

- `registry-url` (Secret text)
- `registry-credentials` (Username/password)
- `gitops-repo-url` (Secret text)
- `gitops-ssh` (SSH private key)
- `infra-repo-url` (Secret text)
- `infra-repo-creds` (Username/password or token)

4. Trigger pipeline with parameters:

- `REPO_URL`
- `BRANCH`
- `APP_NAME`
- `APP_PORT`
- `USER_ID`
- `PLATFORM_DOMAIN`
- `DEPLOY_MODE` (`docker-local` or `gitops`)

## Local testing (before pushing)

### 1) Shell syntax check

```bash
bash -n jenkins/scripts/detect-framework.sh
bash -n jenkins/scripts/generate-dockerfile.sh
bash -n jenkins/scripts/build-app.sh
bash -n jenkins/scripts/update-gitops.sh
```

### 2) Framework detection smoke tests

```bash
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

echo '{"dependencies":{"next":"15.0.0"}}' > package.json
bash /path/to/plateform-infra/jenkins/scripts/detect-framework.sh   # expected: nextjs
```

### 3) Dockerfile generation smoke test

```bash
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
bash /path/to/plateform-infra/jenkins/scripts/generate-dockerfile.sh nextjs /path/to/plateform-infra/jenkins/scripts
cat Dockerfile
```

## Run pipeline testing in Jenkins

Recommended validation path:

1. Run with `DEPLOY_MODE=docker-local` first for fast feedback.
2. Run with `DEPLOY_MODE=gitops` and verify commit appears in your GitOps repo.
3. Confirm ArgoCD syncs and app becomes reachable at `https://<APP_NAME>.<PLATFORM_DOMAIN>`.

## Registry examples

### GitLab registry

- `registry-url`: `registry.gitlab.yourdomain.com/group/project`
- `registry-credentials`: GitLab user/token with push access

### Harbor registry

- `registry-url`: `harbor.example.com/project-name`
- `registry-credentials`: Harbor user/password or robot account

