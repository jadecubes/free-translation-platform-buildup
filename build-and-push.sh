#!/bin/bash

# ========================================
# Multi-Platform Docker Image Builder
# ========================================
# Builds and pushes webhook-reloader to Docker Hub
# Supports: amd64, arm64, arm/v7

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
echo "  Multi-Platform Image Builder"
echo "=========================================="
echo ""

# ========================================
# Load Configuration
# ========================================
if [ ! -f .env ]; then
    log_error ".env file not found!"
    log_info "Please create .env from .env.template"
    exit 1
fi

source .env

# ========================================
# Validate Configuration
# ========================================
if [ -z "$DOCKER_HUB_USERNAME" ]; then
    log_error "DOCKER_HUB_USERNAME not set in .env"
    log_info "Please configure Docker Hub settings in .env file"
    exit 1
fi

if [ -z "$DOCKER_HUB_TOKEN" ]; then
    log_error "DOCKER_HUB_TOKEN not set in .env"
    log_info "Create a token at: https://hub.docker.com/settings/security"
    exit 1
fi

if [ -z "$DOCKER_HUB_WEBHOOK_REPO" ]; then
    log_error "DOCKER_HUB_WEBHOOK_REPO not set in .env"
    log_info "Set to: ${DOCKER_HUB_USERNAME}/weblate-webhook-reloader"
    exit 1
fi

# Default platforms if not set
PLATFORMS=${DOCKER_BUILD_PLATFORMS:-"linux/amd64,linux/arm64"}

log_info "Configuration:"
echo "  Username: $DOCKER_HUB_USERNAME"
echo "  Repository: $DOCKER_HUB_WEBHOOK_REPO"
echo "  Platforms: $PLATFORMS"
echo ""

# ========================================
# Docker Login
# ========================================
log_info "Logging in to Docker Hub..."

if echo "$DOCKER_HUB_TOKEN" | docker login -u "$DOCKER_HUB_USERNAME" --password-stdin; then
    log_success "Docker Hub login successful"
else
    log_error "Docker Hub login failed"
    exit 1
fi
echo ""

# ========================================
# Check Docker Buildx
# ========================================
log_info "Checking Docker Buildx..."

if ! docker buildx version &>/dev/null; then
    log_error "Docker Buildx not found"
    log_info "Please update Docker to a version that supports Buildx"
    exit 1
fi

# Create/use multiplatform builder
if ! docker buildx inspect multiplatform &>/dev/null; then
    log_info "Creating multiplatform builder..."
    docker buildx create --name multiplatform --driver docker-container --use
else
    log_info "Using existing multiplatform builder..."
    docker buildx use multiplatform
fi

log_success "Buildx ready"
echo ""

# ========================================
# Get Version Tag
# ========================================
log_info "Version tagging..."

# Default to 'latest' unless user provides a version
VERSION=${1:-latest}

if [ "$VERSION" != "latest" ]; then
    log_info "Building version: $VERSION"
    TAGS="-t ${DOCKER_HUB_WEBHOOK_REPO}:${VERSION} -t ${DOCKER_HUB_WEBHOOK_REPO}:latest"
else
    log_info "Building version: latest"
    TAGS="-t ${DOCKER_HUB_WEBHOOK_REPO}:latest"
fi
echo ""

# ========================================
# Build and Push
# ========================================
log_info "Building multi-platform image..."
log_info "This may take several minutes..."
echo ""

if docker buildx build \
    --platform "$PLATFORMS" \
    --file Dockerfile.webhook \
    $TAGS \
    --push \
    . ; then
    echo ""
    log_success "Multi-platform image built and pushed!"
    echo ""
    echo "=========================================="
    echo "  Build Summary"
    echo "=========================================="
    echo ""
    echo "Repository: $DOCKER_HUB_WEBHOOK_REPO"
    echo "Platforms:  $PLATFORMS"
    echo "Tags:       $VERSION$([ "$VERSION" != "latest" ] && echo ", latest" || echo "")"
    echo ""
    log_info "To use this image, update docker-compose.yml:"
    echo "  webhook-reloader:"
    echo "    image: ${DOCKER_HUB_WEBHOOK_REPO}:latest"
    echo ""
else
    log_error "Build failed"
    exit 1
fi

# ========================================
# Cleanup
# ========================================
log_info "Logging out from Docker Hub..."
docker logout
log_success "Done!"
