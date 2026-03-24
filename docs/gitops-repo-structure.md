# GitOps Repository Structure

```text
plateform-gitops/
  bootstrap/
    argocd-app-of-apps.yaml
    applicationset-user-projects.yaml
    namespace.yaml
  apps/
    <userId>/
      namespace.yaml
      <projectName>/
        Chart.yaml
        values.yaml              # Jenkins updates image.tag only
        templates/
          _helpers.tpl
          deployment.yaml
          service.yaml
          ingress.yaml
          hpa.yaml
```

## Rules

- `apps/<userId>/<projectName>/` is the deployment contract path.
- `values.yaml` carries tenant metadata and image coordinates.
- Every deploy writes a single Git commit for version traceability.
