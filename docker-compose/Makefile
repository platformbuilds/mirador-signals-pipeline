# Mirador Stack - Docker Compose Makefile
# Single Node and Multi-Node Cluster Management

.PHONY: help up down logs status clean volumes test health single-node multi-node-setup node1 node2 node3

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;36m
NC := \033[0m # No Color

# Configuration
COMPOSE_FILE := docker-compose.yaml
PROJECT_NAME := mirador-stack

help: ## Show this help message
	@echo "$(BLUE)Mirador Stack - Docker Compose$(NC)"
	@echo ""
	@echo "$(YELLOW)Single Node Commands:$(NC)"
	@echo "  $(GREEN)make up$(NC)              - Start the stack on single node"
	@echo "  $(GREEN)make down$(NC)            - Stop the stack"
	@echo "  $(GREEN)make restart$(NC)         - Restart the stack"
	@echo "  $(GREEN)make logs$(NC)            - Follow logs from all services"
	@echo "  $(GREEN)make status$(NC)          - Show status of all services"
	@echo "  $(GREEN)make health$(NC)          - Check health of all services"
	@echo "  $(GREEN)make clean$(NC)           - Remove containers and volumes"
	@echo ""
	@echo "$(YELLOW)Multi-Node Commands:$(NC)"
	@echo "  $(GREEN)make multi-node-setup$(NC) - Generate configs for 3-node cluster"
	@echo "  $(GREEN)make node1$(NC)            - Start node1 (requires setup)"
	@echo "  $(GREEN)make node2$(NC)            - Start node2 (requires setup)"
	@echo "  $(GREEN)make node3$(NC)            - Start node3 (requires setup)"
	@echo ""
	@echo "$(YELLOW)Utility Commands:$(NC)"
	@echo "  $(GREEN)make test$(NC)            - Test OTLP connectivity"
	@echo "  $(GREEN)make haproxy-stats$(NC)   - Open HAProxy stats page"
	@echo ""

up: ## Start the Mirador stack (single node)
	@echo "$(YELLOW)Starting Mirador Stack (Single Node)...$(NC)"
	@docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) up -d
	@echo ""
	@echo "$(GREEN)✓ Stack started successfully!$(NC)"
	@echo ""
	@$(MAKE) status
	@echo ""
	@echo "$(BLUE)Access Points:$(NC)"
	@echo "  OTLP gRPC:        localhost:4317"
	@echo "  OTLP HTTP:        localhost:4318"
	@echo "  HAProxy Stats:    http://localhost:8404 (admin/admin)"
	@echo "  Gateway Metrics:  http://localhost:8888/metrics"
	@echo "  VM Query:         http://localhost:8481"
	@echo "  VT Query:         http://localhost:8483"
	@echo "  VL Query:         http://localhost:9471"
	@echo ""

down: ## Stop the Mirador stack
	@echo "$(YELLOW)Stopping Mirador Stack...$(NC)"
	@docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) down
	@echo "$(GREEN)✓ Stack stopped$(NC)"

restart: down up ## Restart the entire stack

logs: ## Follow logs from all services
	@docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f

logs-gateway: ## Follow gateway logs
	@docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f gateway

logs-vm: ## Follow VictoriaMetrics logs
	@docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f vminsert vmselect vmstorage

logs-vt: ## Follow VictoriaTraces logs
	@docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f vtinsert vtselect vtstorage

logs-vl: ## Follow VictoriaLogs logs
	@docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f vlinsert vlselect vlstorage

status: ## Show status of all services
	@echo "$(BLUE)Service Status:$(NC)"
	@docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) ps

health: ## Check health of all services
	@echo "$(YELLOW)Checking service health...$(NC)"
	@echo ""
	@echo "$(BLUE)HAProxy:$(NC)"
	@curl -s http://localhost:8404 > /dev/null && echo "$(GREEN)✓ HAProxy is running$(NC)" || echo "$(RED)✗ HAProxy is down$(NC)"
	@echo ""
	@echo "$(BLUE)Gateway (OTLP):$(NC)"
	@curl -s http://localhost:8888/metrics > /dev/null && echo "$(GREEN)✓ Gateway is running$(NC)" || echo "$(RED)✗ Gateway is down$(NC)"
	@echo ""
	@echo "$(BLUE)VictoriaMetrics:$(NC)"
	@curl -s http://localhost:8481/health > /dev/null && echo "$(GREEN)✓ VictoriaMetrics is running$(NC)" || echo "$(RED)✗ VictoriaMetrics is down$(NC)"
	@echo ""
	@echo "$(BLUE)VictoriaLogs:$(NC)"
	@curl -s http://localhost:9471/health > /dev/null && echo "$(GREEN)✓ VictoriaLogs is running$(NC)" || echo "$(RED)✗ VictoriaLogs is down$(NC)"
	@echo ""

test: ## Test OTLP connectivity
	@echo "$(YELLOW)Testing OTLP connectivity...$(NC)"
	@echo ""
	@echo "$(BLUE)Sending test trace to OTLP endpoint...$(NC)"
	@docker run --rm --network=$(PROJECT_NAME)_mirador \
		curlimages/curl:latest \
		curl -v -X POST http://haproxy:4318/v1/traces \
		-H "Content-Type: application/json" \
		-d '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"test-service"}}]},"scopeSpans":[{"spans":[{"traceId":"5b8efff798038103d269b633813fc60c","spanId":"eee19b7ec3c1b174","name":"test-span","startTimeUnixNano":"1544712660000000000","endTimeUnixNano":"1544712661000000000"}]}]}]}' \
		2>&1 | grep -E "(HTTP|Connected)" || echo "$(RED)Failed to connect$(NC)"
	@echo ""

