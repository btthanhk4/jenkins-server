# bnf-service — Helm chart deployment DÙNG CHUNG

1 chart cho **mọi service BNF**. Provision hạ tầng (Deployment + Service + HPA +
Ingress) 1 lần; sau đó pipeline Jenkins update image/secret.

Đặt tên khớp cụm: `appName = {project}-{int}-{env}` →
`{appName}-deployment`, `{appName}-service`, `{appName}-hpa`, `{appName}-container`.

## Thêm service mới = tạo 1 file values

```bash
cp values.yaml values-<service>.yaml
# sửa: appName, image.repository, containerPort, fileSecrets/envFromSecrets...
```

## Provision (chạy 1 lần cho mỗi service)

```bash
helm upgrade --install bnf-wallet-be-admin ./helm/bnf-service \
  --namespace bnf-wallet-be-admin-dev-ns --create-namespace \
  -f helm/bnf-service/values-wallet-be-admin.yaml
```

Kiểm tra:
```bash
kubectl get deploy,svc,hpa -n bnf-wallet-be-admin-dev-ns
```

## Sau đó — pipeline Jenkins lo phần update

Deployment đã tồn tại → job `auto-deploy.Jenkinsfile` (action `imagebase`)
build image mới + `set image` + rollout. Không đụng cấu trúc.

## Cách nạp secret (2 kiểu)

| Kiểu | Values | Khi nào |
|---|---|---|
| **File** (app đọc file config `.env`/`.js`) | `fileSecrets` (mount volume) | dotenv, JS config module |
| **Env var** (KEY=VALUE) | `envFromSecrets` (secretRef) | secret tạo bằng `--from-env-file` |

> ENV_FILES trong pipeline tạo secret bằng `--from-file` → dùng `fileSecrets`.
> Nhớ đặt `mountPath` đúng đường dẫn app đọc config.

## Ghi chú
- `hpa.enabled: true` → chart KHÔNG set `replicas` (để HPA quản).
- Ingress mặc định tắt; bật khi cần expose ra ngoài.
- Lệnh `helm upgrade --install` idempotent: chạy lại để cập nhật cấu trúc (thêm HPA, đổi resource...) mà không tạo trùng.
