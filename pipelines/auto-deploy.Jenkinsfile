// ============================================================================
// AUTO-DEPLOY — Webhook-driven, đa registry, đa service. "Bê đi mọi nơi".
// Phát triển từ pipeline V28: GIỮ nguyên tên param (webhook cũ vẫn chạy),
// nhưng VÁ lỗ hổng lộ secret + thêm Trivy + tự rollback + dọn secret an toàn.
//
// ACTION:
//   imagebase : build image (Dockerfile ưu tiên trong repo, fallback Vault)
//               -> Trivy -> push -> kubectl set image -> rollout
//   pipeline  : cập nhật config (env.json/flows.json/env.js) -> secret
//               -> rollout restart
//
// NGUYÊN TẮC BẢO MẬT: secret chỉ nằm trong biến shell (đọc trực tiếp từ vault),
// KHÔNG dùng readFile->interpolate (thứ làm lộ secret trong Console Log).
// ============================================================================

import groovy.json.JsonOutput
import groovy.json.JsonSlurper

pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    parameters {
        // [CORE]
        string(name: 'ACTION', defaultValue: '', description: 'imagebase | pipeline')
        // [NOTIFICATION]
        string(name: 'WEBHOOK_URL', defaultValue: '', description: 'Teams/Slack Webhook URL')
        // [VAULT]
        string(name: 'VAULT_ADDR', defaultValue: '', description: 'Vault Address')
        string(name: 'VAULT_TOKEN_CRED', defaultValue: '', description: '(Khuyến nghị) Jenkins credential id chứa Vault token')
        password(name: 'VAULT_TOKEN', defaultValue: '', description: '(Fallback) Vault token trực tiếp — dùng khi không có VAULT_TOKEN_CRED')
        string(name: 'VAULT_PATH', defaultValue: '', description: 'Path secret chứa System Creds')
        // [REGISTRY]
        choice(name: 'REGISTRY_TYPE', choices: ['gitlab', 'ecr', 'dockerhub'], description: 'Loại Registry')
        string(name: 'REGISTRY_URL', defaultValue: 'registry.gitlab.com', description: 'URL Registry')
        string(name: 'AWS_REGION', defaultValue: 'us-east-1', description: 'AWS Region (ECR)')
        // [IMAGE]
        string(name: 'IMAGE_REPO', defaultValue: '', description: 'Full Image Repo (không kèm tag)')
        // [PROJECT]
        string(name: 'PROJECT_NAME', defaultValue: '', description: 'Tên Project (prefix)')
        string(name: 'ENVIRONMENT', defaultValue: '', description: 'Môi trường')
        // [GIT]
        string(name: 'GIT_REPO_URL', defaultValue: '', description: 'Repo URL (HTTPS)')
        string(name: 'GIT_BRANCH', defaultValue: '', description: 'Branch')
        string(name: 'GIT_CRED', defaultValue: '', description: '(Khuyến nghị) Jenkins credential (user/token) để clone. Trống = dùng GIT_USER/GIT_TOKEN từ Vault')
        string(name: 'COMMIT_MESSAGE', defaultValue: '', description: 'Commit Message')
        string(name: 'COMMIT_NAME', defaultValue: '', description: 'Commit Hash')
        // [VAULT KEY MAPPING] — tên KEY trên Vault (không phải giá trị)
        string(name: 'VAULT_DOCKERFILE_KEY', defaultValue: 'dockerfile-be-admin', description: 'Tên key Dockerfile trên Vault (vd: dockerfile-be-admin)')
        string(name: 'VAULT_GRUNTFILE_KEY', defaultValue: '', description: '(Optional) Tên key Gruntfile trên Vault (vd: grunt-file-be)')
        string(name: 'VAULT_DOCKERCONFIG_KEY', defaultValue: 'dockerconfigjson', description: '(gitlab/dockerhub) Tên key dockerconfigjson trên Vault để login registry. Trống = dùng DOCKER_USER/DOCKER_PASS')
        // ENV FILES: mỗi DÒNG = 1 file env -> 1 k8s Secret trong namespace của service.
        // Cú pháp mỗi dòng:  vaultKey  |  secretName(optional)  |  fileKey(optional)
        //   - vaultKey   : tên key trên Vault để lấy nội dung file
        //   - secretName : tên k8s Secret (mặc định = vaultKey)
        //   - fileKey    : tên file bên trong Secret (mặc định = secretName)
        // Thêm/bớt file = thêm/bớt dòng.
        text(name: 'ENV_FILES', defaultValue: '''secret-env-be
env-file-secret-wallet-be-admin
config-env-secret-wallet-be-admin''', description: 'Danh sách env file (mỗi dòng 1 file). Xem cú pháp trong pipeline.')
        // [DEPLOY]
        // --- Legacy: đã thay bằng ENV_FILES. Bỏ comment nếu cần dùng lại. ---
        // string(name: 'CLIENT_SECRET_NAME', defaultValue: '', description: 'List Secret K8s (legacy)')
        // string(name: 'CLIENT_LOCATION_VAULT', defaultValue: '', description: 'JSON list file lấy từ Vault (legacy)')
        string(name: 'SELECTED_INTS', defaultValue: '', description: 'JSON list tên service/integration')
        // --- Đặt tên tài nguyên. Mặc định theo công thức {PROJECT}-{int}-{ENV}-{suffix}.
        //     Điền override để ÉP đúng tên khi công thức không khớp (chỉ hợp lệ khi 1 int).
        string(name: 'NAMESPACE', defaultValue: '', description: 'Override tên namespace (trống = {PROJECT}-{int}-{ENV}-ns)')
        string(name: 'DEPLOYMENT_NAME', defaultValue: '', description: 'Override tên deployment (trống = {PROJECT}-{int}-{ENV}-deployment)')
        string(name: 'KUBE_CRED', defaultValue: '', description: '(Khuyến nghị) Jenkins credential (Secret file) kubeconfig. Trống = đọc KUBE_CONFIG từ Vault')
        // [OPTIONS - mới]
        booleanParam(name: 'RUN_TRIVY', defaultValue: true, description: 'Quét lỗ hổng image (imagebase)')
        booleanParam(name: 'TRIVY_BLOCK', defaultValue: false, description: 'CHẶN nếu có CVE HIGH/CRITICAL')
        // [GRUNT] Bật cho app Sails có asset cần build; tắt cho API thuần.
        booleanParam(name: 'RUN_GRUNT', defaultValue: false, description: 'Chạy Grunt build asset trước khi build image (app có Gruntfile)')
        string(name: 'GRUNT_TASK', defaultValue: '', description: 'Task Grunt cụ thể (trống = task mặc định trong Gruntfile)')
    }

    stages {
        stage('Initialization')      { steps { script { runInitialization() } } }
        stage('Checkout Source')     { steps { script { runCheckoutSource() } } }

        stage('Grunt Build')         { when { expression { params.ACTION == 'imagebase' && params.RUN_GRUNT } }
                                       steps { script { runGruntBuild() } } }
        stage('Build Image')         { when { expression { params.ACTION == 'imagebase' } }
                                       steps { script { runBuildImage() } } }
        stage('Trivy Scan')          { when { expression { params.ACTION == 'imagebase' && params.RUN_TRIVY } }
                                       steps { script { runTrivyScan() } } }
        stage('Push Image')          { when { expression { params.ACTION == 'imagebase' } }
                                       steps { script { runPushImage() } } }

        stage('Deploy to Cluster')   { when { expression { params.SELECTED_INTS?.trim() } }
                                       steps { script { runDeployToCluster() } } }
    }

    post {
        success { script { sendNotification('SUCCESS', "Deploy thành công: ${params.PROJECT_NAME} (${params.ENVIRONMENT}).") } }
        failure {
            script {
                def st = env.FAILED_STAGE ?: 'Unknown'
                def er = env.ERROR_LOG ?: 'Xem Console Log.'
                sendNotification('FAILURE', "Stage: ${st}\\nError: ${er}")
            }
        }
        cleanup { cleanWs() }   // xoá workspace + mọi file secret tạm
    }
}