haproxy-stats: ## Open HAProxy stats page
	@echo "$(BLUE)Opening HAProxy Stats...$(NC)"
	@echo "URL: http://localhost:8404"
	@echo "Credentials: admin / admin"
	@command -v xdg-open > /dev/null && xdg-open http://localhost:8404 || open http://localhost:8404 || echo "Please open http://localhost:8404 manually"

clean: down ## Remove containers and volumes
	@echo "$(RED)Removing all data volumes...$(NC)"
	@docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) down -v
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

volumes: ## Show volume usage
	@echo "$(BLUE)Volume Usage:$(NC)"
	@docker volume ls | grep $(PROJECT_NAME) || echo "No volumes found"
	@echo ""
	@docker system df -v | grep $(PROJECT_NAME) || true

# ========================
# Multi-Node Cluster Setup
# ========================

multi-node-setup: ## Generate configuration for 3-node cluster
	@echo "$(YELLOW)Generating 3-node cluster configuration...$(NC)"
	@echo ""
	@echo "$(BLUE)This will create:$(NC)"
	@echo "  - node1/ (with .env and haproxy.cfg for node1)"
	@echo "  - node2/ (with .env and haproxy.cfg for node2)"
	@echo "  - node3/ (with .env and haproxy.cfg for node3)"
	@echo ""
	@echo "$(RED)WARNING: This is a template. You need to:$(NC)"
	@echo "  1. Set actual IP addresses in each node's .env file"
	@echo "  2. Copy node directories to respective machines"
	@echo "  3. Run 'make nodeX' on each machine"
	@echo ""
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		mkdir -p node1 node2 node3; \
		echo "NODE_NAME=node1" > node1/.env; \
		echo "NODE_IP=192.168.1.101" >> node1/.env; \
		echo "NODE1_IP=192.168.1.101" >> node1/.env; \
		echo "NODE2_IP=192.168.1.102" >> node1/.env; \
		echo "NODE3_IP=192.168.1.103" >> node1/.env; \
		echo "NODE_NAME=node2" > node2/.env; \
		echo "NODE_IP=192.168.1.102" >> node2/.env; \
		echo "NODE1_IP=192.168.1.101" >> node2/.env; \
		echo "NODE2_IP=192.168.1.102" >> node2/.env; \
		echo "NODE3_IP=192.168.1.103" >> node2/.env; \
		echo "NODE_NAME=node3" > node3/.env; \
		echo "NODE_IP=192.168.1.103" >> node3/.env; \
		echo "NODE1_IP=192.168.1.101" >> node3/.env; \
		echo "NODE2_IP=192.168.1.102" >> node3/.env; \
		echo "NODE3_IP=192.168.1.103" >> node3/.env; \
		cp haproxy/haproxy.cfg node1/haproxy-node1.cfg; \
		cp haproxy/haproxy.cfg node2/haproxy-node2.cfg; \
		cp haproxy/haproxy.cfg node3/haproxy-node3.cfg; \
		echo "$(GREEN)✓ Multi-node configuration created$(NC)"; \
		echo "$(YELLOW)Next steps:$(NC)"; \
		echo "  1. Edit node*/. env files with actual IPs"; \
		echo "  2. Edit node*/haproxy-node*.cfg to add backend servers"; \
		echo "  3. Deploy to each node"; \
	else \
		echo "Cancelled."; \
	fi

node1: ## Start node1 (for multi-node cluster)
	@echo "$(YELLOW)Starting Node 1...$(NC)"
	@if [ -f node1/.env ]; then \
		docker compose -f $(COMPOSE_FILE) --env-file node1/.env -p $(PROJECT_NAME)-node1 up -d; \
		echo "$(GREEN)✓ Node 1 started$(NC)"; \
	else \
		echo "$(RED)Error: Run 'make multi-node-setup' first$(NC)"; \
		exit 1; \
	fi

node2: ## Start node2 (for multi-node cluster)
	@echo "$(YELLOW)Starting Node 2...$(NC)"
	@if [ -f node2/.env ]; then \
		docker compose -f $(COMPOSE_FILE) --env-file node2/.env -p $(PROJECT_NAME)-node2 up -d; \
		echo "$(GREEN)✓ Node 2 started$(NC)"; \
	else \
		echo "$(RED)Error: Run 'make multi-node-setup' first$(NC)"; \
		exit 1; \
	fi

node3: ## Start node3 (for multi-node cluster)
	@echo "$(YELLOW)Starting Node 3...$(NC)"
	@if [ -f node3/.env ]; then \
		docker compose -f $(COMPOSE_FILE) --env-file node3/.env -p $(PROJECT_NAME)-node3 up -d; \
		echo "$(GREEN)✓ Node 3 started$(NC)"; \
	else \
		echo "$(RED)Error: Run 'make multi-node-setup' first$(NC)"; \
		exit 1; \
	fi

.DEFAULT_GOAL := help
