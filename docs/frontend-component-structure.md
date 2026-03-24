# Frontend Component Structure (React + Tailwind)

```text
src/
  app/
    dashboard/
      page.tsx                 # summary cards + recent deployments
      projects/page.tsx        # project table + domain preview
      deployments/[id]/page.tsx
      logs/[deploymentId]/page.tsx
  components/
    projects/
      ProjectCard.tsx
      ProjectForm.tsx
      RepoConnectModal.tsx
    deployments/
      DeploymentTimeline.tsx
      DeploymentStatusBadge.tsx
      RollbackModal.tsx
    logs/
      LogsViewer.tsx           # WebSocket stream renderer
      LogFilterBar.tsx
    shared/
      Header.tsx
      Sidebar.tsx
      EmptyState.tsx
      LoadingState.tsx
  lib/
    api.ts                     # typed backend API client
    ws.ts                      # websocket helper (reconnect/backoff)
  store/
    projectSlice.ts
    deploymentSlice.ts
    logSlice.ts
```

## UX requirements covered

- Project management and repository connection
- Deployment history with status badges
- Live logs viewer via WebSocket
- Domain preview for each project (`https://{project}.{domain}`)
- Rollback action from deployment detail/timeline
