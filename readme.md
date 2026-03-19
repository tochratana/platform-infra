# platform-infra

CI templates and scripts used by Jenkins to build user apps and update the GitOps repo.

## Pipeline responsibilities

- Detect project framework.
- Generate Dockerfile template (if user repo has no Dockerfile).
- Build and push container image.
- Write `deployment.yaml`, `service.yaml`, `ingress.yaml` to `platform-gitops`.

## Supported frameworks

- `nextjs`
- `nodejs`
- `springboot`
- `gradle`
- `go`
- `fastapi`
- `python`
- `static`

## Required Jenkins credentials

Create these credentials in Jenkins before running `deploy-pipeline`:

- `registry-url` (Secret text)
  - Value for self-hosted GitLab registry: `registry.gitlab.yourdomain.com/group/project`
- `registry-credentials` (Username with password)
  - Username: GitLab username (or deploy token username)
  - Password: GitLab personal access token / deploy token password
- `gitops-repo-url` (Secret text)
  - Example: `git@github.com:yourorg/platform-gitops.git`
- `gitops-ssh` (SSH Username with private key)
  - SSH key with push access to GitOps repo
- `infra-repo-url` (Secret text)
  - Example: `https://github.com/yourorg/platform-infra.git`
- `infra-repo-creds` (Username/password or token credential for `infra-repo-url`)

## Parameters you pass when triggering deploy-pipeline

- `REPO_URL`: user app git URL
- `BRANCH`: user app branch
- `APP_NAME`: unique app slug
- `APP_PORT`: app container port
- `USER_ID`: platform user id from backend auth subject
- `PLATFORM_DOMAIN`: base domain (example: `tochratana.com`)
- `DEPLOY_MODE`: `docker-local` or `gitops`

`DEPLOY_MODE` behavior:

- `docker-local`: build image, push image to registry, and run container on Jenkins host (no GitOps update).
- `gitops`: build image, push image to registry, and update GitOps manifests.

## Metadata stamped on manifests

`update-gitops.sh` now writes deployment metadata automatically:

- Label: `cloudflow.dev/user-id`
- Label: `app.kubernetes.io/version`
- Annotation: `cloudflow.dev/version`
- Annotation: `cloudflow.dev/commit-sha`
- Annotation: `cloudflow.dev/requested-by`

## GitLab registry example

If your registry server is `registry.gitlab.yourdomain.com` and images should live under
`group/project`, set:

- `registry-url` = `registry.gitlab.yourdomain.com/group/project`
- `registry-credentials` = GitLab user/token with push permission

The pipeline will:

- Login to `registry.gitlab.yourdomain.com`
- Push image as:
  - `registry.gitlab.yourdomain.com/group/project/<app-name>:<build-number>`

## Harbor registry example

If your Harbor URL is `harbor.devith.it.com` and your Harbor project is
`deployment-pipeline`, set Jenkins credentials:

- `registry-url` = `harbor.devith.it.com/deployment-pipeline`
- `registry-credentials` = Harbor username/password (for quick test `admin` is fine; for production use a robot account)

The pushed image format will be:

- `harbor.devith.it.com/deployment-pipeline/<app-name>:<build-number>-<commit-sha>`
