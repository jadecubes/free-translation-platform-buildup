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
    echo "  - GEMINI_API_KEY"
    echo ""
    echo "Then run this script again."
    exit 0
fi

# Check required env vars
source .env

if [ -z "$GEMINI_API_KEY" ] || [ "$GEMINI_API_KEY" = "your_gemini_api_key_here" ]; then
    echo "Error: GEMINI_API_KEY not set in .env"
    echo "Get your API key from: https://aistudio.google.com/app/apikey"
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
    if docker exec gitlab curl -s http://localhost/-/health > /dev/null 2>&1; then
        echo "GitLab is ready!"
        break
    fi
    sleep 5
    timeout=$((timeout - 5))
    echo "Still waiting... ($timeout seconds remaining)"
done

if [ $timeout -le 0 ]; then
    echo "GitLab is still starting. Check 'docker logs gitlab' for status."
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Open https://gitlab.local:8081"
echo "2. Login with: root / $GITLAB_ROOT_PASSWORD"
echo "3. Create a new project"
echo "4. Register GitLab Runner:"
echo "   docker exec -it gitlab-runner gitlab-runner register"
echo "5. Add your translation files and push!"
echo ""
echo "See README.md for detailed instructions."
