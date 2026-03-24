# Deployment Flow

1. User connects Git repository from dashboard/CLI.
2. Platform backend stores project metadata and webhook secret.
3. Push event arrives from GitHub/GitLab webhook.
4. Backend validates signature and creates deployment record (`BUILDING`).
5. Backend triggers Jenkins generic pipeline with project parameters.
6. Jenkins clones user repo and detects framework automatically.
7. Jenkins uses user Dockerfile if present, otherwise generates from templates.
8. Jenkins builds and tags image:
   - `<userId>-<buildNumber>-<commitSHA>`
9. Jenkins pushes image to registry.
10. Jenkins updates GitOps repo at `apps/<userId>/<projectName>/values.yaml`.
11. Only `image.tag` changes for each deploy (version history via Git commit).
12. ArgoCD ApplicationSet detects GitOps commit and syncs automatically.
13. Kubernetes rolls out updated Deployment in `user-<userId>` namespace.
14. App is served via Ingress:
   - `https://<projectName>.<platformDomain>`
15. Backend/UI expose deployment history and allow rollback.

## Rollback Flow

1. User selects target deployment version.
2. Backend creates a rollback deployment record.
3. Backend updates GitOps `image.tag` to target version.
4. ArgoCD syncs and Kubernetes rolls back to the selected image.
5. Deployment history shows rollback event with references.
