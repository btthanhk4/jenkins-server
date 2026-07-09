# ============================================================================
# Makefile tiện lợi cho vòng đời Jenkins
# Dùng: make <target>   (vd: make up)
# ============================================================================

.DEFAULT_GOAL := help
COMPOSE := docker compose

.PHONY: help build up down restart logs ps shell backup restore pull clean

help: ## Hiển thị danh sách lệnh
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Build image (không cache)
	$(COMPOSE) build --no-cache

up: ## Khởi động Jenkins (nền)
	$(COMPOSE) up -d

down: ## Dừng và xoá container
	$(COMPOSE) down

restart: ## Khởi động lại
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

clean: ## Dừng và XOÁ luôn volume dữ liệu (nguy hiểm)
	$(COMPOSE) down -v
