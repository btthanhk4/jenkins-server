# Jenkins DevOps Server

Hạ tầng Jenkins **All-in-One** đóng gói bằng Docker, cấu hình bằng
[Configuration as Code (JCasC)](https://github.com/jenkinsci/configuration-as-code-plugin),
đã **hardening bảo mật** và **tune JVM**, sẵn sàng deploy các dự án của công ty.

Image tích hợp sẵn: **Docker CLI + Buildx + Compose, kubectl, Helm, yq, Maven,
Node 22 + pnpm, Terraform, Vault, SonarScanner, Trivy, AWS CLI v2, Ansible**.

---

## 📁 Cấu trúc thư mục

```
jenkins-server/
├── .github/workflows/lint.yml   # CI: hadolint + shellcheck
├── docker/Dockerfile            # Image Jenkins + toàn bộ DevOps tools
├── plugins/plugins.txt          # Danh sách plugin cài sẵn khi build
├── casc/jenkins.yaml            # Cấu hình + hardening Jenkins (JCasC)
├── scripts/
│   ├── backup.sh                # Sao lưu JENKINS_HOME (bind mount)
│   └── restore.sh               # Khôi phục từ backup
├── examples/Jenkinsfile.example # Pipeline mẫu cho dự án
├── docker-compose.yml           # Service + resource limits + JVM tuning
├── .env.example                 # Mẫu biến môi trường (copy -> .env)
├── .gitignore / .dockerignore / .gitattributes
├── Makefile                     # Lệnh tắt: make bootstrap/up/logs...
├── LICENSE
└── README.md
```

---

## 🚀 Cài đặt trên VM

> Đã kiểm chứng trên: Proxmox VE → Ubuntu Server 24.04 LTS, IP `192.168.10.185`.

### 1. Yêu cầu
- Docker Engine + Docker Compose plugin đã cài trên host.
- User hiện tại thuộc group `docker`.

### 2. Lấy source & cấu hình
```bash
git clone https://github.com/btthanhk4/jenkins-server.git
cd jenkins-server
cp .env.example .env
nano .env        # đổi mật khẩu admin, JENKINS_URL, DOCKER_GID...
```

Lấy đúng **GID của group docker** để Jenkins gọi được `docker.sock`:
```bash
getent group docker | cut -d: -f3     # dán số này vào DOCKER_GID trong .env
```

### 3. Khởi tạo thư mục dữ liệu (1 lần)
```bash
make bootstrap   # tạo /data/jenkins_home + chown 1000:1000
```

### 4. Build & chạy
```bash
make build       # docker compose build --no-cache
make up          # tự tạo network jenkins-net rồi up -d
make logs        # theo dõi khởi động
```

Truy cập: **http://192.168.10.185:8080** — đăng nhập bằng tài khoản trong `.env`.

---

## 🔧 Lệnh thường dùng (Makefile)

| Lệnh              | Chức năng                                   |
|-------------------|---------------------------------------------|
| `make bootstrap`  | Tạo thư mục dữ liệu + phân quyền (1 lần)     |
| `make up`         | Tạo network + khởi động Jenkins             |
| `make down`       | Dừng & xoá container                        |
| `make restart`    | Khởi động lại (nạp lại JCasC)               |
| `make logs`       | Xem log realtime                            |
| `make shell`      | Vào bash trong container                    |
| `make backup`     | Sao lưu dữ liệu                             |
| `make restore FILE=backups/xxx.tar.gz` | Khôi phục              |
| `make clean`      | Dừng container (KHÔNG xoá dữ liệu host)      |

---

## ⚡ Tối ưu đã áp dụng

**Hiệu năng (JVM):** G1GC, String Deduplication, `MaxRAMPercentage=70%` (JVM tự
co giãn theo RAM container), heap dump khi OOM. Giới hạn RAM qua `JENKINS_MEM_LIMIT`.

**Bảo mật (hardening):**
- `remotingSecurity` bật, chỉ cho phép agent protocol hiện đại (`JNLP4`).
- Tắt SSHD tích hợp, CSRF crumb bật, Job DSL chạy sandbox.
- Không disable CSP, tắt gửi usage statistics ra ngoài.
- Secret nạp qua ENV/Credentials, không hardcode trong git.

**Vận hành:** healthcheck, `stop_grace_period` (drain build), log rotation,
`shm_size` lớn cho test, network external ổn định, bind mount dễ backup.

---

## 🛡️ Độ bền & tự phục hồi (VM 24GB · 12 vCPU · 150GB NVMe)

Đã tính toán cấu hình theo đúng phần cứng VM:

| Tài nguyên | Giá trị | Lý do |
|---|---|---|
| RAM Jenkins (`JENKINS_MEM_LIMIT`) | `10g` (heap ~7g) | Chừa ~14g cho OS + build container chạy qua docker.sock |
| CPU cap (`JENKINS_CPU_LIMIT`) | `10` | Chừa 2 core cho OS, tránh Jenkins làm nghẽn host |
| `numExecutors` | `4` | Cân bằng cho controller all-in-one; nâng `6` nếu build chạy trong container |
| `ulimits nofile` | `65536` | Chống "Too many open files" khi nhiều job song song |
| `pids_limit` | `8192` | Chặn fork-bomb do build lỗi |

**Ma trận các kiểu lỗi & cách hệ thống tự xử lý:**

| Kiểu lỗi | Cơ chế phục hồi |
|---|---|
| Container crash / VM reboot / mất điện | `restart: unless-stopped` (cần `systemctl enable docker`) |
| JVM hết heap (OOM) | `ExitOnOutOfMemoryError` → thoát → restart |
| Jenkins treo/deadlock (unhealthy) | sidecar `autoheal` restart sau ~15s |
| RAM vượt limit | cgroup giới hạn ở 10g, không lan sang host |
| Đầy disk (image/cache tích tụ) | `make maintenance` + cron dọn định kỳ |
| Nhiều job → cạn file descriptor | `ulimits nofile=65536` |
| Restart/nâng cấp Docker daemon | `live-restore: true` (container không bị dừng) |

### Bắt buộc làm trên host (1 lần)

**1. Bật Docker tự khởi động cùng máy:**
```bash
sudo systemctl enable docker
```

**2. Cấu hình Docker daemon** — tạo `/etc/docker/daemon.json`:
```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "storage-driver": "overlay2"
}
```
Rồi `sudo systemctl restart docker`.

**3. Cron dọn disk hằng tuần** (`crontab -e`):
```cron
0 3 * * 0 cd /home/jits/jenkins && bash scripts/docker-maintenance.sh >> /var/log/jenkins-maint.log 2>&1
```

**4. Giới hạn tài nguyên cho build container.** Build chạy qua `docker.sock` KHÔNG bị `JENKINS_MEM_LIMIT` giới hạn. Trong pipeline nên thêm `--memory` / `--cpus`:
```groovy
sh 'docker build --memory=2g --cpus=2 -t $IMAGE:$TAG .'
```

---

## 🔐 Bảo mật

- **Không bao giờ** commit `.env` hay secret (đã chặn trong `.gitignore`).
- Container gắn `docker.sock` ⇒ Jenkins có quyền tương đương root trên host. Chỉ cấp quyền cho người đáng tin.
- Production nên đặt **Nginx reverse proxy + HTTPS (Let's Encrypt)** trước Jenkins.

---

## 💾 Sao lưu & khôi phục
```bash
make backup                                        # -> backups/jenkins-home-*.tar.gz
make restore FILE=backups/jenkins-home-XXXX.tar.gz
```
Nên cron backup định kỳ và đẩy file ra lưu trữ ngoài (S3, GitLab, NAS...).

---

## 📝 Deploy dự án
1. Copy `examples/Jenkinsfile.example` vào repo dự án → đổi tên `Jenkinsfile`.
2. Jenkins: **New Item → (Multibranch) Pipeline** → trỏ tới repo.
3. Thêm credentials (GitLab/registry) trong **Manage Jenkins → Credentials**.
4. Cấu hình webhook GitLab → build tự động.

---

## 🛠 Thêm/bớt công cụ hoặc plugin
- **Plugin:** sửa `plugins/plugins.txt` → `make build` → `make up`.
- **Công cụ CLI:** thêm block `RUN` trong `docker/Dockerfile` → rebuild.
- **Cấu hình Jenkins:** sửa `casc/jenkins.yaml` → `make restart`.