// ============================================================================
// HELPERS
// ============================================================================

def runWithHandling(String stageName, Closure body) {
    try { body() }
    catch (Exception e) {
        env.FAILED_STAGE = stageName
        env.ERROR_LOG = e.getMessage()
        echo "Lỗi tại '${stageName}': ${e.getMessage()}"
        throw e
    }
}

// Đăng nhập Vault 1 lần (token cache ở ~/.vault-token cho các lệnh sau).
// Ưu tiên credential; fallback param. Token KHÔNG bao giờ vào Groovy/log.
def vaultLogin() {
    if (params.VAULT_TOKEN_CRED?.trim()) {
        withCredentials([string(credentialsId: params.VAULT_TOKEN_CRED, variable: 'VT')]) {
            sh '''set +x
printf '%s' "$VT" | vault login -no-print -address='''+ params.VAULT_ADDR +''' -method=token token=-
set -x'''
        }
    } else if (params.VAULT_TOKEN?.trim()) {
        withEnv(["VT_VALUE=${params.VAULT_TOKEN}"]) {
            sh '''set +x
printf '%s' "$VT_VALUE" | vault login -no-print -address='''+ params.VAULT_ADDR +''' -method=token token=-
set -x'''
        }
    } else {
        error("Thiếu Vault token: cung cấp VAULT_TOKEN_CRED (khuyến nghị) hoặc VAULT_TOKEN.")
    }
}

