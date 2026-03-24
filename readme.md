# platform-infra

Production-grade CI/CD building blocks for a multi-tenant deployment platform (Vercel/Render style).

## What this repo provides

- Single generic Jenkins pipeline for all frameworks
- Automatic framework detection and Dockerfile fallback templates
- Docker image build/push with immutable version tag format:
  - `<userId>-<buildNumber>-<commitSHA>`
- GitOps update script that writes to:
  - `apps/<userId>/<projectName>/`
- Helm templates for Deployment, Service, Ingress, and HPA
- Conflict-safe GitOps pushes with retry logic

## Supported frameworks

- Node.js (`nextjs`, `react`, `nodejs`)
- Java (`springboot-maven`, `springboot-gradle`, `java-maven`, `java-gradle`)
- Python (`fastapi`, `flask`, `python`)
- PHP (`laravel`, `php`)
- Static sites (`static`)

## Key files

- `jenkins/Jenkinsfile`
- `jenkins/scripts/detect-framework.sh`
- `jenkins/scripts/generate-dockerfile.sh`
- `jenkins/scripts/update-gitops.sh`
- `docker/dockerfiles/*`
- `helm/app-template/*`

## Jenkins credentials required

- `infra-repo-url` (Secret text)
- `infra-repo-creds` (Git credentials)
- `registry-repository` (Secret text, e.g. `registry.example.com/platform`)
- `registry-credentials` (Username/Password)
- `gitops-repo-url` (Secret text, SSH URL)
- `gitops-ssh` (SSH private key)

## Pipeline inputs

- `REPO_URL`
- `BRANCH`
- `USER_ID`
- `PROJECT_NAME`
- `APP_PORT`
- `PLATFORM_DOMAIN`
- `GITOPS_BRANCH`
- `REPO_CREDENTIALS_ID` (optional)

## Local validation

```bash
bash -n jenkins/scripts/detect-framework.sh
bash -n jenkins/scripts/generate-dockerfile.sh
bash -n jenkins/scripts/update-gitops.sh
```
