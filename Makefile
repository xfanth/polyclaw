# =============================================================================
# OpenClaw Docker Makefile
# =============================================================================
# Convenient commands for managing OpenClaw Docker deployment
# =============================================================================

.PHONY: help build up down logs shell config test smoke-test clean update restart status

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
NC := \033[0m # No Color

# =============================================================================
# Help
# =============================================================================
help: ## Show this help message
	@echo "$(BLUE)OpenClaw Docker - Available Commands:$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

# =============================================================================
# Setup
# =============================================================================
setup: ## Initial setup - copy .env.example to .env
	@if [ ! -f .env ]; then \
		echo "$(BLUE)Creating .env file...$(NC)"; \
		cp .env.example .env; \
		echo "$(GREEN)Created .env file. Please edit it with your configuration.$(NC)"; \
	else \
		echo "$(YELLOW).env file already exists.$(NC)"; \
	fi

# =============================================================================
# Build
# =============================================================================
build: ## Build the Docker image locally
	@echo "$(BLUE)Building OpenClaw Docker image...$(NC)"
	docker compose build --no-cache
	@echo "$(GREEN)Build complete!$(NC)"

build-quick: ## Build the Docker image using cache
	@echo "$(BLUE)Building OpenClaw Docker image (using cache)...$(NC)"
	docker compose build
	@echo "$(GREEN)Build complete!$(NC)"

# =============================================================================
# Run
# =============================================================================
up: ## Start OpenClaw in detached mode
	@echo "$(BLUE)Starting OpenClaw...$(NC)"
	docker compose up -d
	@echo "$(GREEN)OpenClaw started!$(NC)"
	@echo "Access the web interface at: $(YELLOW)http://localhost:8080$(NC)"

up-fg: ## Start OpenClaw in foreground mode (for debugging)
	@echo "$(BLUE)Starting OpenClaw in foreground mode...$(NC)"
	docker compose up

down: ## Stop and remove OpenClaw containers
	@echo "$(BLUE)Stopping OpenClaw...$(NC)"
	docker compose down
	@echo "$(GREEN)OpenClaw stopped!$(NC)"

down-volumes: ## Stop and remove containers AND volumes (WARNING: deletes data!)
	@echo "$(RED)WARNING: This will delete all data!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker compose down -v; \
		echo "$(GREEN)Containers and volumes removed!$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled.$(NC)"; \
	fi

# =============================================================================
# Logs
# =============================================================================
logs: ## View OpenClaw logs
	docker compose logs -f openclaw

logs-browser: ## View browser sidecar logs
	docker compose logs -f browser

logs-all: ## View all logs
	docker compose logs -f

# =============================================================================
# Shell Access
# =============================================================================
shell: ## Open shell in OpenClaw container
	docker compose exec openclaw bash

shell-root: ## Open shell as root in OpenClaw container
	docker compose exec --user root openclaw bash

shell-browser: ## Open shell in browser container
	docker compose exec browser bash

# =============================================================================
# Configuration
# =============================================================================
config: ## Generate and view openclaw.json configuration
	@echo "$(BLUE)Generating configuration...$(NC)"
	docker compose exec openclaw cat /data/.openclaw/openclaw.json | jq .

config-edit: ## Edit configuration file directly
	@$${EDITOR:-nano} data/.openclaw/openclaw.json

env-edit: ## Edit environment file
	@$${EDITOR:-nano} .env

# =============================================================================
# Status & Info
# =============================================================================
status: ## Show container status
	@echo "$(BLUE)Container Status:$(NC)"
	docker compose ps
	@echo ""
	@echo "$(BLUE)Resource Usage:$(NC)"
	docker stats --no-stream openclaw-gateway browser 2>/dev/null || docker stats --no-stream

health: ## Check OpenClaw health
	@echo "$(BLUE)Checking OpenClaw health...$(NC)"
	@curl -s http://localhost:8080/healthz && echo " $(GREEN)✓ Healthy$(NC)" || echo " $(RED)✗ Unhealthy$(NC)"

version: ## Show OpenClaw version
	@echo "$(BLUE)OpenClaw Version:$(NC)"
	docker compose exec openclaw openclaw --version 2>/dev/null || echo "$(YELLOW)Could not get version$(NC)"

# =============================================================================
# Updates
# =============================================================================
update: ## Pull latest image and restart
	@echo "$(BLUE)Pulling latest image...$(NC)"
	docker compose pull
	@echo "$(BLUE)Restarting OpenClaw...$(NC)"
	docker compose up -d
	@echo "$(GREEN)Update complete!$(NC)"

update-build: ## Rebuild from source and restart
	@echo "$(BLUE)Rebuilding image...$(NC)"
	docker compose build --no-cache
	@echo "$(BLUE)Restarting OpenClaw...$(NC)"
	docker compose up -d
	@echo "$(GREEN)Rebuild complete!$(NC)"

# =============================================================================
# Maintenance
# =============================================================================
restart: ## Restart OpenClaw containers
	@echo "$(BLUE)Restarting OpenClaw...$(NC)"
	docker compose restart
	@echo "$(GREEN)Restart complete!$(NC)"

prune: ## Clean up unused Docker resources
	@echo "$(BLUE)Cleaning up unused Docker resources...$(NC)"
	docker system prune -f
	@echo "$(GREEN)Cleanup complete!$(NC)"

backup: ## Backup OpenClaw data
	@echo "$(BLUE)Creating backup...$(NC)"
	@mkdir -p backups
	@tar czf backups/openclaw-backup-$$(date +%Y%m%d-%H%M%S).tar.gz data/ 2>/dev/null || echo "$(YELLOW)No data directory found$(NC)"
	@echo "$(GREEN)Backup created in backups/ directory$(NC)"

clean: ## Remove all containers, images, and volumes (WARNING: destructive!)
	@echo "$(RED)WARNING: This will delete all containers, images, and volumes!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker compose down -v --rmi all; \
		docker system prune -f; \
		echo "$(GREEN)Cleanup complete!$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled.$(NC)"; \
	fi

# =============================================================================
# Testing
# =============================================================================
test: ## Run basic tests
	@echo "$(BLUE)Running tests...$(NC)"
	@echo "$(BLUE)1. Checking if containers are running...$(NC)"
	@docker compose ps | grep -q "openclaw" && echo "$(GREEN)✓ OpenClaw container is running$(NC)" || echo "$(RED)✗ OpenClaw container is not running$(NC)"
	@echo "$(BLUE)2. Checking health endpoint...$(NC)"
	@curl -s http://localhost:8080/healthz > /dev/null && echo "$(GREEN)✓ Health endpoint is responding$(NC)" || echo "$(RED)✗ Health endpoint is not responding$(NC)"
	@echo "$(BLUE)3. Checking configuration...$(NC)"
	@docker compose exec openclaw test -f /data/.openclaw/openclaw.json && echo "$(GREEN)✓ Configuration file exists$(NC)" || echo "$(RED)✗ Configuration file not found$(NC)"
	@echo "$(GREEN)Tests complete!$(NC)"

smoke-test: ## Run comprehensive smoke tests (builds image and tests from scratch)
	@echo "$(BLUE)Running smoke tests...$(NC)"
	@chmod +x scripts/smoke-test.sh
	@./scripts/smoke-test.sh

# =============================================================================
# WhatsApp
# =============================================================================
whatsapp-qr: ## Show WhatsApp QR code for pairing
	@echo "$(BLUE)Showing WhatsApp QR code (press Ctrl+C to exit)...$(NC)"
	docker compose logs -f openclaw | grep -A 20 "QR code"

whatsapp-pair: ## Show WhatsApp pairing code
	@echo "$(BLUE)Showing WhatsApp pairing code...$(NC)"
	docker compose logs -f openclaw | grep -i "pairing\|code"

# =============================================================================
# Development
# =============================================================================
dev-build: ## Build for development with hot reload
	@echo "$(BLUE)Building development image...$(NC)"
	docker compose -f docker-compose.yml -f docker-compose.dev.yml build

dev-up: ## Start in development mode
	@echo "$(BLUE)Starting in development mode...$(NC)"
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up

lint: ## Lint Dockerfile
	@echo "$(BLUE)Linting Dockerfile...$(NC)"
	@which hadolint > /dev/null || (echo "$(YELLOW)Installing hadolint...$(NC)" && curl -sSL https://github.com/hadolint/hadolint/releases/download/v2.12.0/hadolint-Linux-x86_64 -o /tmp/hadolint && chmod +x /tmp/hadolint)
	/tmp/hadolint Dockerfile || echo "$(YELLOW)Linting complete with warnings$(NC)"