def runInitialization() {
    runWithHandling("Initialization") {
        def suffix = ""
        if (params.SELECTED_INTS?.trim()) {
            try {
                def ints = new JsonSlurper().parseText(params.SELECTED_INTS)
                if (ints instanceof List && ints) suffix = " - " + ints.join(", ")
            } catch (ignored) {}
        }
        currentBuild.displayName = "[${params.ACTION}] ${params.PROJECT_NAME}${suffix} - ${params.ENVIRONMENT} - #${env.BUILD_ID}"
        echo "=== CONFIG ==="
        params.each { k, v ->
            if (k == 'VAULT_TOKEN') echo "  ${k} : ***** (ẩn)"
            else if (!(k in ['COMMIT_MESSAGE', 'COMMIT_NAME'])) echo "  ${k} : ${v ?: '(trống)'}"
        }
    }
}

def runCheckoutSource() {
    runWithHandling("Checkout Source") {
        def dir = "${params.PROJECT_NAME}-${params.ENVIRONMENT}"
        def cleanUrl = params.GIT_REPO_URL.replace("https://", "")
        if (params.GIT_CRED?.trim()) {
            // Ưu tiên Jenkins credential (an toàn hơn, không cần Git trong Vault).
            withCredentials([usernamePassword(credentialsId: params.GIT_CRED, usernameVariable: 'GU', passwordVariable: 'GP')]) {
                sh """
                    set +x
                    rm -rf ${dir}
                    git clone -b ${params.GIT_BRANCH} "https://oauth2:\$GP@${cleanUrl}" ${dir}
                    set -x
                """
            }
        } else {
            // Fallback: GIT_USER/GIT_TOKEN từ Vault (chỉ trong shell, không qua Groovy/log).
            vaultLogin()
            sh """
                set +x
                GIT_USER="\$(vault kv get -field=GIT_USER -address=${params.VAULT_ADDR} ${params.VAULT_PATH})"
                GIT_TOKEN="\$(vault kv get -field=GIT_TOKEN -address=${params.VAULT_ADDR} ${params.VAULT_PATH})"
                rm -rf ${dir}
                git clone -b ${params.GIT_BRANCH} "https://\${GIT_USER}:\${GIT_TOKEN}@${cleanUrl}" ${dir}
                set -x
            """
        }
        env.COMMIT_NAME    = sh(script: "cd ${dir} && git rev-parse --short HEAD", returnStdout: true).trim()
        env.COMMIT_MESSAGE = sh(script: "cd ${dir} && git log -1 --pretty=%B", returnStdout: true).trim()
        echo "Commit: ${env.COMMIT_NAME}"
    }
}

