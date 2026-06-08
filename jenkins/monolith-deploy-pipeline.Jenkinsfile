@Library(['share_lib@master', 'a8s-sonarqube@main']) _

def notifyBackendRelease(String outcome, String statusMessageOverride = null) {
    String callbackBaseUrl = params.BACKEND_CALLBACK_URL?.trim()
    String projectId = params.PROJECT_ID?.trim()
    String releaseId = params.RELEASE_ID?.trim()

    if (!callbackBaseUrl || !projectId || !releaseId) {
        echo 'Skipping backend release callback: PROJECT_ID, RELEASE_ID, or BACKEND_CALLBACK_URL is missing.'
        return
    }

    String endpoint = outcome == 'complete' ? 'complete' : 'failed'
    Integer buildNumber = null
    try {
        buildNumber = env.BUILD_NUMBER?.trim() ? env.BUILD_NUMBER.trim().toInteger() : null
    } catch (Exception ignored) {
        buildNumber = null
    }

    String framework = env.FRAMEWORK?.trim() ?: params.FRAMEWORK?.trim() ?: ''
    String callbackTokenParam = params.CALLBACK_TOKEN?.trim() ?: ''
    String callbackUrl = "${callbackBaseUrl.replaceAll('/+$', '')}/api/v1/projects/${projectId}/releases/${releaseId}/${endpoint}"
    String callbackFile = ".a8s-release-callback-${endpoint}.json"
    String resolvedStatusMessage = outcome == 'complete'
        ? 'Deployment completed successfully'
        : (statusMessageOverride?.trim() ?: 'Jenkins pipeline failed')
    Map payload = [
        buildNumber: buildNumber,
        framework: framework,
        statusMessage: resolvedStatusMessage
    ]

    writeFile file: callbackFile, text: groovy.json.JsonOutput.toJson(payload)
    withEnv([
        "A8S_RELEASE_CALLBACK_URL=${callbackUrl}",
        "A8S_RELEASE_CALLBACK_FILE=${callbackFile}",
        "A8S_CALLBACK_TOKEN_PARAM=${callbackTokenParam}"
    ]) {
        int callbackStatus = sh(
            script: '''
                set +x
                token="${A8S_JENKINS_CALLBACK_TOKEN:-}"
                if [ -z "$token" ] && [ -n "${A8S_CALLBACK_TOKEN_PARAM:-}" ]; then
                    token="$A8S_CALLBACK_TOKEN_PARAM"
                fi
                if [ -n "$token" ]; then
                    curl -fsS -X POST "$A8S_RELEASE_CALLBACK_URL" \
                        -H 'Content-Type: application/json' \
                        -H "X-A8S-Jenkins-Callback-Token: $token" \
                        --data @"$A8S_RELEASE_CALLBACK_FILE"
                else
                    curl -fsS -X POST "$A8S_RELEASE_CALLBACK_URL" \
                        -H 'Content-Type: application/json' \
                        --data @"$A8S_RELEASE_CALLBACK_FILE"
                fi
            ''',
            returnStatus: true
        )
        if (callbackStatus != 0) {
            echo "Backend release callback failed with exit code ${callbackStatus} at ${callbackUrl}."
        } else {
            echo "Backend release callback sent: ${endpoint} framework=${framework ?: 'unknown'}."
        }
    }
}

def notifyBackendDelete(String outcome) {
    String callbackBaseUrl = params.BACKEND_CALLBACK_URL?.trim()
    String projectId = params.PROJECT_ID?.trim()

    if (!callbackBaseUrl || !projectId) {
        echo 'Skipping backend delete callback: PROJECT_ID or BACKEND_CALLBACK_URL is missing.'
        return
    }

    String endpoint = outcome == 'complete' ? 'complete' : 'failed'
    String callbackTokenParam = params.CALLBACK_TOKEN?.trim() ?: ''
    String callbackUrl = "${callbackBaseUrl.replaceAll('/+$', '')}/api/v1/projects/${projectId}/delete/${endpoint}"
    String callbackFile = ".a8s-delete-callback-${endpoint}.json"
    Map payload = [
        statusMessage: outcome == 'complete' ? 'Project cleanup completed successfully' : 'Jenkins project cleanup failed'
    ]

    writeFile file: callbackFile, text: groovy.json.JsonOutput.toJson(payload)
    withEnv([
        "A8S_DELETE_CALLBACK_URL=${callbackUrl}",
        "A8S_DELETE_CALLBACK_FILE=${callbackFile}",
        "A8S_CALLBACK_TOKEN_PARAM=${callbackTokenParam}"
    ]) {
        int callbackStatus = sh(
            script: '''
                set +x
                token="${A8S_JENKINS_CALLBACK_TOKEN:-}"
                if [ -z "$token" ] && [ -n "${A8S_CALLBACK_TOKEN_PARAM:-}" ]; then
                    token="$A8S_CALLBACK_TOKEN_PARAM"
                fi
                if [ -n "$token" ]; then
                    curl -fsS -X POST "$A8S_DELETE_CALLBACK_URL" \
                        -H 'Content-Type: application/json' \
                        -H "X-A8S-Jenkins-Callback-Token: $token" \
                        --data @"$A8S_DELETE_CALLBACK_FILE"
                else
                    curl -fsS -X POST "$A8S_DELETE_CALLBACK_URL" \
                        -H 'Content-Type: application/json' \
                        --data @"$A8S_DELETE_CALLBACK_FILE"
                fi
            ''',
            returnStatus: true
        )
        if (callbackStatus != 0) {
            echo "Backend delete callback failed with exit code ${callbackStatus} at ${callbackUrl}."
        } else {
            echo "Backend delete callback sent: ${endpoint}."
        }
    }
}

