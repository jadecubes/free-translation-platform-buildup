#!/bin/bash

# ========================================
# Update Webhook Image in docker-compose.yml
# ========================================
# Switches between local build and Docker Hub image

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load .env
if [ ! -f .env ]; then
    log_error ".env file not found!"
    exit 1
fi

source .env

echo "=========================================="
echo "  Webhook Image Configuration"
echo "=========================================="
echo ""

# Check current configuration
if grep -q "build:" docker-compose.yml | grep -A5 "webhook-reloader"; then
    CURRENT="local build"
else
    CURRENT="Docker Hub image"
fi

log_info "Current configuration: $CURRENT"
echo ""

# Ask user what they want
echo "Choose webhook image source:"
echo "  1) Local build (default)"
echo "  2) Docker Hub image"
echo ""
read -p "Select (1-2): " CHOICE

case $CHOICE in
    2)
        # Switch to Docker Hub
        if [ -z "$DOCKER_HUB_WEBHOOK_REPO" ]; then
            log_error "DOCKER_HUB_WEBHOOK_REPO not set in .env"
            log_info "Please configure Docker Hub settings first"
            exit 1
        fi

        log_info "Updating docker-compose.yml to use Docker Hub image..."

        # Backup
        cp docker-compose.yml docker-compose.yml.bak

        # Replace build section with image
        sed -i.tmp '/webhook-reloader:/,/expose:/ {
            /build:/d
            /context:/d
            /dockerfile:/d
            /container_name: webhook-reloader/a\
    image: '"$DOCKER_HUB_WEBHOOK_REPO"':latest
        }' docker-compose.yml

        rm -f docker-compose.yml.tmp

        log_success "Updated to use Docker Hub image: $DOCKER_HUB_WEBHOOK_REPO:latest"
        log_info "Backup saved to: docker-compose.yml.bak"
        ;;
    1|*)
        # Switch to local build
        log_info "Updating docker-compose.yml to use local build..."

        # Backup
        cp docker-compose.yml docker-compose.yml.bak

        # Replace image with build section
        sed -i.tmp '/webhook-reloader:/,/expose:/ {
            /image: .*/d
            /container_name: webhook-reloader/a\
    build:\
      context: .\
      dockerfile: Dockerfile.webhook
        }' docker-compose.yml

        rm -f docker-compose.yml.tmp

        log_success "Updated to use local build"
        log_info "Backup saved to: docker-compose.yml.bak"
        ;;
esac

echo ""
log_info "Restart services to apply changes:"
echo "  docker compose down && docker compose up -d"