// Grunt build asset trên Jenkins (Node 22 có sẵn) TRƯỚC khi docker build.
// Tự bỏ qua nếu repo không có Gruntfile.js -> an toàn cho cả app không cần Grunt.
def runGruntBuild() {
    runWithHandling("Grunt Build") {
        def dir = "${params.PROJECT_NAME}-${params.ENVIRONMENT}"
        def gKey = params.VAULT_GRUNTFILE_KEY?.trim()
        if (!fileExists("${dir}/Gruntfile.js")) {
            if (gKey) {
                // Lấy Gruntfile từ Vault (vd be-admin dùng key 'grunt-file-be')
                vaultLogin()
                sh """
                    set +x
                    vault kv get -field=${gKey} -address=${params.VAULT_ADDR} ${params.VAULT_PATH} > ${dir}/Gruntfile.js
                    set -x
                """
                echo "Đã lấy Gruntfile từ Vault key: ${gKey}"
            } else {
                echo "Không có Gruntfile (repo & Vault) -> bỏ qua Grunt."
                return
            }
        }
        def task = params.GRUNT_TASK?.trim() ?: ''
        echo "Chạy Grunt build (task='${task ?: 'default'}')..."
        sh """
            cd ${dir}
            npm install
            npx grunt ${task}
        """
    }
}

def runBuildImage() {
    runWithHandling("Build Image") {
        def dir = "${params.PROJECT_NAME}-${params.ENVIRONMENT}"
        def tag = "${params.PROJECT_NAME}-${params.ENVIRONMENT}-${env.COMMIT_NAME}-${env.BUILD_ID}"
        env.GENERATED_IMAGE_PATH = "${params.IMAGE_REPO}:${tag}"
        echo "Build: ${env.GENERATED_IMAGE_PATH}"
        vaultLogin()
        def dfKey = params.VAULT_DOCKERFILE_KEY?.trim()
        // Ưu tiên Dockerfile trong repo; nếu không có mới lấy từ Vault theo key đã nhập.
        sh """
            set +x
            cd ${dir}
            if [ ! -f Dockerfile ]; then
              if [ -z "${dfKey}" ]; then
                echo "Repo không có Dockerfile và VAULT_DOCKERFILE_KEY trống"; exit 1
              fi
              echo "Lấy Dockerfile từ Vault key: ${dfKey}"
              vault kv get -field=${dfKey} -address=${params.VAULT_ADDR} ${params.VAULT_PATH} > Dockerfile
            fi
            set -x
            docker build -t ${env.GENERATED_IMAGE_PATH} .
        """
    }
}

def runTrivyScan() {
    runWithHandling("Trivy Scan") {
        def code = params.TRIVY_BLOCK ? 1 : 0
        sh "trivy image --scanners vuln --severity HIGH,CRITICAL --no-progress --exit-code ${code} ${env.GENERATED_IMAGE_PATH}"
    }
}

def runPushImage() {
    runWithHandling("Push Image") {
        vaultLogin()
        if (params.REGISTRY_TYPE == 'ecr') {
            sh """
                set +x
                export AWS_ACCESS_KEY_ID="\$(vault kv get -field=AWS_ACCESS_KEY -address=${params.VAULT_ADDR} ${params.VAULT_PATH})"
                export AWS_SECRET_ACCESS_KEY="\$(vault kv get -field=AWS_SECRET_KEY -address=${params.VAULT_ADDR} ${params.VAULT_PATH})"
                export AWS_DEFAULT_REGION=${params.AWS_REGION}
                aws ecr get-login-password --region ${params.AWS_REGION} | docker login --username AWS --password-stdin ${params.REGISTRY_URL}
                set -x
            """
            sh "docker push ${env.GENERATED_IMAGE_PATH}"
        } else if (params.VAULT_DOCKERCONFIG_KEY?.trim()) {
            // Dùng dockerconfigjson từ Vault -> config riêng (không đụng ~/.docker chung).
            sh """
                set +x
                mkdir -p .secure/dockercfg
                vault kv get -field=${params.VAULT_DOCKERCONFIG_KEY} -address=${params.VAULT_ADDR} ${params.VAULT_PATH} > .secure/dockercfg/config.json
                chmod 600 .secure/dockercfg/config.json
                set -x
                docker --config .secure/dockercfg push ${env.GENERATED_IMAGE_PATH}
                rm -rf .secure/dockercfg
            """
        } else {
            // Fallback: DOCKER_USER/DOCKER_PASS (chỉ trong biến shell, không lộ log).
            sh """
                set +x
                DUSER="\$(vault kv get -field=DOCKER_USER -address=${params.VAULT_ADDR} ${params.VAULT_PATH})"
                printf '%s' "\$(vault kv get -field=DOCKER_PASS -address=${params.VAULT_ADDR} ${params.VAULT_PATH})" \
                  | docker login ${params.REGISTRY_URL} -u "\$DUSER" --password-stdin
                set -x
            """
            sh "docker push ${env.GENERATED_IMAGE_PATH}"
        }
    }
}

