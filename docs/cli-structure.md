# CLI Structure (Go)

## Commands

- `a8s deploy`
  - Trigger deployment for current repository or explicit repo input
- `a8s logs --deployment-id <id> [--follow]`
  - Read deployment logs from backend
- `a8s rollback --deployment-id <id> --target-deployment-id <id>`
  - Roll back deployment by resetting GitOps image tag

## Internal package layout

```text
a8s-cli/
  main.go
  internal/
    cli/
      deploy.go
      logs.go
      rollback.go
      run.go
    api/
      client.go
    config/
      config.go
    types/
      types.go
```

## Auth

- Uses stored backend token from local config.
- Supports login flow and non-interactive command execution.