pipeline {
    agent { label 'istad' }

    options {
        timeout(time: 20, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '50'))
        skipDefaultCheckout(true)
    }

    parameters {
        string(name: 'OPERATION', defaultValue: 'deploy', description: 'deploy or delete')
        string(name: 'REPO_URL', defaultValue: '', description: 'Git repository URL from user (GitHub/GitLab)')
        string(name: 'BRANCH', defaultValue: 'main', description: 'Git branch, tag, or ref to build')
        string(name: 'USER_ID', defaultValue: '', description: 'Tenant user id')
        string(name: 'WORKSPACE_ID', defaultValue: '', description: 'Workspace namespace, for example ns-username-1234abcd')
        string(name: 'CUSTOM_DOMAIN', defaultValue: '', description: 'Optional custom host (example: app.example.com)')
        string(name: 'PROJECT_NAME', defaultValue: '', description: 'Project slug')
        string(name: 'APP_NAME', defaultValue: '', description: 'Legacy alias for PROJECT_NAME')
        string(name: 'APP_PORT', defaultValue: '3000', description: 'Container application port')
        string(name: 'FRAMEWORK', defaultValue: '', description: 'Optional framework fallback from A8S backend')
        string(name: 'IMAGE_TAG', defaultValue: '', description: 'Image tag supplied by A8S release tracking')
        string(name: 'PROJECT_ID', defaultValue: '', description: 'A8S project id for release callback')
        string(name: 'RELEASE_ID', defaultValue: '', description: 'A8S release id for release callback')
        string(name: 'BACKEND_CALLBACK_URL', defaultValue: '', description: 'A8S backend public base URL for release callback')
        string(name: 'CALLBACK_TOKEN', defaultValue: '', description: 'Legacy fallback only. Jenkins normally uses credential a8s-jenkins-callback-token.')
        text(name: 'ENV_JSON', defaultValue: '[]', description: 'Optional JSON array of runtime env vars')
        string(name: 'VAULT_ENV_PATH', defaultValue: '', description: 'Vault KV path for project secret env values')
        string(name: 'PLATFORM_DOMAIN', defaultValue: 'apps.example.com', description: 'Wildcard platform domain')
        string(name: 'GITOPS_BRANCH', defaultValue: 'main', description: 'GitOps branch to update')
        string(name: 'REGISTRY_REPOSITORY', defaultValue: 'goharbor-itp.anajak-khmer.site/deployment-pipeline', description: 'Harbor host/project for pushed images')
        string(name: 'REPO_CREDENTIALS_ID', defaultValue: '', description: 'Optional Jenkins credential id for private user repositories')
        string(name: 'SONARQUBE_SERVER_NAME', defaultValue: 'sonarqube', description: 'Jenkins SonarQube server configuration name')
        string(name: 'SONARQUBE_SCANNER_TOOL', defaultValue: '', description: 'Optional Jenkins SonarScanner tool name')
        booleanParam(name: 'ENABLE_SONARQUBE_SCAN', defaultValue: true, description: 'Run SonarQube source analysis')
        booleanParam(name: 'ENABLE_SONARQUBE_QUALITY_GATE', defaultValue: true, description: 'Wait for SonarQube quality gate before build')
        booleanParam(name: 'ENABLE_TRIVY_SCAN', defaultValue: true, description: 'Run local Trivy image scan')
        string(name: 'TRIVY_BIN', defaultValue: 'trivy', description: 'Trivy executable name or absolute path on the Jenkins agent')
        string(name: 'TRIVY_REPORT_SEVERITY', defaultValue: 'HIGH,CRITICAL', description: 'Severities included in Trivy report artifacts')
        string(name: 'TRIVY_GATE_SEVERITY', defaultValue: 'CRITICAL', description: 'Severities that should fail the deployment gate')
        string(name: 'TRIVY_GATE_EXIT_CODE', defaultValue: '1', description: 'Trivy gate exit code (1=enforce gate, 0=report-only)')
        booleanParam(name: 'UPLOAD_DEFECTDOJO', defaultValue: true, description: 'Upload monolithic deploy Trivy report to DefectDojo')
        string(name: 'DEFECTDOJO_URL', defaultValue: 'https://defetchdojo.anajak-khmer.site', description: 'DefectDojo base URL')
        string(name: 'DEFECTDOJO_CREDENTIALS_ID', defaultValue: 'DEFECTDOJO', description: 'Jenkins secret text credential id containing a DefectDojo API token')
        string(name: 'DEFECTDOJO_PRODUCT_TYPE_NAME', defaultValue: 'Web Applications', description: 'DefectDojo product type name used when auto-creating products')
        string(name: 'DEFECTDOJO_PRODUCT_NAME', defaultValue: '', description: 'DefectDojo product name. Defaults to PROJECT_NAME.')
        booleanParam(name: 'ENABLE_GITOPS_UPDATE', defaultValue: true, description: 'Update GitOps repository after push')
    }

    environment {
        INFRA_REPO_URL = credentials('infra-repo-url')
        GITOPS_REPO_URL = credentials('gitops-repo-url')
        A8S_JENKINS_CALLBACK_TOKEN = credentials('a8s-jenkins-callback-token')
    }

    stages {
        stage('Prepare workspace') {
            steps {
                sh '''
                    set +e
                    if [ -d "$WORKSPACE/trivy-cache" ]; then
                        echo "[workspace] Removing stale Trivy cache from previous builds."
                        rm -rf "$WORKSPACE/trivy-cache" 2>/dev/null
                    fi
                    if [ -d "$WORKSPACE/trivy-cache" ] && command -v docker >/dev/null 2>&1; then
                        docker run --rm \
                            -v "$WORKSPACE:/workspace" \
                            --entrypoint /bin/sh \
                            aquasec/trivy:latest \
                            -c 'rm -rf /workspace/trivy-cache' || true
                    fi
                    if [ -d "$WORKSPACE/trivy-cache" ]; then
                        echo "[workspace] Stale Trivy cache still exists; future cleanup will ignore it."
                    fi
                '''
            }
        }

        stage('Validate input') {
            steps {
                script {
                    String operation = params.OPERATION?.trim() ?: 'deploy'
                    if (!(operation in ['deploy', 'delete'])) {
                        error("monolith-deploy-pipeline only supports OPERATION=deploy or OPERATION=delete, got ${operation}")
                    }
                    env.EFFECTIVE_OPERATION = operation
                    boolean deleteMode = operation == 'delete'
                    if (!deleteMode && !params.REPO_URL?.trim()) {
                        error('REPO_URL is required')
                    }
                    if (!params.USER_ID?.trim()) {
                        error('USER_ID is required')
                    }
                    env.EFFECTIVE_WORKSPACE_ID = params.WORKSPACE_ID?.trim()
                    if (!env.EFFECTIVE_WORKSPACE_ID) {
                        error('WORKSPACE_ID is required and must be the workspace namespace, for example ns-username-1234abcd')
                    }
                    env.EFFECTIVE_PROJECT_NAME = params.PROJECT_NAME?.trim() ? params.PROJECT_NAME.trim() : params.APP_NAME?.trim()
                    if (!env.EFFECTIVE_PROJECT_NAME) {
                        error('PROJECT_NAME (or APP_NAME) is required')
                    }
                    if (!deleteMode && !(params.APP_PORT ==~ /^\d+$/)) {
                        error('APP_PORT must be numeric')
                    }
                    if (!deleteMode && !(params.TRIVY_GATE_EXIT_CODE ==~ /^\d+$/)) {
                        error('TRIVY_GATE_EXIT_CODE must be numeric, normally 0 or 1')
                    }

                    env.SAFE_USER_ID = sh(
                        script: '''echo "$USER_ID" | tr '[:upper:]' '[:lower:]' | sed -E "s/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g" | cut -c1-30''',
                        returnStdout: true
                    ).trim()
                    env.SAFE_WORKSPACE_ID = sh(
                        script: '''echo "$EFFECTIVE_WORKSPACE_ID" | tr '[:upper:]' '[:lower:]' | sed -E "s/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g" | cut -c1-63''',
                        returnStdout: true
                    ).trim()
                    env.SAFE_PROJECT_NAME = sh(
                        script: '''echo "$EFFECTIVE_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed -E "s/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g" | cut -c1-40''',
                        returnStdout: true
                    ).trim()

                    def normalizedRegistry = (params.REGISTRY_REPOSITORY?.trim() ?: 'goharbor-itp.anajak-khmer.site/deployment-pipeline')
                        .replaceFirst(/^https?:\/\//, '')
                        .replaceAll(/\/+$/, '')
                    if (!normalizedRegistry.contains('/')) {
                        error('REGISTRY_REPOSITORY must include registry host and Harbor project (example: goharbor-itp.anajak-khmer.site/deployment-pipeline)')
                    }
                    env.EFFECTIVE_REGISTRY_REPOSITORY = normalizedRegistry

                    env.NORMALIZED_REGISTRY_REPOSITORY = env.EFFECTIVE_REGISTRY_REPOSITORY
                    env.REGISTRY_LOGIN_SERVER = env.EFFECTIVE_REGISTRY_REPOSITORY.split('/')[0]
                    env.IMAGE_REPOSITORY = "${env.NORMALIZED_REGISTRY_REPOSITORY}/${env.SAFE_USER_ID}/${env.SAFE_PROJECT_NAME}"
                    env.IMAGE_FULL = deleteMode ? "(delete ${env.IMAGE_REPOSITORY})" : ''

                    echo "OPERATION=${env.EFFECTIVE_OPERATION} | ENABLE_GITOPS_UPDATE=${params.ENABLE_GITOPS_UPDATE} | GITOPS_BRANCH=${params.GITOPS_BRANCH} | WORKSPACE_ID=${env.EFFECTIVE_WORKSPACE_ID}"
                }
            }
        }

        stage('Checkout infra') {
            steps {
                dir('platform-infra') {
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: '*/main']],
                        userRemoteConfigs: [[url: env.INFRA_REPO_URL]]
                    ])
                }
            }
        }

        stage('Checkout user repository') {
            when {
                expression { return env.EFFECTIVE_OPERATION != 'delete' }
            }
            steps {
                dir('user-app') {
                    script {
                        deleteDir()
                        env.NORMALIZED_REPO_URL = params.REPO_URL
                        if (params.REPO_URL?.contains('%')) {
                            try {
                                env.NORMALIZED_REPO_URL = java.net.URLDecoder.decode(params.REPO_URL, 'UTF-8')
                            } catch (Exception ignored) {
                                echo 'Could not decode REPO_URL, using original value.'
                            }
                        }

                        if (params.REPO_CREDENTIALS_ID?.trim()) {
                            checkout([
                                $class: 'GitSCM',
                                branches: [[name: "*/${params.BRANCH}"]],
                                userRemoteConfigs: [[
                                    url: env.NORMALIZED_REPO_URL,
                                    credentialsId: params.REPO_CREDENTIALS_ID
                                ]]
                            ])
                        } else {
                            git url: env.NORMALIZED_REPO_URL, branch: params.BRANCH
                        }

                        env.APP_COMMIT_SHA = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
                        env.NORMALIZED_REGISTRY_REPOSITORY = env.EFFECTIVE_REGISTRY_REPOSITORY
                        env.IMAGE_TAG = params.IMAGE_TAG?.trim() ?: "${env.SAFE_USER_ID}-${env.BUILD_NUMBER}-${env.APP_COMMIT_SHA}"
                        env.IMAGE_REPOSITORY = "${env.NORMALIZED_REGISTRY_REPOSITORY}/${env.SAFE_USER_ID}/${env.SAFE_PROJECT_NAME}"
                        env.IMAGE_FULL = "${env.IMAGE_REPOSITORY}:${env.IMAGE_TAG}"
                        env.REGISTRY_LOGIN_SERVER = env.EFFECTIVE_REGISTRY_REPOSITORY.split('/')[0]

                        echo "Resolved image: ${env.IMAGE_FULL}"
                    }
                }
            }
        }

        stage('Detect framework') {
            when {
                expression { return env.EFFECTIVE_OPERATION != 'delete' }
            }
            steps {
                dir('user-app') {
                    script {
                        String scriptsDir = sh(
                            script: '''
                                set -e
                                for d in "$WORKSPACE/platform-infra/jenkins/scripts" "$WORKSPACE/plateform-infra/jenkins/scripts"; do
                                    if [ -f "$d/detect-framework.sh" ]; then
                                        echo "$d"
                                        exit 0
                                    fi
                                done
                                echo "ERROR: detect-framework.sh not found in expected infra directories." >&2
                                ls -la "$WORKSPACE" >&2 || true
                                exit 1
                            ''',
                            returnStdout: true
                        ).trim()
                        String detectedFramework = sh(
                            script: "bash '${scriptsDir}/detect-framework.sh'",
                            returnStdout: true
                        ).trim()
                        env.FRAMEWORK = detectedFramework ?: params.FRAMEWORK?.trim()
                        echo "Detected framework: ${env.FRAMEWORK}"
                    }
                }
            }
        }

        stage('SonarQube Analysis') {
            when {
                expression { return env.EFFECTIVE_OPERATION != 'delete' && params.ENABLE_SONARQUBE_SCAN }
            }
            steps {
                dir('user-app') {
                    script {
                        a8sSonarScan(
                            server: params.SONARQUBE_SERVER_NAME?.trim() ?: 'sonarqube',
                            scannerTool: params.SONARQUBE_SCANNER_TOOL?.trim(),
                            projectKey: "${env.SAFE_WORKSPACE_ID}-${env.SAFE_PROJECT_NAME}",
                            projectName: env.EFFECTIVE_PROJECT_NAME,
                            projectVersion: env.APP_COMMIT_SHA,
                            sources: '.',
                            exclusions: '**/node_modules/**,**/.next/**,**/dist/**,**/build/**,**/target/**,**/vendor/**,**/.git/**'
                        )
                    }
                }
            }
        }

        stage('SonarQube Quality Gate') {
            when {
                expression { return env.EFFECTIVE_OPERATION != 'delete' && params.ENABLE_SONARQUBE_SCAN && params.ENABLE_SONARQUBE_QUALITY_GATE }
            }
            steps {
                a8sSonarQualityGate(timeoutMinutes: 5, abortPipeline: true)
            }
        }

        stage('Prepare Dockerfile') {
            when {
                expression { return env.EFFECTIVE_OPERATION != 'delete' }
            }
            steps {
                dir('user-app') {
                    sh '''
                        SCRIPTS_DIR=""
                        for d in "$WORKSPACE/platform-infra/jenkins/scripts" "$WORKSPACE/plateform-infra/jenkins/scripts"; do
                            if [ -f "$d/generate-dockerfile.sh" ]; then
                                SCRIPTS_DIR="$d"
                                break
                            fi
                        done
                        if [ -z "$SCRIPTS_DIR" ]; then
                            echo "ERROR: generate-dockerfile.sh not found in expected infra directories."
                            ls -la "$WORKSPACE" || true
                            exit 1
                        fi

                        case "$FRAMEWORK" in
                          springboot-*)
                            echo "Using platform-managed Spring Boot Dockerfile template."
                            FORCE_PLATFORM_DOCKERFILE=true bash "${SCRIPTS_DIR}/generate-dockerfile.sh" "${FRAMEWORK}" "${SCRIPTS_DIR}"
                            ;;
                          *)
                            if [ -f Dockerfile ]; then
                                echo "Using user-provided Dockerfile."
                            else
                                echo "Generating Dockerfile from platform template."
                                bash "${SCRIPTS_DIR}/generate-dockerfile.sh" "${FRAMEWORK}" "${SCRIPTS_DIR}"
                            fi
                            ;;
                        esac
                    '''
                }
            }
        }

        stage('Build, Scan, Push') {
            when {
                expression { return env.EFFECTIVE_OPERATION != 'delete' }
            }
            agent { label 'istad' }
            steps {
                script {
                    dir('platform-infra') {
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: '*/main']],
                            userRemoteConfigs: [[url: env.INFRA_REPO_URL]]
                        ])
                    }

                    dir('user-app') {
                        deleteDir()
                        if (params.REPO_CREDENTIALS_ID?.trim()) {
                            checkout([
                                $class: 'GitSCM',
                                branches: [[name: "*/${params.BRANCH}"]],
                                userRemoteConfigs: [[
                                    url: env.NORMALIZED_REPO_URL,
                                    credentialsId: params.REPO_CREDENTIALS_ID
                                ]]
                            ])
                        } else {
                            git url: env.NORMALIZED_REPO_URL, branch: params.BRANCH
                        }

                        sh '''
                            SCRIPTS_DIR=""
                            for d in "$WORKSPACE/platform-infra/jenkins/scripts" "$WORKSPACE/plateform-infra/jenkins/scripts"; do
                                if [ -f "$d/generate-dockerfile.sh" ]; then
                                    SCRIPTS_DIR="$d"
                                    break
                                fi
                            done
                            if [ -z "$SCRIPTS_DIR" ]; then
                                echo "ERROR: generate-dockerfile.sh not found in expected infra directories."
                                ls -la "$WORKSPACE" || true
                                exit 1
                            fi

                            case "$FRAMEWORK" in
                              springboot-*)
                                FORCE_PLATFORM_DOCKERFILE=true bash "${SCRIPTS_DIR}/generate-dockerfile.sh" "${FRAMEWORK}" "${SCRIPTS_DIR}"
                                ;;
                              *)
                                if [ ! -f Dockerfile ]; then
                                    bash "${SCRIPTS_DIR}/generate-dockerfile.sh" "${FRAMEWORK}" "${SCRIPTS_DIR}"
                                fi
                                ;;
                            esac

                            echo "[build] Starting docker build for ${IMAGE_FULL}"
                            docker build --pull --progress=plain --provenance=false -t "$IMAGE_FULL" .
                            echo "[build] Docker build completed"
                        '''
                    }

                    if (params.ENABLE_TRIVY_SCAN) {
                        echo "[scan] Starting Trivy scan for ${env.IMAGE_FULL}"
                        sh '''
                            set -eu
                            TRIVY_REPORT_SEVERITY_VALUE="${TRIVY_REPORT_SEVERITY:-HIGH,CRITICAL}"
                            TRIVY_GATE_SEVERITY_VALUE="${TRIVY_GATE_SEVERITY:-CRITICAL}"
                            TRIVY_GATE_EXIT_CODE_VALUE="${TRIVY_GATE_EXIT_CODE:-1}"
                            echo "[scan] report severity: ${TRIVY_REPORT_SEVERITY_VALUE} | gate severity: ${TRIVY_GATE_SEVERITY_VALUE} | gate exit code: ${TRIVY_GATE_EXIT_CODE_VALUE}"
                            mkdir -p trivy-reports
                            cat > trivy-reports/run-trivy <<'TRIVY_RUNNER'
#!/bin/sh
set -eu
TRIVY_CMD="${TRIVY_BIN:-trivy}"
if command -v "$TRIVY_CMD" >/dev/null 2>&1; then
    exec "$(command -v "$TRIVY_CMD")" "$@"
elif [ -x "$TRIVY_CMD" ]; then
    exec "$TRIVY_CMD" "$@"
elif [ -x /usr/local/bin/trivy ]; then
    exec /usr/local/bin/trivy "$@"
elif [ -x /usr/bin/trivy ]; then
    exec /usr/bin/trivy "$@"
elif [ -x /snap/bin/trivy ]; then
    exec /snap/bin/trivy "$@"
elif [ -x /home/istad/bin/trivy ]; then
    exec /home/istad/bin/trivy "$@"
elif [ -x /home/istad/.local/bin/trivy ]; then
    exec /home/istad/.local/bin/trivy "$@"
elif command -v docker >/dev/null 2>&1; then
    TRIVY_CACHE_ROOT="${TRIVY_CACHE_DIR:-${TMPDIR:-/tmp}/a8s-trivy-cache/${JOB_NAME:-jenkins}}"
    mkdir -p "$TRIVY_CACHE_ROOT"
    exec docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$PWD:$PWD" \
        -w "$PWD" \
        -v "$TRIVY_CACHE_ROOT:/tmp/trivy-cache" \
        aquasec/trivy:latest --cache-dir /tmp/trivy-cache "$@"
else
    echo "ERROR: Trivy was not found on this Jenkins agent and Docker fallback is unavailable."
    echo "Agent: ${NODE_NAME:-unknown}"
    echo "PATH: ${PATH:-}"
    echo "Install Trivy on the istad agent, set TRIVY_BIN, or allow Docker to run aquasec/trivy:latest."
    exit 127
fi
TRIVY_RUNNER
                            chmod +x trivy-reports/run-trivy
                            TRIVY_CONFIGURED_BIN="${TRIVY_BIN:-trivy}"
                            if command -v "$TRIVY_CONFIGURED_BIN" >/dev/null 2>&1 \
                                || [ -x "$TRIVY_CONFIGURED_BIN" ] \
                                || [ -x /usr/local/bin/trivy ] \
                                || [ -x /usr/bin/trivy ] \
                                || [ -x /snap/bin/trivy ] \
                                || [ -x /home/istad/bin/trivy ] \
                                || [ -x /home/istad/.local/bin/trivy ]; then
                                echo "[scan] Using host Trivy executable."
                            else
                                echo "[scan] Host Trivy not found; using Docker image aquasec/trivy:latest."
                            fi
                            ./trivy-reports/run-trivy --version
                            ./trivy-reports/run-trivy image \
                                --format json \
                                --output trivy-reports/trivy-report.json \
                                --severity "${TRIVY_REPORT_SEVERITY_VALUE}" \
                                --exit-code 0 \
                                "$IMAGE_FULL"
                            ./trivy-reports/run-trivy image \
                                --format table \
                                --output trivy-reports/trivy-report.txt \
                                --severity "${TRIVY_REPORT_SEVERITY_VALUE}" \
                                --exit-code 0 \
                                "$IMAGE_FULL" || true
                        '''
                        archiveArtifacts artifacts: 'trivy-reports/*', fingerprint: true, allowEmptyArchive: true
                        if (params.UPLOAD_DEFECTDOJO) {
                            catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                                withCredentials([string(credentialsId: params.DEFECTDOJO_CREDENTIALS_ID?.trim() ?: 'DEFECTDOJO', variable: 'DEFECTDOJO_TOKEN')]) {
                                    sh '''
                                        set -eu
                                        PRODUCT_NAME="${DEFECTDOJO_PRODUCT_NAME:-${WORKSPACE_ID}-${EFFECTIVE_PROJECT_NAME}}"
                                        PRODUCT_TYPE_NAME="${DEFECTDOJO_PRODUCT_TYPE_NAME:-Web Applications}"
                                        DEFECTDOJO_BASE_URL="${DEFECTDOJO_URL:-https://defetchdojo.anajak-khmer.site}"
                                        RESPONSE_FILE="$(mktemp)"
                                        echo "[defectdojo] Uploading Trivy report for ${PRODUCT_NAME}"
                                        HTTP_CODE="$(curl -sS -o "${RESPONSE_FILE}" -w "%{http_code}" -X POST "${DEFECTDOJO_BASE_URL%/}/api/v2/import-scan/" \
                                            -H "Authorization: Token ${DEFECTDOJO_TOKEN}" \
                                            -F "scan_type=Trivy Scan" \
                                            -F "file=@trivy-reports/trivy-report.json" \
                                            -F "product_type_name=${PRODUCT_TYPE_NAME}" \
                                            -F "product_name=${PRODUCT_NAME}" \
                                            -F "engagement_name=Jenkins-${BUILD_NUMBER}" \
                                            -F "test_title=Trivy Image Scan - ${IMAGE_TAG}" \
                                            -F "minimum_severity=Info" \
                                            -F "auto_create_context=true" \
                                            -F "active=true" \
                                            -F "verified=true")"
                                        if [ "${HTTP_CODE}" -lt 200 ] || [ "${HTTP_CODE}" -ge 300 ]; then
                                            echo "[defectdojo] Upload failed with HTTP ${HTTP_CODE}"
                                            cat "${RESPONSE_FILE}"
                                            exit 1
                                        fi
                                        cat "${RESPONSE_FILE}"
                                        echo "[defectdojo] Upload completed"
                                    '''
                                }
                            }
                        } else {
                            echo "[scan] DefectDojo upload disabled for monolithic deploy scan."
                        }
                        String trivyFailureSummary = sh(
                            script: '''
                                set -eu
                                if [ ! -f trivy-reports/trivy-report.txt ]; then
                                    printf '0|'
                                    exit 0
                                fi

                                CRITICAL_COUNT="$(sed -nE 's/^Total:[[:space:]]+[0-9]+[[:space:]]+\\(CRITICAL:[[:space:]]*([0-9]+)\\).*/\\1/p' trivy-reports/trivy-report.txt | head -n1)"
                                if [ -z "${CRITICAL_COUNT}" ]; then
                                    CRITICAL_COUNT="0"
                                fi

                                CVE_LIST="$(grep -Eo 'CVE-[0-9]{4}-[0-9]+' trivy-reports/trivy-report.txt | sort -u | head -n 3 | tr '\\n' ',' | sed 's/,$//')"
                                printf '%s|%s' "${CRITICAL_COUNT}" "${CVE_LIST}"
                            ''',
                            returnStdout: true
                        ).trim()

                        String[] trivyParts = trivyFailureSummary.split('\\|', 2)
                        int trivyCriticalCount = 0
                        try {
                            trivyCriticalCount = trivyParts[0]?.trim() ? trivyParts[0].trim().toInteger() : 0
                        } catch (Exception ignored) {
                            trivyCriticalCount = 0
                        }
                        if (trivyCriticalCount > 0) {
                            String vulnerabilityWord = trivyCriticalCount == 1 ? 'vulnerability' : 'vulnerabilities'
                            String cveList = trivyParts.length > 1 ? trivyParts[1].trim() : ''
                            String cveSuffix = cveList ? " (${cveList})" : ''
                            env.DEPLOY_FAILURE_REASON = "Deployment blocked by Trivy security gate: ${trivyCriticalCount} CRITICAL ${vulnerabilityWord} detected${cveSuffix}."
                        }
                        sh '''
                            set -eu
                            TRIVY_GATE_SEVERITY_VALUE="${TRIVY_GATE_SEVERITY:-CRITICAL}"
                            TRIVY_GATE_EXIT_CODE_VALUE="${TRIVY_GATE_EXIT_CODE:-1}"
                            ./trivy-reports/run-trivy image \
                                --format table \
                                --severity "${TRIVY_GATE_SEVERITY_VALUE}" \
                                --exit-code "${TRIVY_GATE_EXIT_CODE_VALUE}" \
                                "$IMAGE_FULL"
                        '''
                    }

                    withCredentials([usernamePassword(
                        credentialsId: 'registry-credentials',
                        usernameVariable: 'REGISTRY_USERNAME',
                        passwordVariable: 'REGISTRY_PASSWORD'
                    )]) {
                        sh '''
                            echo "[push] Pushing image ${IMAGE_FULL}"
                            echo "${REGISTRY_PASSWORD}" | docker login "${REGISTRY_LOGIN_SERVER}" \
                                -u "${REGISTRY_USERNAME}" --password-stdin
                            docker push "${IMAGE_FULL}"
                            echo "[push] Image push completed"
                        '''
                    }
                }
            }
        }

        stage('Update GitOps repository') {
            when {
                expression { return params.ENABLE_GITOPS_UPDATE }
            }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'gitops-ssh', keyFileVariable: 'SSH_KEY')]) {
                    sh '''
                        SCRIPTS_DIR=""
                        INFRA_BASE_DIR=""
                        for base in "$WORKSPACE/platform-infra" "$WORKSPACE/plateform-infra"; do
                            if [ -f "$base/jenkins/scripts/update-gitops.sh" ]; then
                                SCRIPTS_DIR="$base/jenkins/scripts"
                                INFRA_BASE_DIR="$base"
                                break
                            fi
                        done
                        if [ -z "$SCRIPTS_DIR" ]; then
                            echo "ERROR: update-gitops.sh not found in expected infra directories."
                            ls -la "$WORKSPACE" || true
                            exit 1
                        fi

                        bash "${SCRIPTS_DIR}/update-gitops.sh" \
                            --operation "${EFFECTIVE_OPERATION}" \
                            --gitops-repo "${GITOPS_REPO_URL}" \
                            --gitops-branch "${GITOPS_BRANCH}" \
                            --ssh-key "${SSH_KEY}" \
                            --workspace-id "${EFFECTIVE_WORKSPACE_ID}" \
                            --user-id "${USER_ID}" \
                            --project-name "${EFFECTIVE_PROJECT_NAME}" \
                            --custom-domain "${CUSTOM_DOMAIN}" \
                            --image-repository "${IMAGE_REPOSITORY}" \
                            --image-tag "${IMAGE_TAG}" \
                            --app-port "${APP_PORT}" \
                            --env-json "${ENV_JSON}" \
                            --vault-env-path "${VAULT_ENV_PATH}" \
                            --platform-domain "${PLATFORM_DOMAIN}" \
                            --framework "${FRAMEWORK}" \
                            --commit-sha "${APP_COMMIT_SHA}" \
                            --build-number "${BUILD_NUMBER}" \
                            --chart-source "${INFRA_BASE_DIR}/helm/app-template"
                    '''
                }
            }
        }

        stage('Delete Harbor repository') {
            when {
                expression { return env.EFFECTIVE_OPERATION == 'delete' }
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'registry-credentials',
                    usernameVariable: 'REGISTRY_USERNAME',
                    passwordVariable: 'REGISTRY_PASSWORD'
                )]) {
                    sh '''
                        set -eu
                        HARBOR_HOST="${REGISTRY_LOGIN_SERVER}"
                        HARBOR_PROJECT="${NORMALIZED_REGISTRY_REPOSITORY#*/}"
                        HARBOR_REPOSITORY="${SAFE_USER_ID}/${SAFE_PROJECT_NAME}"
                        ENCODED_REPOSITORY="${SAFE_USER_ID}%252F${SAFE_PROJECT_NAME}"
                        URL="https://${HARBOR_HOST}/api/v2.0/projects/${HARBOR_PROJECT}/repositories/${ENCODED_REPOSITORY}"
                        echo "[harbor] Deleting repository ${HARBOR_PROJECT}/${HARBOR_REPOSITORY}"
                        HTTP_CODE="$(curl -sS -o /tmp/a8s-harbor-delete.out -w '%{http_code}' \
                            -u "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" \
                            -X DELETE "${URL}")"
                        if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "202" ] || [ "${HTTP_CODE}" = "204" ] || [ "${HTTP_CODE}" = "404" ]; then
                            echo "[harbor] Delete accepted with HTTP ${HTTP_CODE}"
                            exit 0
                        fi
                        echo "[harbor] Delete failed with HTTP ${HTTP_CODE}"
                        cat /tmp/a8s-harbor-delete.out || true
                        exit 1
                    '''
                }
            }
        }
    }

    post {
        success {
            script {
                if (env.EFFECTIVE_OPERATION == 'delete') {
                    echo "Project removal completed for ${env.EFFECTIVE_PROJECT_NAME}."
                    notifyBackendDelete('complete')
                } else {
                    echo "Deployment requested successfully for ${env.EFFECTIVE_PROJECT_NAME}."
                    echo "Image: ${env.IMAGE_FULL}"
                    String customDomain = params.CUSTOM_DOMAIN?.trim()
                    String expectedHost = customDomain ?: "${env.SAFE_PROJECT_NAME}-${env.SAFE_WORKSPACE_ID}.${params.PLATFORM_DOMAIN}"
                    echo "Expected URL: https://${expectedHost}"
                    notifyBackendRelease('complete')
                }
            }
        }
        failure {
            echo 'Deployment failed. Check stage logs for details.'
            script {
                if (env.EFFECTIVE_OPERATION == 'delete') {
                    notifyBackendDelete('failed')
                } else {
                    notifyBackendRelease('failed', env.DEPLOY_FAILURE_REASON)
                }
            }
        }
        always {
            script {
                node('istad') {
                    sh '''
                        set +e
                        if [ -d "$WORKSPACE/trivy-cache" ]; then
                            rm -rf "$WORKSPACE/trivy-cache" 2>/dev/null
                        fi
                        if [ -d "$WORKSPACE/trivy-cache" ] && command -v docker >/dev/null 2>&1; then
                            docker run --rm \
                                -v "$WORKSPACE:/workspace" \
                                --entrypoint /bin/sh \
                                aquasec/trivy:latest \
                                -c 'rm -rf /workspace/trivy-cache' || true
                        fi
                    '''
                    cleanWs(deleteDirs: true, disableDeferredWipeout: true, notFailBuild: true)
                }
            }
        }
    }
}
