# Backend API Design (FastAPI)

## Core routes

- `POST /api/v1/projects`
  - Create project and assign isolated namespace (`user-{userId}`)
- `PUT /api/v1/projects/{projectId}/repository`
  - Connect/replace repository and webhook secret
- `GET /api/v1/projects`
  - List projects for authenticated user
- `POST /api/v1/projects/{projectId}/deploy`
  - Trigger Jenkins generic pipeline and create deployment row
- `GET /api/v1/projects/{projectId}/deployments`
  - List deployment history for project
- `POST /api/v1/deployments/{deploymentId}/rollback`
  - Rollback by setting GitOps image tag to target deployment tag
- `GET /api/v1/deployments/{deploymentId}/logs`
  - Fetch persisted logs
- `POST /api/v1/webhooks/github`
  - Validate `X-Hub-Signature-256`, process push event
- `POST /api/v1/webhooks/gitlab`
  - Validate `X-Gitlab-Token`, process push event
- `WS /ws/projects/{projectId}/deployments/{deploymentId}/logs`
  - Stream logs to dashboard in near real time

## Data models

- `users`
  - tenant identity
- `projects`
  - repository linkage, namespace, domain, runtime metadata
- `deployments`
  - immutable version records (image tag, commit SHA, rollback references)
- `deployment_logs`
  - line-oriented Jenkins/build logs for debugging and UI streaming
- `webhook_events`
  - raw webhook audit trail and processing outcomes

## File references

- API routes: `platform-backend-fastapi/app/api/routes/`
- SQLAlchemy models: `platform-backend-fastapi/app/models/`
- SQL schema: `platform-backend-fastapi/schema.sql`
