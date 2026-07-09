// ============================================================================
// DEPLOY-ANY-PROJECT — Jenkinsfile TẤT-CẢ-TRONG-MỘT
// ----------------------------------------------------------------------------
// 1 file duy nhất. Đổi PARAMETER (không sửa code) là deploy được mọi dự án.
// Luồng: Clone -> Build -> Trivy -> Push -> (Vault) -> (Duyệt) -> Deploy K8s -> Teams.
//
// CÁCH DÙNG:
//   - Tạo Pipeline job -> dán file này vào (hoặc trỏ SCM tới file này).
//   - Build with Parameters -> điền thông tin dự án -> Build.
//   - Deploy dự án/môi trường khác = đổi param, KHÔNG sửa code.
//
// CREDENTIALS cần tạo sẵn trong Jenkins (Manage Jenkins -> Credentials):
//   gitlab-credentials (user/token)  · gitlab-registry (user/token)
//   vault-token (secret text)        · teams-webhook (secret text)
//   kubeconfig-dev/staging/prod (secret file)
// K8s: cần Ingress controller nếu bật Ingress.
// ============================================================================

pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }

  parameters {
    // ===================== THÔNG TIN DỰ ÁN =====================
    string(name: 'APP_NAME',        defaultValue: 'node-backend', description: 'Tên app (= tên deployment/service/secret/configmap)')
    string(name: 'GIT_REPO',        defaultValue: 'https://gitlab.com/jits-innovation/node-backend.git', description: 'URL repo (HTTPS)')
    string(name: 'GIT_BRANCH',      defaultValue: 'develop', description: 'Nhánh build')
    string(name: 'REGISTRY_IMAGE',  defaultValue: 'registry.gitlab.com/jits-innovation/node-backend', description: 'Đường dẫn image (KHÔNG kèm tag)')

    // ===================== KUBERNETES =====================
    string(name: 'NAMESPACE',       defaultValue: 'node-backend-dev', description: 'Namespace deploy (tự tạo nếu chưa có)')
    string(name: 'KUBE_CREDENTIAL', defaultValue: 'kubeconfig-dev', description: 'Jenkins credential (Secret file) kubeconfig của cụm/môi trường')
    string(name: 'REPLICAS',        defaultValue: '1', description: 'Số bản chạy')
    string(name: 'CONTAINER_PORT',  defaultValue: '3000', description: 'Cổng app lắng nghe trong container')
    string(name: 'SERVICE_PORT',    defaultValue: '80', description: 'Cổng Service')
    text(  name: 'ENV_VARS',        defaultValue: 'NODE_ENV=production\nPORT=3000', description: 'Env công khai — mỗi dòng KEY=VALUE (thành ConfigMap)')

    // ===================== INGRESS (tùy chọn) =====================
    booleanParam(name: 'ENABLE_INGRESS', defaultValue: false, description: 'Tạo Ingress (domain)')
    string(name: 'INGRESS_HOST',    defaultValue: '', description: 'Domain, vd api-dev.jits.com')
    string(name: 'INGRESS_CLASS',   defaultValue: 'nginx', description: 'IngressClass')

    // ===================== VAULT (tùy chọn) =====================
    booleanParam(name: 'USE_VAULT', defaultValue: false, description: 'Nạp secret từ Vault vào k8s Secret <app>-secrets')
    string(name: 'VAULT_ADDR',      defaultValue: 'http://192.168.10.153:8200', description: 'Vault server')
    string(name: 'VAULT_PATH',      defaultValue: 'secret/data/node-backend', description: 'KV path chứa secret')
    string(name: 'VAULT_KEYS',      defaultValue: 'DB_PASSWORD,JWT_SECRET', description: 'Các key, ngăn cách bởi dấu phẩy')

    // ===================== TÙY CHỌN =====================
    booleanParam(name: 'RUN_TRIVY',     defaultValue: true,  description: 'Quét lỗ hổng image')
    booleanParam(name: 'TRIVY_BLOCK',   defaultValue: false, description: 'CHẶN deploy nếu có CVE HIGH/CRITICAL')
    booleanParam(name: 'PROD_APPROVAL', defaultValue: false, description: 'Chờ người duyệt trước khi deploy')

    // ===================== CREDENTIAL IDS =====================
    string(name: 'GIT_CRED',           defaultValue: 'gitlab-credentials', description: 'Credential clone repo (user/token)')
    string(name: 'REGISTRY_CRED',      defaultValue: 'gitlab-registry',    description: 'Credential push/pull image (user/token)')
    string(name: 'VAULT_TOKEN_CRED',   defaultValue: 'vault-token',        description: 'Credential token Vault (secret text)')
    string(name: 'TEAMS_WEBHOOK_CRED', defaultValue: 'teams-webhook',      description: 'Credential webhook Teams (secret text)')
  }

  stages {
    stage('Checkout') {
      steps {
        script {
          deleteDir()
          withCredentials([usernamePassword(credentialsId: params.GIT_CRED, usernameVariable: 'GU', passwordVariable: 'GP')]) {
            def repo = params.GIT_REPO.replaceFirst('https://', '')
            sh "git clone --branch ${params.GIT_BRANCH} https://oauth2:\$GP@${repo} ."
          }
          def sha = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          env.IMAGE_TAG  = params.GIT_BRANCH.replaceAll('[^a-zA-Z0-9_.-]', '-') + '-' + sha
          env.FULL_IMAGE = "${params.REGISTRY_IMAGE}:${env.IMAGE_TAG}"
          currentBuild.displayName = "${params.APP_NAME} · ${params.NAMESPACE} · ${env.IMAGE_TAG}"
          notify('STARTED', "Bắt đầu deploy **${params.APP_NAME}** → **${params.NAMESPACE}** (`${env.IMAGE_TAG}`)")
        }
      }
    }

    stage('Build image') {
      steps { sh "docker build -t ${env.FULL_IMAGE} ." }
    }

    stage('Trivy scan') {
      when { expression { params.RUN_TRIVY } }
      steps {
        sh "trivy image --scanners vuln --severity HIGH,CRITICAL --no-progress --exit-code ${params.TRIVY_BLOCK ? 1 : 0} ${env.FULL_IMAGE}"
      }
    }

    stage('Push image') {
      steps {
        script {
          def host = params.REGISTRY_IMAGE.tokenize('/')[0]
          withCredentials([usernamePassword(credentialsId: params.REGISTRY_CRED, usernameVariable: 'RU', passwordVariable: 'RP')]) {
            sh """
              set +x
              echo "\$RP" | docker login ${host} -u "\$RU" --password-stdin
              set -x
              docker push ${env.FULL_IMAGE}
            """
          }
        }
      }
    }

    stage('Approve') {
      when { expression { params.PROD_APPROVAL } }
      steps {
        timeout(time: 30, unit: 'MINUTES') {
          input message: "Deploy ${env.FULL_IMAGE} lên ${params.NAMESPACE}?", ok: 'Deploy'
        }
      }
    }

    stage('Deploy to Kubernetes') {
      steps {
        script {
          withKubeConfig([credentialsId: params.KUBE_CREDENTIAL]) {
            def ns = params.NAMESPACE
            def app = params.APP_NAME

            // 1) Namespace
            sh "kubectl create namespace ${ns} --dry-run=client -o yaml | kubectl apply -f -"

            // 2) imagePullSecret (để cụm kéo image private)
            def host = params.REGISTRY_IMAGE.tokenize('/')[0]
            withCredentials([usernamePassword(credentialsId: params.REGISTRY_CRED, usernameVariable: 'RU', passwordVariable: 'RP')]) {
              sh """
                set +x
                kubectl -n ${ns} create secret docker-registry gitlab-registry \
                  --docker-server=${host} --docker-username="\$RU" --docker-password="\$RP" \
                  --dry-run=client -o yaml | kubectl apply -f -
                set -x
              """
            }

            // 3) ConfigMap (env công khai)
            writeFile file: 'app.env', text: params.ENV_VARS
            sh "kubectl -n ${ns} create configmap ${app}-config --from-env-file=app.env --dry-run=client -o yaml | kubectl apply -f -"

            // 4) Secret từ Vault (tùy chọn)
            if (params.USE_VAULT) { syncVault() }

            // 5) Deployment + Service (+ Ingress) — sinh manifest ngay trong file
            writeFile file: 'k8s.yaml', text: renderManifest()
            sh "kubectl -n ${ns} apply -f k8s.yaml"

            // 6) Chờ rollout; nếu lỗi thì TỰ ROLLBACK (giống helm --atomic)
            sh "kubectl -n ${ns} rollout status deploy/${app} --timeout=180s || (echo 'Rollout lỗi -> rollback'; kubectl -n ${ns} rollout undo deploy/${app}; exit 1)"
          }
        }
      }
    }
  }

  post {
    success { script { notify('SUCCESS', "✅ **${params.APP_NAME}** `${env.IMAGE_TAG}` → **${params.NAMESPACE}** THÀNH CÔNG") } }
    failure { script { notify('FAILURE', "❌ **${params.APP_NAME}** deploy THẤT BẠI") } }
    cleanup { cleanWs() }
  }
}

