#!/bin/bash

# Setup script for GitLab + Gemini Translation Platform

set -e

echo "=== GitLab + Gemini Translation Platform Setup ==="
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "Creating .env from template..."
    cp .env.template .env
    echo ""
    echo "Please edit .env and set:"
    echo "  - GITLAB_ROOT_PASSWORD"
    echo ""
    echo "Then run this script again."
    exit 0
fi

# Check required env vars
source .env

if [ -z "$GITLAB_ROOT_PASSWORD" ] || [ "$GITLAB_ROOT_PASSWORD" = "gitlab_admin_password" ]; then
    echo "Error: GITLAB_ROOT_PASSWORD not set in .env"
    exit 1
fi

echo "Starting GitLab..."
docker compose up -d

echo ""
echo "Waiting for GitLab to initialize (this takes 2-3 minutes)..."
echo "You can check status with: docker logs -f gitlab"
echo ""

# Wait for GitLab to be healthy
timeout=300
while [ $timeout -gt 0 ]; do
    if docker exec gitlab curl -s http://localhost:8081/-/health > /dev/null 2>&1; then
        echo "GitLab is ready!"
        break
    fi
    sleep 5
    timeout=$((timeout - 5))
    echo "Still waiting... ($timeout seconds remaining)"
done

if [ $timeout -le 0 ]; then
    echo "GitLab is still starting. Check 'docker logs gitlab' for status."
    exit 1
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Add '127.0.0.1 gitlab.local' to /etc/hosts if needed"
echo "2. Open http://gitlab.local:8081"
echo "3. Login as root using the password from .env"
echo "4. Create a new project"
echo "5. Register GitLab Runner using the command in README.md"
echo "6. Add your translation files and push!"
echo ""
echo "See README.md for detailed instructions."