// Parse param ENV_FILES (nhiều dòng) -> danh sách [vaultKey, secretName, fileKey].
// Cú pháp mỗi dòng:  vaultKey | secretName(optional) | fileKey(optional)
def parseEnvFiles() {
    def out = []
    if (!params.ENV_FILES?.trim()) return out
    params.ENV_FILES.split("\n").each { raw ->
        def line = raw.trim()
        if (!line || line.startsWith('#')) return
        def parts = line.split("\\|").collect { it.trim() }
        def vaultKey = parts[0]
        if (!vaultKey) return
        def secretName = (parts.size() > 1 && parts[1]) ? parts[1] : vaultKey
        def fileKey    = (parts.size() > 2 && parts[2]) ? parts[2] : secretName
        out << [vaultKey: vaultKey, secretName: secretName, fileKey: fileKey]
    }
    return out
}

// Với mỗi env file: lấy nội dung từ Vault -> tạo 1 k8s Secret trong namespace.
// Nội dung secret chỉ nằm trong file tạm .secure, không in log, dọn ngay sau khi apply.
def applyEnvFileSecrets(String kube, String ns) {
    def files = parseEnvFiles()
    if (!files) { echo "ENV_FILES trống -> không tạo secret."; return }
    files.each { f ->
        sh """
            set +x
            vault kv get -field=${f.vaultKey} -address=${params.VAULT_ADDR} ${params.VAULT_PATH} > .secure/${f.fileKey}
            KUBECONFIG=${kube} kubectl create secret generic ${f.secretName} \
              --from-file=${f.fileKey}=.secure/${f.fileKey} -n ${ns} \
              --dry-run=client -o yaml | KUBECONFIG=${kube} kubectl apply -f -
            rm -f .secure/${f.fileKey}
            set -x
        """
        echo "Secret '${f.secretName}' (file '${f.fileKey}') -> ns ${ns}"
    }
}

