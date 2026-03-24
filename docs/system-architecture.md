# System Architecture (Text Diagram)

```text
                       +-----------------------------+
                       |        React Dashboard      |
                       |  Projects / Logs / Rollback |
                       +--------------+--------------+
                                      |
                                      | HTTPS + WebSocket
                                      v
+----------------------+     +--------+---------+      +---------------------+
|      A8S CLI (Go)    +---->+   Backend API    +----->+    PostgreSQL DB     |
| deploy/logs/rollback |     |  FastAPI (stateless)   |  users/projects/...  |
+----------+-----------+     +----+-----------+--+      +---------------------+
           |                      |           |
           |                      |           +----------------------------+
           |                      |                                        |
           |                      v                                        v
           |              +-------+--------+                       +-------+--------+
           |              | Jenkins API    |                       | Webhook Handler |
           |              | Generic Job    |<-- GitHub/GitLab ----+ Signature Check |
           |              +-------+--------+                       +-------+--------+
           |                      |
           |                      | build image + push
           |                      v
           |              +-------+--------+
           +------------->+ Container       |
                          | Registry        |
                          +-------+--------+
                                  |
                                  | update values.yaml (image tag)
                                  v
                          +-------+--------+
                          |  GitOps Repo   |
                          | apps/{user}/{project}
                          +-------+--------+
                                  |
                                  | auto-sync
                                  v
                          +-------+--------+
                          |    ArgoCD      |
                          | ApplicationSet |
                          +-------+--------+
                                  |
                                  | deploy to namespace user-{userId}
                                  v
                          +-------+--------+
                          |   Kubernetes    |
                          | Deployment/Svc/ |
                          | Ingress/HPA     |
                          +-----------------+
```
