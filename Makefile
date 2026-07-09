# ============================================================================
# Makefile tiện lợi cho vòng đời Jenkins
# Dùng: make <target>   (vd: make up)
# ============================================================================

.DEFAULT_GOAL := help
COMPOSE := docker compose
JENKINS_HOME_HOST ?= /data/jenkins_home

.PHONY: help bootstrap network build up down restart logs ps shell password backup restore pull clean

help: ## Hiển thị danh sách lệnh
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Tạo thư mục dữ liệu + phân quyền uid 1000 (chạy 1 lần, cần sudo)
	sudo mkdir -p $(JENKINS_HOME_HOST)
	sudo chown -R 1000:1000 $(JENKINS_HOME_HOST)
	@echo "OK: $(JENKINS_HOME_HOST) đã sẵn sàng (owner uid 1000)."

network: ## Tạo docker network jenkins-net nếu chưa có
	@docker network inspect jenkins-net >/dev/null 2>&1 || docker network create jenkins-net

build: ## Build image (không cache)
	$(COMPOSE) build --no-cache

up: network ## Khởi động Jenkins (nền)
	$(COMPOSE) up -d

down: ## Dừng và xoá container
	$(COMPOSE) down

restart: ## Khởi động lại (nạp lại JCasC)
	$(COMPOSE) restart

logs: ## Xem log realtime
	$(COMPOSE) logs -f jenkins

ps: ## Trạng thái container
	$(COMPOSE) ps

shell: ## Vào shell trong container
	$(COMPOSE) exec jenkins bash

password: ## In initial admin password (nếu setup wizard bật)
	$(COMPOSE) exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

backup: ## Sao lưu JENKINS_HOME
	bash scripts/backup.sh

restore: ## Khôi phục từ backup (make restore FILE=backups/xxx.tar.gz)
	bash scripts/restore.sh $(FILE)

clean: ## Dừng container (KHÔNG xoá dữ liệu bind-mount trên host)
	$(COMPOSE) down