def runDeployToCluster() {
    runWithHandling("Deploy to Cluster") {
        if (!params.SELECTED_INTS?.trim()) { echo "SELECTED_INTS trống — bỏ qua."; return }
        def ints = new JsonSlurper().parseText(params.SELECTED_INTS)

        vaultLogin()   // cần cho ENV_FILES (đọc từ Vault)
        sh 'mkdir -p .secure && chmod 700 .secure'
        // Nguồn kubeconfig: ưu tiên Jenkins credential (Secret file); fallback Vault.
        if (params.KUBE_CRED?.trim()) {
            withCredentials([file(credentialsId: params.KUBE_CRED, variable: 'KCFG')]) {
                sh 'cp "$KCFG" .secure/kube-config && chmod 600 .secure/kube-config'
            }
        } else {
            sh """
                set +x
                vault kv get -field=KUBE_CONFIG -address=${params.VAULT_ADDR} ${params.VAULT_PATH} > .secure/kube-config
                chmod 600 .secure/kube-config
                set -x
            """
        }
        def kube = ".secure/kube-config"
        def image = env.GENERATED_IMAGE_PATH ?: "${params.IMAGE_REPO}:${params.PROJECT_NAME}-${params.ENVIRONMENT}-${env.BUILD_ID}"
        def proj  = params.PROJECT_NAME.trim()
        def envn  = params.ENVIRONMENT.trim()
        def codeDir = "${proj}-${envn}"

        ints.each { item ->
            def name   = item.trim()
            def base   = "${proj}-${name}-${envn}"
            def ns     = params.NAMESPACE?.trim()       ? params.NAMESPACE.trim()       : "${base}-ns"
            def deploy = params.DEPLOYMENT_NAME?.trim() ? params.DEPLOYMENT_NAME.trim() : "${base}-deployment"
            def secret = "secret-env-${name}"
            echo "=== ${name}  ->  namespace='${ns}'  deployment='${deploy}' ==="

            // Namespace: chỉ tạo mới nếu chưa có (không đụng namespace do IaC quản lý).
            sh "KUBECONFIG=${kube} kubectl get namespace ${ns} >/dev/null 2>&1 || KUBECONFIG=${kube} kubectl create namespace ${ns}"

            // Apply mọi ENV_FILES thành k8s Secret trong namespace này.
            applyEnvFileSecrets(kube, ns)

            // CHẶN SAI CHỖ: deployment BẮT BUỘC phải tồn tại sẵn -> sai tên là dừng ngay.
            sh """
                export KUBECONFIG=${kube}
                if ! kubectl get deployment ${deploy} -n ${ns} >/dev/null 2>&1; then
                  echo "❌ KHÔNG tìm thấy deployment '${deploy}' trong namespace '${ns}'."
                  echo "   Kiểm tra PROJECT_NAME/SELECTED_INTS/ENVIRONMENT hoặc NAMESPACE/DEPLOYMENT_NAME."
                  echo "   Các deployment đang có trong ns:"; kubectl get deploy -n ${ns} -o name || true
                  exit 1
                fi
            """

            if (params.ACTION == 'imagebase') {
                // Tự DÒ tên container thật (không đoán) rồi set image.
                sh """
                    export KUBECONFIG=${kube}
                    CONTAINER=\$(kubectl get deployment ${deploy} -n ${ns} -o jsonpath='{.spec.template.spec.containers[0].name}')
                    echo "set image -> deployment=${deploy} container=\$CONTAINER image=${image}"
                    kubectl set image deployment/${deploy} \$CONTAINER=${image} -n ${ns}
                    kubectl rollout status deployment/${deploy} -n ${ns} --timeout=180s \
                      || (echo 'Rollout lỗi -> rollback'; kubectl rollout undo deployment/${deploy} -n ${ns}; exit 1)
                """
            } else if (params.ACTION == 'pipeline') {
                def args = []
                ["env.json", "flows.json", "env.js"].each { f ->
                    if (fileExists("${codeDir}/${f}")) args.add("--from-file=${f}=${codeDir}/${f}")
                }
                if (args) {
                    sh """
                        export KUBECONFIG=${kube}
                        kubectl create secret generic ${secret} ${args.join(' ')} -n ${ns} \
                          --dry-run=client -o yaml | kubectl apply -f -
                    """
                }
                sh """
                    export KUBECONFIG=${kube}
                    kubectl rollout restart deployment/${deploy} -n ${ns}
                    kubectl rollout status deployment/${deploy} -n ${ns} --timeout=180s \
                      || (echo 'Rollout lỗi -> rollback'; kubectl rollout undo deployment/${deploy} -n ${ns}; exit 1)
                """
            }
            echo "Xong ${name}"
        }
    }
}

// Gửi Teams qua httpRequest (JSON escape an toàn, KHÔNG dùng curl+interpolate).
def sendNotification(String status, String message) {
    def url = params.WEBHOOK_URL?.trim()
    if (!url) { echo "Không có WEBHOOK_URL — bỏ qua notify."; return }
    def color = (status == 'SUCCESS') ? '2EB886' : 'D00000'
    def title = "${(status == 'SUCCESS') ? '✅' : '❌'} ${params.PROJECT_NAME} - ${params.ENVIRONMENT}"
    def payload = [
        "@type"   : "MessageCard", "@context": "http://schema.org/extensions",
        themeColor: color, summary: title,
        sections  : [[
            activityTitle: title, activitySubtitle: "Build #${env.BUILD_ID}",
            facts: [
                [name: 'Action', value: params.ACTION ?: '-'],
                [name: 'Branch', value: params.GIT_BRANCH ?: '-'],
                [name: 'Image',  value: env.GENERATED_IMAGE_PATH ?: '-'],
                [name: 'Status', value: status]
            ],
            text: message
        ]],
        potentialAction: [[ "@type": "OpenUri", name: "View Console",
            targets: [["os": "default", "uri": env.BUILD_URL ?: '']] ]]
    ]
    try {
        httpRequest httpMode: 'POST', contentType: 'APPLICATION_JSON',
            requestBody: JsonOutput.toJson(payload), url: url, validResponseCodes: '100:599'
    } catch (e) {
        echo "WARN: gửi notify thất bại: ${e.message}"
    }
}