// ============================================================================
// HÀM PHỤ (nằm cùng file — không cần shared library)
// ============================================================================

// Đọc secret từ Vault -> tạo k8s Secret <app>-secrets. Giá trị chỉ nằm trong
// file tạm, KHÔNG in log, KHÔNG vào command args.
def syncVault() {
  def keys = params.VAULT_KEYS.split(',').collect { it.trim() }.findAll { it }.join(' ')
  withCredentials([string(credentialsId: params.VAULT_TOKEN_CRED, variable: 'VT')]) {
    sh """
      set +x
      export VAULT_ADDR="${params.VAULT_ADDR}"
      export VAULT_TOKEN="\$VT"
      TMPD=\$(mktemp -d); ARGS=""
      for KEY in ${keys}; do
        vault kv get -field=\$KEY ${params.VAULT_PATH} > "\$TMPD/\$KEY"
        ARGS="\$ARGS --from-file=\$KEY=\$TMPD/\$KEY"
      done
      kubectl -n ${params.NAMESPACE} create secret generic ${params.APP_NAME}-secrets \$ARGS \
        --dry-run=client -o yaml | kubectl apply -f -
      rm -rf "\$TMPD"; set -x
      echo "Đã đồng bộ secret vào ${params.APP_NAME}-secrets"
    """
  }
}

