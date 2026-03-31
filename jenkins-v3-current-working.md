@Library('share_lib@master') _

pipeline {
    agent any

    options {
        timeout(time: 20, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '50'))
        // ansiColor('xterm')
    }

    parameters {
        string(name: 'REPO_URL', defaultValue: '', description: 'Git repository URL from user (GitHub/GitLab)')
        string(name: 'BRANCH', defaultValue: 'main', description: 'Git branch to build')
        string(name: 'USER_ID', defaultValue: '', description: 'Tenant user id')
        string(name: 'PROJECT_NAME', defaultValue: '', description: 'Project slug')
        string(name: 'APP_NAME', defaultValue: '', description: 'Legacy alias for PROJECT_NAME')
        string(name: 'APP_PORT', defaultValue: '3000', description: 'Container application port')
        string(name: 'PLATFORM_DOMAIN', defaultValue: 'apps.example.com', description: 'Wildcard platform domain')
        string(name: 'GITOPS_BRANCH', defaultValue: 'main', description: 'GitOps branch to update')
        string(name: 'REPO_CREDENTIALS_ID', defaultValue: '', description: 'Optional Jenkins credential id for private user repositories')
        booleanParam(name: 'ENABLE_TRIVY_SCAN', defaultValue: true, description: 'Run local Trivy image scan')
        booleanParam(name: 'ENABLE_GITOPS_UPDATE', defaultValue: false, description: 'Update GitOps repository after push')
    }

    environment {
        INFRA_REPO_URL = credentials('infra-repo-url')
        REGISTRY_REPOSITORY = credentials('registry-repository')
        GITOPS_REPO_URL = credentials('gitops-repo-url')
        SCRIPTS_DIR = "${WORKSPACE}/platform-infra/jenkins/scripts"
        HELM_CHART_SOURCE = "${WORKSPACE}/platform-infra/helm/app-template"
    }

    stages {
        stage('Validate input') {
            steps {
                script {
                    if (!params.REPO_URL?.trim()) {
                        error('REPO_URL is required')
                    }
                    if (!params.USER_ID?.trim()) {
                        error('USER_ID is required')
                    }
                    env.EFFECTIVE_PROJECT_NAME = params.PROJECT_NAME?.trim() ? params.PROJECT_NAME.trim() : params.APP_NAME?.trim()
                    if (!env.EFFECTIVE_PROJECT_NAME) {
                        error('PROJECT_NAME (or APP_NAME) is required')
                    }
                    if (!(params.APP_PORT ==~ /^\d+$/)) {
                        error('APP_PORT must be numeric')
                    }

                    def normalizedRegistry = (env.REGISTRY_REPOSITORY ?: '')
                        .replaceFirst(/^https?:\/\//, '')
                        .replaceAll(/\/+$/, '')
                    if (!normalizedRegistry.contains('/')) {
                        error('REGISTRY_REPOSITORY must include registry host and Harbor project (example: harbor.devith.it.com/deployment-pipeline)')
                    }
                }
            }
        }

        stage('Checkout infra') {
            steps {
                dir('platform-infra') {
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: '*/main']],
                        userRemoteConfigs: [[
                            url: env.INFRA_REPO_URL,
                            credentialsId: 'infra-repo-creds'
                        ]]
                    ])
                }
            }
        }

        stage('Checkout user repository') {
            steps {
                dir('user-app') {
                    script {
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
                        env.SAFE_USER_ID = sh(
                            script: '''echo "$USER_ID" | tr '[:upper:]' '[:lower:]' | sed -E "s/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g" | cut -c1-30''',
                            returnStdout: true
                        ).trim()
                        env.SAFE_PROJECT_NAME = sh(
                            script: '''echo "$EFFECTIVE_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed -E "s/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g" | cut -c1-40''',
                            returnStdout: true
                        ).trim()

                        env.NORMALIZED_REGISTRY_REPOSITORY = sh(
                            script: '''echo "$REGISTRY_REPOSITORY" | sed -E 's#^https?://##; s#/*$##' ''',
                            returnStdout: true
                        ).trim()

                        env.IMAGE_TAG = "${env.SAFE_USER_ID}-${env.BUILD_NUMBER}-${env.APP_COMMIT_SHA}"
                        env.IMAGE_REPOSITORY = "${env.NORMALIZED_REGISTRY_REPOSITORY}/${env.SAFE_USER_ID}/${env.SAFE_PROJECT_NAME}"
                        env.IMAGE_FULL = "${env.IMAGE_REPOSITORY}:${env.IMAGE_TAG}"
                        env.REGISTRY_LOGIN_SERVER = sh(
                            script: '''echo "$REGISTRY_REPOSITORY" | sed -E 's#^https?://##' | cut -d/ -f1''',
                            returnStdout: true
                        ).trim()

                        echo "Resolved image tag: ${env.IMAGE_TAG}"
                    }
                }
            }
        }

        stage('Detect framework') {
            steps {
                dir('user-app') {
                    script {
                        env.FRAMEWORK = sh(
                            script: "bash ${SCRIPTS_DIR}/detect-framework.sh",
                            returnStdout: true
                        ).trim()
                        echo "Detected framework: ${env.FRAMEWORK}"
                    }
                }
            }
        }

        stage('Prepare Dockerfile') {
            steps {
                dir('user-app') {
                    sh '''
                        if [ -f Dockerfile ]; then
                            echo "Using user-provided Dockerfile."
                        else
                            echo "Generating Dockerfile from platform template."
                            bash "${SCRIPTS_DIR}/generate-dockerfile.sh" "${FRAMEWORK}" "${SCRIPTS_DIR}"
                        fi
                    '''
                }
            }
        }

        stage('Build → Scan → Push') {
            agent { label 'trivy' }
            steps {
                script {
                    // Re-checkout infra (for scripts + helm chart)
                    dir('platform-infra') {
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: '*/main']],
                            userRemoteConfigs: [[
                                url: env.INFRA_REPO_URL,
                                credentialsId: 'infra-repo-creds'
                            ]]
                        ])
                    }

                    // Re-checkout user app
                    dir('user-app') {
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
                    }

                    // Prepare Dockerfile (in case user didn't provide one)
                    dir('user-app') {
                        sh '''
                            if [ -f Dockerfile ]; then
                                echo "Using user-provided Dockerfile."
                            else
                                echo "Generating Dockerfile from platform template."
                                bash "${SCRIPTS_DIR}/generate-dockerfile.sh" "${FRAMEWORK}" "${SCRIPTS_DIR}"
                            fi
                        '''
                    }

                    // Build
                        dir('user-app') {
                    sh 'docker build --pull -t "$IMAGE_FULL" .'
                }

                // 2. Scan (conditional — but does NOT gate the push on its own)
                if (params.ENABLE_TRIVY_SCAN) {
                    trivyScan(
                        fullImage: env.IMAGE_FULL,
                        trivyPath: '/home/enz/trivy/docker-compose.yml',
                        reportPath: '/home/enz/trivy/reports/trivy-report.json',
                        gateSeverity: 'HIGH,CRITICAL'
                    )
                    uploadDefectDojo(
                        defectdojoUrl: 'https://defectdojo.devith.it.com',
                        defectdojoCredentialId: 'DEFECTDOJO',
                        reportPath: '/home/enz/trivy/reports/trivy-report.json',
                        productTypeName: 'Web Applications',
                        productName: env.EFFECTIVE_PROJECT_NAME,
                        engagementName: "Jenkins-${env.BUILD_NUMBER}",
                        testTitle: "Trivy Image Scan - ${env.IMAGE_TAG}"
                    )
                }

                // 3. Push — always runs after scan (scan failures call error() and stop execution)
                withCredentials([usernamePassword(
                    credentialsId: 'registry-credentials',
                    usernameVariable: 'REGISTRY_USERNAME',
                    passwordVariable: 'REGISTRY_PASSWORD'
                )]) {
                    sh '''
                        echo "${REGISTRY_PASSWORD}" | docker login "${REGISTRY_LOGIN_SERVER}" \
                            -u "${REGISTRY_USERNAME}" --password-stdin
                        docker push "${IMAGE_FULL}"
                    '''
                    }
                }
            }
        }

        // stage('Update GitOps repository') {
        //     when {
        //         expression { return params.ENABLE_GITOPS_UPDATE }
        //     }
        //     steps {
        //         lock(resource: "gitops-${env.SAFE_USER_ID}-${env.SAFE_PROJECT_NAME}") {
        //             withCredentials([sshUserPrivateKey(credentialsId: 'gitops-ssh', keyFileVariable: 'SSH_KEY')]) {
        //                 sh '''
        //                     bash "${SCRIPTS_DIR}/update-gitops.sh" \
        //                       --gitops-repo "${GITOPS_REPO_URL}" \
        //                       --gitops-branch "${GITOPS_BRANCH}" \
        //                       --ssh-key "${SSH_KEY}" \
        //                       --user-id "${USER_ID}" \
        //                       --project-name "${EFFECTIVE_PROJECT_NAME}" \
        //                       --image-repository "${IMAGE_REPOSITORY}" \
        //                       --image-tag "${IMAGE_TAG}" \
        //                       --app-port "${APP_PORT}" \
        //                       --platform-domain "${PLATFORM_DOMAIN}" \
        //                       --framework "${FRAMEWORK}" \
        //                       --commit-sha "${APP_COMMIT_SHA}" \
        //                       --build-number "${BUILD_NUMBER}" \
        //                       --chart-source "${HELM_CHART_SOURCE}"
        //                 '''
        //             }
        //         }
        //     }
        // }
    }

    post {
        success {
            echo "Deployment requested successfully for ${env.EFFECTIVE_PROJECT_NAME}."
            echo "Image: ${env.IMAGE_FULL}"
            echo "Expected URL: https://${env.SAFE_PROJECT_NAME}.${params.PLATFORM_DOMAIN}"
        }
        failure {
            echo "Deployment failed. Check stage logs for details."
        }
        always {
            cleanWs()
        }
    }
}
