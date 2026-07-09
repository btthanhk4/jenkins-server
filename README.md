# Jenkins DevOps Server

Hạ tầng Jenkins **All-in-One** đóng gói bằng Docker, cấu hình bằng
[Configuration as Code (JCasC)](https://github.com/jenkinsci/configuration-as-code-plugin),
sẵn sàng deploy các dự án của công ty.

Image đã tích hợp sẵn: **Docker CLI, kubectl, Helm, Maven, Node 22, Terraform,
Vault, SonarScanner, Trivy, AWS CLI, Ansible**.

---

## 📁 Cấu trúc thư mục

```
jenkins-server/
├── docker/
│   └── Dockerfile           # Image Jenkins + toàn bộ DevOps tools
├── plugins/
│   └── plugins.txt          # Danh sách plugin cài sẵn khi build
├── casc/
│   └── jenkins.yaml         # Cấu hình Jenkins (JCasC) - version control được
├── scripts/
│   ├── backup.sh            # Sao lưu JENKINS_HOME
│   └── restore.sh           # Khôi phục từ backup
├── examples/
│   └── Jenkinsfile.example  # Pipeline mẫu cho dự án
├── docker-compose.yml       # Định nghĩa service
├── .env.example             # Mẫu biến môi trường (copy -> .env)
├── .gitignore               # Chặn commit secret
├── .dockerignore
├── Makefile                 # Lệnh tắt: make up / down / logs ...
└── README.md
```

---

## 🚀 Cài đặt trên VM

### 1. Yêu cầu

- VM Debian/Ubuntu, đã cài **Docker Engine** + **Docker Compose plugin**
- User đang dùng nằm trong group `docker`

```bash
# Cài Docker (nếu chưa có)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Lấy source về VM

```bash
git clone <URL-repo-của-bạn> jenkins-server
cd jenkins-server
```

### 3. Tạo file cấu hình

```bash
cp .env.example .env
nano .env        # đổi mật khẩu admin, JENKINS_URL, email...
```

> ⚠️ **Bắt buộc** đổi `JENKINS_ADMIN_PASSWORD` trước khi chạy production.

### 4. Build & khởi động

```bash
make build       # hoặc: docker compose build --no-cache
make up          # hoặc: docker compose up -d
make logs        # theo dõi khởi động
```

Truy cập: **http://<IP-VM>:8080** — đăng nhập bằng tài khoản trong `.env`.

---

## 🔧 Lệnh thường dùng (Makefile)

| Lệnh            | Chức năng                          |
|-----------------|------------------------------------|
| `make up`       | Khởi động Jenkins                  |
| `make down`     | Dừng & xoá container               |
| `make restart`  | Khởi động lại                      |
| `make logs`     | Xem log realtime                   |
| `make shell`    | Vào bash trong container           |
| `make backup`   | Sao lưu dữ liệu                    |
| `make restore FILE=backups/xxx.tar.gz` | Khôi phục       |
| `make clean`    | Dừng + **xoá volume** (nguy hiểm)  |

---

## 🔐 Bảo mật

- **Không bao giờ** commit file `.env` hay secret (đã chặn trong `.gitignore`).
- Secret/credentials nên nạp qua **Jenkins Credentials** hoặc **Vault**, không hardcode vào `casc/jenkins.yaml`.
- Nên đặt **reverse proxy (Nginx) + HTTPS** trước Jenkins khi chạy production.
- Container gắn `docker.sock` của host ⇒ Jenkins có quyền tương đương root trên host. Chỉ cấp quyền cho người đáng tin.

---

## 💾 Sao lưu & khôi phục

```bash
make backup                                   # tạo backups/jenkins-home-*.tar.gz
make restore FILE=backups/jenkins-home-XXXX.tar.gz
```

Nên thiết lập cron backup định kỳ và đẩy file backup ra nơi lưu trữ ngoài (S3...).

---

## 📝 Deploy dự án

1. Copy `examples/Jenkinsfile.example` vào repo dự án, đổi tên thành `Jenkinsfile`.
2. Trên Jenkins: **New Item → Pipeline** (hoặc Multibranch Pipeline) → trỏ tới repo.
3. Thêm credentials (GitLab/registry) trong **Manage Jenkins → Credentials**.
4. Chạy build.

---

## 🛠 Thêm/bớt công cụ hoặc plugin

- **Plugin:** sửa `plugins/plugins.txt` → `make build` → `make up`.
- **Công cụ CLI:** thêm block `RUN` tương ứng trong `docker/Dockerfile` → rebuild.
- **Cấu hình Jenkins:** sửa `casc/jenkins.yaml` → `make restart` (JCasC nạp lại).