// Sinh manifest k8s (Deployment + Service + Ingress tùy chọn)
def renderManifest() {
  def app = params.APP_NAME

  def secretRef = params.USE_VAULT ? """
            - secretRef:
                name: ${app}-secrets
                optional: true""" : ''

  def ingress = ''
  if (params.ENABLE_INGRESS) {
    ingress = """
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${app}
spec:
  ingressClassName: ${params.INGRESS_CLASS}
  rules:
    - host: ${params.INGRESS_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${app}
                port:
                  number: ${params.SERVICE_PORT}
"""
  }

  return """
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${app}
  labels:
    app: ${app}
spec:
  replicas: ${params.REPLICAS}
  selector:
    matchLabels:
      app: ${app}
  template:
    metadata:
      labels:
        app: ${app}
    spec:
      imagePullSecrets:
        - name: gitlab-registry
      containers:
        - name: ${app}
          image: ${env.FULL_IMAGE}
          ports:
            - containerPort: ${params.CONTAINER_PORT}
          envFrom:
            - configMapRef:
                name: ${app}-config${secretRef}
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits:   { cpu: 500m, memory: 256Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: ${app}
spec:
  selector:
    app: ${app}
  ports:
    - port: ${params.SERVICE_PORT}
      targetPort: ${params.CONTAINER_PORT}
${ingress}
"""
}

// Gửi thông báo Teams (http_request plugin). Lỗi notify không làm fail build.
def notify(String status, String text) {
  try {
    withCredentials([string(credentialsId: params.TEAMS_WEBHOOK_CRED, variable: 'HOOK')]) {
      def color = (status == 'SUCCESS') ? '2EB886' : (status == 'FAILURE') ? 'D00000' : '0076D7'
      def payload = [
        "@type"   : "MessageCard", "@context": "http://schema.org/extensions",
        summary   : text, themeColor: color,
        title     : "${status} · ${params.APP_NAME}",
        sections  : [[ activitySubtitle: text, facts: [
          [name: 'Namespace', value: params.NAMESPACE],
          [name: 'Image',     value: env.FULL_IMAGE ?: '-'],
          [name: 'Build',     value: env.BUILD_URL ?: '-']
        ]]]
      ]
      httpRequest httpMode: 'POST', contentType: 'APPLICATION_JSON',
        requestBody: groovy.json.JsonOutput.toJson(payload), url: HOOK,
        validResponseCodes: '100:599'
    }
  } catch (e) {
    echo "WARN: gửi Teams thất bại: ${e.message}"
  }
}
