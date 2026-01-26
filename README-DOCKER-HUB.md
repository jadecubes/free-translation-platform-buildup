# Docker Hub Multi-Platform Image Support

This guide explains how to build and push multi-platform Docker images to Docker Hub for the webhook-reloader service.

## Why Multi-Platform Images?

Building multi-platform images allows your webhook service to run on:
- **linux/amd64** - Intel/AMD servers, traditional VPS
- **linux/arm64** - Apple Silicon Macs, AWS Graviton, modern ARM servers
- **linux/arm/v7** - Raspberry Pi, ARM single-board computers

Docker will automatically pull the correct image for your CPU architecture.

## Setup

### 1. Create Docker Hub Account

If you don't have one: https://hub.docker.com/signup

### 2. Create Access Token

1. Go to https://hub.docker.com/settings/security
2. Click "New Access Token"
3. Name: `weblate-webhook-builder`
4. Permissions: "Read, Write, Delete"
5. Click "Generate"
6. **Copy the token immediately** (you won't see it again)

### 3. Configure .env File

Add these settings to your `.env` file:

```bash
# Docker Hub Configuration
DOCKER_HUB_USERNAME=your-dockerhub-username
DOCKER_HUB_TOKEN=dckr_pat_xxxxxxxxxxxxxxxxxxxxx
DOCKER_HUB_WEBHOOK_REPO=your-username/weblate-webhook-reloader
DOCKER_BUILD_PLATFORMS=linux/amd64,linux/arm64
```

**Example:**
```bash
DOCKER_HUB_USERNAME=johndoe
DOCKER_HUB_TOKEN=dckr_pat_AbCdEf123456789
DOCKER_HUB_WEBHOOK_REPO=johndoe/weblate-webhook-reloader
DOCKER_BUILD_PLATFORMS=linux/amd64,linux/arm64,linux/arm/v7
```

## Usage

### Method 1: Using start.sh (Recommended)

The `start.sh` script will detect your Docker Hub configuration and offer to build:

```bash
./start.sh
```

You'll be asked:
1. Confirm your CPU architecture
2. Build and push to Docker Hub? (y/n)
3. Version tag (default: latest)
4. Use Docker Hub image or local build? (y/n)

**Example flow:**
```
[INFO] Docker Hub configuration detected

Build and push multi-platform image to Docker Hub? (y/n) [n]: y

Enter version tag [latest]: v1.0.0

[INFO] Building and pushing to Docker Hub...
[SUCCESS] Image pushed successfully!

Use the Docker Hub image instead of local build? (y/n) [y]: y
```

### Method 2: Manual Build Script

Build and push directly:

```bash
# Build with default 'latest' tag
./build-and-push.sh

# Build with specific version
./build-and-push.sh v1.0.0
```

This will:
1. Login to Docker Hub
2. Create/use a multi-platform builder
3. Build for all configured platforms
4. Push to Docker Hub
5. Tag as both `v1.0.0` and `latest` (if version specified)

### Method 3: Switch Image Source

To toggle between local build and Docker Hub image, edit `docker-compose.yml`:

**For local build:**
```yaml
webhook-reloader:
  build:
    context: .
    dockerfile: Dockerfile.webhook
```

**For Docker Hub image:**
```yaml
webhook-reloader:
  image: your-username/weblate-webhook-reloader:latest
```

## Workflow Examples

### Scenario 1: First-Time Setup

```bash
# 1. Configure .env with Docker Hub credentials
nano .env

# 2. Run start script
./start.sh

# 3. When prompted, choose 'y' to build and push
# 4. Choose 'y' to use Docker Hub image
```

### Scenario 2: Update and Release New Version

```bash
# 1. Make changes to webhook-reload-service.py or Dockerfile.webhook

# 2. Build and push new version
./build-and-push.sh v1.1.0

# 3. Update docker-compose.yml to use new version
# Change: image: your-username/weblate-webhook-reloader:v1.1.0

# 4. Restart services
docker compose down
docker compose up -d
```

### Scenario 3: Deploy on Different Architecture

On your **ARM64 server** (e.g., AWS Graviton):

```bash
# 1. Clone repo and configure .env
git clone <your-repo>
cd myweblate
cp .env.template .env
nano .env  # Set DOCKER_HUB_WEBHOOK_REPO

# 2. Edit docker-compose.yml to use Hub image
# Change webhook-reloader from build: to image: your-username/weblate-webhook-reloader:latest

# 3. Start services
./start.sh
```

Docker automatically pulls the `linux/arm64` image!

## Understanding the Build Process

### What happens during build?

1. **Docker Login**: Authenticates with Docker Hub
2. **Buildx Setup**: Creates/uses multi-platform builder
3. **Multi-Arch Build**: Builds for each platform in parallel:
   - Pulls base images for each architecture
   - Compiles/installs dependencies per platform
   - Creates manifest list (multi-arch index)
4. **Push**: Uploads all images + manifest to Docker Hub
5. **Tagging**: Tags with version and 'latest'

### Build time expectations

- **Single platform** (amd64 only): ~2-3 minutes
- **Two platforms** (amd64 + arm64): ~4-6 minutes
- **Three platforms** (+arm/v7): ~6-10 minutes

First build is slower due to base image pulls.

## Troubleshooting

### "buildx not found"

Update Docker to latest version:
```bash
docker --version  # Should be 19.03+
```

### Build fails on specific platform

Remove problematic platform from `DOCKER_BUILD_PLATFORMS`:
```bash
# .env - Only build for amd64 and arm64
DOCKER_BUILD_PLATFORMS=linux/amd64,linux/arm64
```

### "unauthorized: incorrect username or password"

1. Check `DOCKER_HUB_USERNAME` matches your Docker Hub username exactly
2. Regenerate access token at https://hub.docker.com/settings/security
3. Update `DOCKER_HUB_TOKEN` in `.env`

### Repository not found

Create the repository on Docker Hub first:
1. Go to https://hub.docker.com/repositories
2. Click "Create Repository"
3. Name: `weblate-webhook-reloader` (or your choice)
4. Visibility: Public or Private
5. Update `DOCKER_HUB_WEBHOOK_REPO` in `.env`

### Wrong architecture pulled

Check manifest:
```bash
docker manifest inspect your-username/weblate-webhook-reloader:latest
```

Should show multiple platforms. If not, rebuild with correct `DOCKER_BUILD_PLATFORMS`.

## Advanced: Manual docker-compose.yml Configuration

### Use Local Build
```yaml
webhook-reloader:
  build:
    context: .
    dockerfile: Dockerfile.webhook
  container_name: webhook-reloader
  # ...
```

### Use Docker Hub Image
```yaml
webhook-reloader:
  image: your-username/weblate-webhook-reloader:latest
  container_name: webhook-reloader
  # ...
```

### Use Specific Version
```yaml
webhook-reloader:
  image: your-username/weblate-webhook-reloader:v1.0.0
  container_name: webhook-reloader
  # ...
```

## Security Best Practices

1. **Use Access Tokens**, not your Docker Hub password
2. **Limit token scope** to "Read, Write" only (not "Delete" if paranoid)
3. **Rotate tokens** every 6-12 months
4. **Keep .env secure** - never commit to git
   ```bash
   # Already in .gitignore, but verify:
   cat .gitignore | grep .env
   ```
5. **Use private repositories** for production images

## Cost Considerations

**Docker Hub Free Tier:**
- Unlimited public repositories
- 1 private repository
- Rate limits: 200 pulls/6 hours (authenticated)

**Pro Tier ($5/month):**
- Unlimited private repositories
- No rate limits
- Advanced features

For most users, the **free tier is sufficient**.

## Next Steps

After setting up Docker Hub integration:

1. ✅ Build and push your first image
2. ✅ Test pulling on different architecture
3. ✅ Set up CI/CD to auto-build on git push (optional)
4. ✅ Share your public image with team/community

## CI/CD Integration (Optional)

Add to `.github/workflows/docker-build.yml`:

```yaml
name: Build Multi-Platform Image

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Login to Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKER_HUB_USERNAME }}
          password: ${{ secrets.DOCKER_HUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          context: .
          file: Dockerfile.webhook
          platforms: linux/amd64,linux/arm64,linux/arm/v7
          push: true
          tags: |
            ${{ secrets.DOCKER_HUB_WEBHOOK_REPO }}:latest
            ${{ secrets.DOCKER_HUB_WEBHOOK_REPO }}:${{ github.ref_name }}
```

This auto-builds on every git tag push!
