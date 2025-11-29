#!/bin/bash

# ========================================
# Weblate Translation Platform Launcher
# ========================================
# Detects CPU architecture and starts services

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

echo "=========================================="
echo "  Weblate Translation Platform"
echo "=========================================="
echo ""

# ========================================
# Detect CPU Architecture
# ========================================
log_info "Detecting CPU architecture..."

ARCH=$(uname -m)
PLATFORM=""

case $ARCH in
    x86_64)
        PLATFORM="linux/amd64"
        log_success "Detected: x86_64 (Intel/AMD 64-bit)"
        ;;
    aarch64|arm64)
        PLATFORM="linux/arm64"
        log_success "Detected: ARM64 (Apple Silicon / ARM)"
        ;;
    armv7l)
        PLATFORM="linux/arm/v7"
        log_success "Detected: ARMv7 (32-bit ARM)"
        ;;
    *)
        log_warning "Unknown architecture: $ARCH"
        log_info "Defaulting to linux/amd64"
        PLATFORM="linux/amd64"
        ;;
esac

export DOCKER_DEFAULT_PLATFORM=$PLATFORM
echo ""

# ========================================
# Check if .env exists
# ========================================
if [ ! -f .env ]; then
    log_error ".env file not found!"
    log_info "Please create .env from .env.template:"
    log_info "  cp .env.template .env"
    log_info "  nano .env"
    exit 1
fi

# ========================================
# User Choice: Architecture Override
# ========================================
log_info "Current platform: $PLATFORM"
echo ""
read -p "Use this platform? (y/n) [y]: " USE_DETECTED
USE_DETECTED=${USE_DETECTED:-y}

if [[ ! "$USE_DETECTED" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Available platforms:"
    echo "  1) linux/amd64    - Intel/AMD 64-bit (x86_64)"
    echo "  2) linux/arm64    - ARM 64-bit (Apple Silicon, AWS Graviton)"
    echo "  3) linux/arm/v7   - ARM 32-bit (Raspberry Pi)"
    echo ""
    read -p "Select platform (1-3): " PLATFORM_CHOICE

    case $PLATFORM_CHOICE in
        1)
            PLATFORM="linux/amd64"
            ;;
        2)
            PLATFORM="linux/arm64"
            ;;
        3)
            PLATFORM="linux/arm/v7"
            ;;
        *)
            log_error "Invalid choice, using detected platform"
            ;;
    esac

    export DOCKER_DEFAULT_PLATFORM=$PLATFORM
    log_success "Platform set to: $PLATFORM"
fi

echo ""

# ========================================
# Display Memory Configuration
# ========================================
log_info "Memory limits configured:"
echo "  - PostgreSQL:  512M (reserved: 256M)"
echo "  - Redis:       256M (reserved: 64M)"
echo "  - Weblate:     2G   (reserved: 1G)"
echo "  - Nginx:       128M (reserved: 64M)"
echo "  - GitLab:      2.5G (reserved: 1.5G)"
echo "  - Webhook:     128M (reserved: 32M)"
echo ""
log_info "Total estimated usage: ~5.5GB RAM"
echo ""

# ========================================
# Docker Hub Build Option
# ========================================
if [ -n "$DOCKER_HUB_USERNAME" ] && [ -n "$DOCKER_HUB_TOKEN" ] && [ -n "$DOCKER_HUB_WEBHOOK_REPO" ]; then
    log_info "Docker Hub configuration detected"
    echo ""
    read -p "Build and push multi-platform image to Docker Hub? (y/n) [n]: " BUILD_PUSH
    BUILD_PUSH=${BUILD_PUSH:-n}

    if [[ "$BUILD_PUSH" =~ ^[Yy]$ ]]; then
        echo ""
        read -p "Enter version tag [latest]: " VERSION_TAG
        VERSION_TAG=${VERSION_TAG:-latest}

        log_info "Building and pushing to Docker Hub..."
        if ./build-and-push.sh "$VERSION_TAG"; then
            log_success "Image pushed successfully!"
            echo ""

            # Ask if they want to use the Docker Hub image
            read -p "Use the Docker Hub image instead of local build? (y/n) [y]: " USE_HUB_IMAGE
            USE_HUB_IMAGE=${USE_HUB_IMAGE:-y}

            if [[ "$USE_HUB_IMAGE" =~ ^[Yy]$ ]]; then
                log_info "Updating docker-compose.yml to use Docker Hub image..."

                # Backup
                cp docker-compose.yml docker-compose.yml.bak

                # Check if image line already exists
                if grep -q "image:.*webhook" docker-compose.yml; then
                    # Update existing image line
                    sed -i.tmp "s|image:.*webhook.*|image: ${DOCKER_HUB_WEBHOOK_REPO}:latest|" docker-compose.yml
                else
                    # Remove build section and add image
                    sed -i.tmp '/webhook-reloader:/,/container_name:/ {
                        /build:/,/dockerfile:/d
                    }' docker-compose.yml
                    sed -i.tmp "/webhook-reloader:/a\\
    image: ${DOCKER_HUB_WEBHOOK_REPO}:latest" docker-compose.yml
                fi

                rm -f docker-compose.yml.tmp
                log_success "Updated to use Docker Hub image"
            fi
        else
            log_warning "Build failed, continuing with local build..."
        fi
        echo ""
    fi
fi

# ========================================
# Start Services
# ========================================
log_info "Starting Docker Compose services..."
echo ""

if docker compose up -d --build; then
    echo ""
    log_success "Services started successfully!"
    echo ""
    echo "=========================================="
    echo "  Access Points"
    echo "=========================================="
    echo ""
    echo "Weblate:  https://$(grep WEBLATE_SITE_DOMAIN .env | cut -d'=' -f2)"
    echo "GitLab:   https://gitlab.local:8081"
    echo ""
    log_info "To view logs: docker compose logs -f"
    log_info "To stop:      docker compose down"
    echo ""
else
    log_error "Failed to start services"
    exit 1
fi
