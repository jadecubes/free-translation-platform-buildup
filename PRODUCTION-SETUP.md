# Production Setup Guide - Existing GitLab

Complete guide for deploying Weblate in production with an **existing GitLab instance** (GitLab.com, self-hosted, or enterprise).

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture Options](#architecture-options)
- [Recommended Setup](#recommended-setup)
- [Step-by-Step Setup](#step-by-step-setup)
- [Configuration Files](#configuration-files)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

**Production scenario:**
- ✅ You already have GitLab (GitLab.com, self-hosted, or enterprise)
- ✅ You want to add Weblate for translation management
- ✅ Weblate should connect to existing GitLab repositories
- ✅ No need for bundled GitLab container

**What we'll remove:**
- ❌ GitLab container (using your existing GitLab instead)
- ❌ Self-signed SSL certificates (use real certs)
- ❌ Development-only settings

**What we'll keep:**
- ✅ Weblate container
- ✅ PostgreSQL container (Weblate's database)
- ✅ Redis container (Weblate's cache)
- ✅ Nginx container (reverse proxy, optional)
- ✅ Webhook service (auto-translation)

---

## 🏗️ Architecture Options

### Option 1: Weblate Behind Your Existing Reverse Proxy (Recommended)

```
Internet
    ↓
Your Existing Infrastructure
    ├─→ your-domain.com/gitlab → Existing GitLab
    └─→ your-domain.com/weblate → Weblate (new)
            ↓
        Docker Compose Stack
            ├─ Weblate container
            ├─ PostgreSQL container
            ├─ Redis container
            └─ Webhook container
```

**Best for:**
- You have existing nginx/Traefik/HAProxy
- Multiple services on same server
- Centralized SSL management

### Option 2: Weblate with Own Nginx (Simpler)

```
Internet
    ↓
    Nginx container (with SSL)
        ↓
    Weblate container
        ↓
    PostgreSQL + Redis
```

**Best for:**
- Dedicated Weblate server
- Simple setup
- Direct public access

### Option 3: Weblate on Separate Server

```
[GitLab Server]          [Weblate Server]
gitlab.company.com   →   weblate.company.com
    ↓                          ↓
Existing GitLab          Docker Compose Stack
                         (Weblate + DB + Redis)
```

**Best for:**
- Large organizations
- High traffic
- Maximum isolation

---

## ✅ Recommended Setup

**I recommend Option 2** for most cases: Weblate with its own Nginx and real SSL certificates.

**Why:**
- ✅ Self-contained (easy to deploy)
- ✅ Production-ready SSL
- ✅ Can run on dedicated server or shared
- ✅ Easy to scale later
- ✅ Works with any GitLab (cloud or self-hosted)

---

## 🚀 Step-by-Step Setup

### Prerequisites

1. **Server requirements:**
   - 4-6GB RAM (after optimization)
   - 20GB disk space
   - Docker & Docker Compose installed
   - Public IP or domain name

2. **GitLab access:**
   - Existing GitLab instance (GitLab.com or self-hosted)
   - Admin access to repositories you want to translate
   - Ability to add deploy keys and webhooks

3. **Domain/DNS:**
   - Domain or subdomain for Weblate (e.g., `weblate.company.com`)
   - DNS A record pointing to your server

4. **SSL Certificate:**
   - Option A: Let's Encrypt (recommended, free)
   - Option B: Your company's SSL certificate

---

### Step 1: Clone and Prepare

```bash
# On your production server
cd /opt  # or your preferred location
git clone <this-repo> weblate-production
cd weblate-production

# Create production compose file
cp docker-compose.yml docker-compose.prod.yml
```

---

### Step 2: Create Production Docker Compose

Edit `docker-compose.prod.yml`:

```yaml
version: '3'

services:
  # PostgreSQL Database
  database:
    image: postgres:15-alpine
    container_name: weblate_postgres
    env_file:
      - .env.production
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    restart: always
    networks:
      - weblate-network
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M

  # Redis Cache
  redis:
    image: redis:7-alpine
    container_name: weblate_redis
    restart: always
    command: redis-server --appendonly yes --maxmemory 128mb --maxmemory-policy allkeys-lru
    volumes:
      - redis-data:/data
    networks:
      - weblate-network
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 64M

  # Weblate Service
  weblate:
    image: weblate/weblate:latest
    container_name: weblate
    env_file:
      - .env.production
    volumes:
      - ./weblate-data:/app/data
    expose:
      - "8080"
    restart: always
    depends_on:
      - database
      - redis
    networks:
      - weblate-network
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G
    environment:
      # Production settings
      WEBLATE_DEBUG: 0
      WEBLATE_ENABLE_HTTPS: 1
      WEBLATE_REQUIRE_LOGIN: 1

      # From .env.production
      WEBLATE_SITE_DOMAIN: ${WEBLATE_SITE_DOMAIN}
      WEBLATE_ADMIN_PASSWORD: ${WEBLATE_ADMIN_PASSWORD}
      WEBLATE_ADMIN_EMAIL: ${WEBLATE_ADMIN_EMAIL}
      WEBLATE_ADMIN_NAME: ${WEBLATE_ADMIN_NAME}
      WEBLATE_SERVER_EMAIL: ${WEBLATE_SERVER_EMAIL}
      WEBLATE_DEFAULT_FROM_EMAIL: ${WEBLATE_DEFAULT_FROM_EMAIL}
      WEBLATE_ALLOWED_HOSTS: ${WEBLATE_ALLOWED_HOSTS}
      WEBLATE_SECRET_KEY: ${WEBLATE_SECRET_KEY}

      # Email settings (for notifications)
      WEBLATE_EMAIL_HOST: ${WEBLATE_EMAIL_HOST}
      WEBLATE_EMAIL_PORT: ${WEBLATE_EMAIL_PORT}
      WEBLATE_EMAIL_HOST_USER: ${WEBLATE_EMAIL_HOST_USER}
      WEBLATE_EMAIL_HOST_PASSWORD: ${WEBLATE_EMAIL_HOST_PASSWORD}
      WEBLATE_EMAIL_USE_TLS: ${WEBLATE_EMAIL_USE_TLS}

      # Database
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_DATABASE: ${POSTGRES_DATABASE}
      POSTGRES_HOST: database
      POSTGRES_PORT: 5432

      # Redis
      REDIS_HOST: redis
      REDIS_PORT: 6379

      # Google Translate
      WEBLATE_MT_GOOGLE_KEY: ${WEBLATE_MT_GOOGLE_KEY}

  # Nginx Reverse Proxy with SSL
  nginx:
    image: nginx:alpine
    container_name: weblate_nginx
    ports:
      - "443:443"
      - "80:80"
    volumes:
      - ./nginx/conf/weblate-prod.conf:/etc/nginx/conf.d/default.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - /var/www/certbot:/var/www/certbot:ro  # For Let's Encrypt
    depends_on:
      - weblate
    restart: always
    networks:
      - weblate-network
    deploy:
      resources:
        limits:
          memory: 128M
        reservations:
          memory: 64M

  # Webhook Auto-Translation Service
  webhook-reloader:
    # Option 1: Use Docker Hub image (recommended for production)
    image: ${DOCKER_HUB_WEBHOOK_REPO}:latest

    # Option 2: Build locally (if you've made customizations)
    # build:
    #   context: .
    #   dockerfile: Dockerfile.webhook

    container_name: webhook-reloader
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - weblate-network
    restart: always
    expose:
      - "5000"
    deploy:
      resources:
        limits:
          memory: 128M
        reservations:
          memory: 32M
    environment:
      # Production mode
      FLASK_ENV: production

  # Certbot for SSL (Let's Encrypt)
  certbot:
    image: certbot/certbot:latest
    container_name: certbot
    volumes:
      - ./ssl:/etc/letsencrypt
      - /var/www/certbot:/var/www/certbot
    networks:
      - weblate-network
    # Run once to get certificate, then can be removed
    # command: certonly --webroot -w /var/www/certbot --email admin@example.com -d weblate.company.com --agree-tos

networks:
  weblate-network:
    driver: bridge

volumes:
  redis-data:
```

**Key differences from dev setup:**
- ❌ No GitLab container
- ✅ Production environment variables
- ✅ Real SSL setup with certbot
- ✅ restart: always (not unless-stopped)
- ✅ Proper email configuration
- ✅ Security hardening

---

### Step 3: Create Production Environment File

Create `.env.production`:

```bash
# ========================================
# PRODUCTION Configuration
# ========================================

# ========================================
# Database
# ========================================
POSTGRES_PASSWORD=<generate-strong-password>
POSTGRES_USER=weblate
POSTGRES_DATABASE=weblate

# ========================================
# Weblate Admin
# ========================================
WEBLATE_ADMIN_NAME=Admin
WEBLATE_ADMIN_EMAIL=admin@company.com
WEBLATE_ADMIN_PASSWORD=<generate-strong-password>

# ========================================
# Site Configuration
# ========================================
WEBLATE_SITE_TITLE=Company Translation Platform
WEBLATE_SITE_DOMAIN=weblate.company.com
WEBLATE_ALLOWED_HOSTS=weblate.company.com
WEBLATE_CSRF_TRUSTED_ORIGINS=https://weblate.company.com

# Secret key - generate with: openssl rand -base64 50
WEBLATE_SECRET_KEY=<generate-random-50-char-string>

# Security
WEBLATE_DEBUG=0
WEBLATE_ENABLE_HTTPS=1
WEBLATE_REQUIRE_LOGIN=1

# ========================================
# Email Configuration (IMPORTANT for production!)
# ========================================
# Option 1: SMTP (Gmail, SendGrid, etc.)
WEBLATE_EMAIL_HOST=smtp.gmail.com
WEBLATE_EMAIL_PORT=587
WEBLATE_EMAIL_HOST_USER=your-email@company.com
WEBLATE_EMAIL_HOST_PASSWORD=<app-password>
WEBLATE_EMAIL_USE_TLS=1
WEBLATE_SERVER_EMAIL=weblate@company.com
WEBLATE_DEFAULT_FROM_EMAIL=weblate@company.com

# Option 2: AWS SES
# WEBLATE_EMAIL_HOST=email-smtp.us-east-1.amazonaws.com
# WEBLATE_EMAIL_PORT=587
# WEBLATE_EMAIL_HOST_USER=<aws-ses-smtp-username>
# WEBLATE_EMAIL_HOST_PASSWORD=<aws-ses-smtp-password>

# ========================================
# GitLab Configuration (YOUR EXISTING GITLAB)
# ========================================
# For GitLab.com
GITLAB_URL=https://gitlab.com
GITLAB_PROJECT_NAMESPACE=your-company
GITLAB_PROJECT_NAME=your-translation-project
GITLAB_REPO_URL=git@gitlab.com:your-company/your-translation-project.git
GITLAB_BRANCH=main

# For Self-Hosted GitLab
# GITLAB_URL=https://gitlab.company.com
# GITLAB_PROJECT_NAMESPACE=translation-team
# GITLAB_PROJECT_NAME=app-translations
# GITLAB_REPO_URL=git@gitlab.company.com:translation-team/app-translations.git
# GITLAB_BRANCH=main

# GitLab Personal Access Token (create in GitLab → Settings → Access Tokens)
# Scopes needed: api, read_repository, write_repository
GITLAB_API_TOKEN=<your-gitlab-personal-access-token>

# ========================================
# Translation Configuration
# ========================================
SOURCE_LANGUAGE=en_US
TARGET_LANGUAGES=ja,fr,de,es,zh_Hans,zh_Hant

FILE_MASK=locales/*.json
FILE_FORMAT=json-nested
NEW_BASE=locales/en-US.json

# ========================================
# Google Translate API
# ========================================
WEBLATE_MT_GOOGLE_KEY=<your-google-translate-api-key>

# ========================================
# Weblate Project
# ========================================
WEBLATE_PROJECT_NAME="Company Translations"
WEBLATE_PROJECT_SLUG=company-translations
WEBLATE_COMPONENT_NAME=main
WEBLATE_COMPONENT_SLUG=main

# Auto-translation
AUTO_TRANSLATE_ENABLED=true
AUTO_TRANSLATE_MODE=translate
AUTO_TRANSLATE_THRESHOLD=80

WEBLATE_ADMIN_USER=admin

# ========================================
# Docker Hub (optional - for webhook image)
# ========================================
DOCKER_HUB_WEBHOOK_REPO=your-username/weblate-webhook-reloader
```

**Security checklist:**
- [ ] Generated strong passwords (not defaults)
- [ ] Created unique SECRET_KEY
- [ ] Configured real email (not localhost)
- [ ] Set WEBLATE_DEBUG=0
- [ ] Set WEBLATE_REQUIRE_LOGIN=1
- [ ] Using HTTPS only

---

### Step 4: Generate SSL Certificate

**Option A: Let's Encrypt (Recommended)**

```bash
# 1. First, create temporary nginx config for certificate challenge
cat > nginx/conf/weblate-prod.conf << 'EOF'
server {
    listen 80;
    server_name weblate.company.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
EOF

# 2. Start nginx temporarily
docker compose -f docker-compose.prod.yml up -d nginx

# 3. Get certificate
docker compose -f docker-compose.prod.yml run --rm certbot \
    certonly --webroot \
    -w /var/www/certbot \
    --email admin@company.com \
    -d weblate.company.com \
    --agree-tos \
    --no-eff-email

# 4. Certificates will be in: ./ssl/live/weblate.company.com/
```

**Option B: Your Own Certificate**

```bash
# Copy your certificates
mkdir -p ssl
cp /path/to/your/certificate.crt ssl/weblate.company.com.crt
cp /path/to/your/private.key ssl/weblate.company.com.key
chmod 600 ssl/weblate.company.com.key
```

---

### Step 5: Create Production Nginx Config

Create `nginx/conf/weblate-prod.conf`:

```nginx
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name weblate.company.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS Server
server {
    listen 443 ssl http2;
    server_name weblate.company.com;

    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/live/weblate.company.com/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/weblate.company.com/privkey.pem;

    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Client Max Body Size (for uploads)
    client_max_body_size 100M;

    # Logging
    access_log /var/log/nginx/weblate_access.log;
    error_log /var/log/nginx/weblate_error.log;

    # Proxy to Weblate
    location / {
        proxy_pass http://weblate:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;

        # Timeouts
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 600;
    }

    # Static files (if served separately)
    location /static/ {
        alias /app/data/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location /media/ {
        alias /app/data/media/;
        expires 7d;
    }
}
```

---

### Step 6: Start Production Services

```bash
# Create necessary directories
mkdir -p postgres-data weblate-data ssl nginx/conf

# Set proper permissions
chmod 700 postgres-data weblate-data

# Start services
docker compose -f docker-compose.prod.yml up -d

# Check logs
docker compose -f docker-compose.prod.yml logs -f

# Wait for services to be ready (2-3 minutes)
docker compose -f docker-compose.prod.yml ps
```

---

### Step 7: Configure GitLab Integration

**7.1. Generate SSH Key in Weblate**

```bash
# Generate SSH key
docker exec weblate bash -c '
if [ ! -f /app/data/ssh/id_rsa ]; then
    mkdir -p /app/data/ssh
    ssh-keygen -t rsa -b 4096 -f /app/data/ssh/id_rsa -N "" -C "weblate@company.com"
fi
'

# Get public key
docker exec weblate cat /app/data/ssh/id_rsa.pub > weblate_ssh_key.pub

echo "Add this key to GitLab:"
cat weblate_ssh_key.pub
```

**7.2. Add Deploy Key to GitLab**

**For GitLab.com:**
1. Go to: `https://gitlab.com/your-company/your-project/-/settings/repository`
2. Expand "Deploy Keys"
3. Click "Add new key"
4. Title: `Weblate Production`
5. Key: Paste from `weblate_ssh_key.pub`
6. ✅ **Check "Grant write permissions"** (IMPORTANT!)
7. Click "Add key"

**For Self-Hosted GitLab:**
1. Go to: `https://gitlab.company.com/your-project/-/settings/repository`
2. Same steps as above

**7.3. Configure SSH Known Hosts**

```bash
# For GitLab.com
docker exec weblate bash -c "
mkdir -p /app/data/ssh
ssh-keyscan -H gitlab.com >> /app/data/ssh/known_hosts 2>/dev/null
chmod 600 /app/data/ssh/known_hosts
"

# For Self-Hosted GitLab
docker exec weblate bash -c "
mkdir -p /app/data/ssh
ssh-keyscan -H gitlab.company.com >> /app/data/ssh/known_hosts 2>/dev/null
chmod 600 /app/data/ssh/known_hosts
"

# Create SSH config
docker exec weblate bash -c "cat > /app/data/ssh/config << 'EOF'
# For GitLab.com
Host gitlab.com
    HostName gitlab.com
    User git
    IdentityFile /app/data/ssh/id_rsa
    StrictHostKeyChecking no

# For Self-Hosted (if applicable)
Host gitlab.company.com
    HostName gitlab.company.com
    User git
    IdentityFile /app/data/ssh/id_rsa
    StrictHostKeyChecking no
EOF
chmod 600 /app/data/ssh/config
"
```

**7.4. Test SSH Connection**

```bash
# For GitLab.com
docker exec weblate ssh -T git@gitlab.com

# Expected output:
# Welcome to GitLab, @your-username!

# For Self-Hosted
docker exec weblate ssh -T git@gitlab.company.com
```

---

### Step 8: Create Weblate Project

```bash
# Create production setup script
cat > setup-production.sh << 'EOF'
#!/bin/bash
set -e
source .env.production

# Create Weblate project
docker exec weblate weblate shell << PYEOF
from weblate.trans.models import Project, Component
from weblate.auth.models import User

# Get admin user
admin = User.objects.get(username='${WEBLATE_ADMIN_USER}')

# Create project
project, created = Project.objects.get_or_create(
    slug='${WEBLATE_PROJECT_SLUG}',
    defaults={
        'name': '${WEBLATE_PROJECT_NAME}',
        'web': '${GITLAB_URL}/${GITLAB_PROJECT_NAMESPACE}/${GITLAB_PROJECT_NAME}',
    }
)

print(f"Project: {project.name} ({'created' if created else 'exists'})")

# Create component
component, created = Component.objects.get_or_create(
    project=project,
    slug='${WEBLATE_COMPONENT_SLUG}',
    defaults={
        'name': '${WEBLATE_COMPONENT_NAME}',
        'repo': '${GITLAB_REPO_URL}',
        'branch': '${GITLAB_BRANCH}',
        'filemask': '${FILE_MASK}',
        'file_format': '${FILE_FORMAT}',
        'new_base': '${NEW_BASE}',
        'vcs': 'git',
        'push_on_commit': True,
        'commit_pending_age': 0,
    }
)

print(f"Component: {component.name} ({'created' if created else 'exists'})")

# Initial update
component.do_update()
print("Repository updated successfully!")

PYEOF

echo "✅ Weblate project configured!"
EOF

chmod +x setup-production.sh
./setup-production.sh
```

---

### Step 9: Configure GitLab Webhooks

**9.1. Create Personal Access Token in GitLab**

**For GitLab.com:**
1. Go to: `https://gitlab.com/-/profile/personal_access_tokens`
2. Name: `Weblate Webhook`
3. Scopes: ✅ `api`, ✅ `read_repository`, ✅ `write_repository`
4. Click "Create personal access token"
5. **Copy the token** → Add to `.env.production` as `GITLAB_API_TOKEN`

**For Self-Hosted:**
1. Go to: `https://gitlab.company.com/-/profile/personal_access_tokens`
2. Same steps as above

**9.2. Create Webhooks**

```bash
# Load environment
source .env.production

# Create Webhook 1: Weblate notification
curl --request POST \
    --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" \
    --header "Content-Type: application/json" \
    --data '{
        "url": "https://weblate.company.com/hooks/gitlab/",
        "push_events": true,
        "enable_ssl_verification": true
    }' \
    "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_NAMESPACE}%2F${GITLAB_PROJECT_NAME}/hooks"

# Create Webhook 2: Auto-translation
curl --request POST \
    --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" \
    --header "Content-Type: application/json" \
    --data '{
        "url": "https://weblate.company.com/webhook-reload",
        "push_events": true,
        "enable_ssl_verification": true
    }' \
    "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_NAMESPACE}%2F${GITLAB_PROJECT_NAME}/hooks"

echo "✅ Webhooks configured!"
```

**Or manually in GitLab:**
1. Go to: Project → Settings → Webhooks
2. Add both webhooks with URLs above
3. Check "Push events"
4. Click "Add webhook"

---

### Step 10: Test the Setup

```bash
# 1. Access Weblate
open https://weblate.company.com

# 2. Login with admin credentials from .env.production

# 3. Check project
# Should see your GitLab project connected

# 4. Test translation
# Edit a string → Save → Check if pushed to GitLab

# 5. Test webhook
# Push to GitLab → Check Weblate updates

# 6. Check logs
docker compose -f docker-compose.prod.yml logs -f webhook-reloader
```

---

## 🔒 Security Considerations

### 1. **Firewall Configuration**

```bash
# Only allow necessary ports
ufw allow 80/tcp    # HTTP (redirects to HTTPS)
ufw allow 443/tcp   # HTTPS
ufw allow 22/tcp    # SSH (for management)
ufw enable
```

### 2. **Secret Management**

```bash
# Never commit .env.production to git
echo ".env.production" >> .gitignore

# Set restrictive permissions
chmod 600 .env.production

# Consider using secret management:
# - AWS Secrets Manager
# - HashiCorp Vault
# - Docker Secrets (Swarm mode)
```

### 3. **Database Backups**

```bash
# Create backup script
cat > backup-weblate.sh << 'EOF'
#!/bin/bash
BACKUP_DIR=/backup/weblate
DATE=$(date +%Y%m%d_%H%M%S)

# Backup database
docker exec weblate_postgres pg_dump -U weblate weblate | gzip > ${BACKUP_DIR}/weblate_db_${DATE}.sql.gz

# Backup Weblate data
tar -czf ${BACKUP_DIR}/weblate_data_${DATE}.tar.gz weblate-data/

# Keep only last 7 days
find ${BACKUP_DIR} -name "*.gz" -mtime +7 -delete

echo "Backup completed: ${DATE}"
EOF

chmod +x backup-weblate.sh

# Add to cron (daily at 2 AM)
echo "0 2 * * * /opt/weblate-production/backup-weblate.sh" | crontab -
```

### 4. **SSL Certificate Renewal**

```bash
# Create renewal script
cat > renew-ssl.sh << 'EOF'
#!/bin/bash
docker compose -f docker-compose.prod.yml run --rm certbot renew
docker compose -f docker-compose.prod.yml restart nginx
EOF

chmod +x renew-ssl.sh

# Add to cron (monthly)
echo "0 0 1 * * /opt/weblate-production/renew-ssl.sh" | crontab -
```

### 5. **Monitoring**

```bash
# Install monitoring
docker run -d \
    --name=prometheus \
    -p 9090:9090 \
    -v prometheus-data:/prometheus \
    prom/prometheus

# Create alerts for:
# - Container health
# - Disk space
# - Memory usage
# - SSL expiry
```

---

## 🔧 Maintenance

### Regular Updates

```bash
# Update Docker images
docker compose -f docker-compose.prod.yml pull

# Restart with new images
docker compose -f docker-compose.prod.yml down
docker compose -f docker-compose.prod.yml up -d

# Check everything is running
docker compose -f docker-compose.prod.yml ps
```

### Log Management

```bash
# View logs
docker compose -f docker-compose.prod.yml logs -f weblate

# Limit log size in docker-compose.prod.yml:
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

---

## 🐛 Troubleshooting

### Weblate Can't Connect to GitLab

```bash
# Check SSH connection
docker exec weblate ssh -T git@gitlab.com

# Check SSH config
docker exec weblate cat /app/data/ssh/config

# Check known_hosts
docker exec weblate cat /app/data/ssh/known_hosts

# Re-add host key
docker exec weblate ssh-keyscan -H gitlab.com >> /app/data/ssh/known_hosts
```

### Webhook Not Working

```bash
# Check webhook service logs
docker logs webhook-reloader

# Test webhook manually
curl -X POST https://weblate.company.com/webhook-reload \
    -H "Content-Type: application/json" \
    -d '{"ref":"refs/heads/main"}'

# Check GitLab webhook logs
# GitLab → Project → Settings → Webhooks → Recent Deliveries
```

### SSL Certificate Issues

```bash
# Check certificate
openssl s_client -connect weblate.company.com:443 -servername weblate.company.com

# Check nginx logs
docker logs weblate_nginx

# Verify certificate files
docker exec weblate_nginx ls -la /etc/nginx/ssl/live/weblate.company.com/
```

---

## 📊 Performance Tuning

### For High Traffic

```yaml
# docker-compose.prod.yml
services:
  weblate:
    deploy:
      replicas: 3  # Multiple Weblate instances
      resources:
        limits:
          memory: 4G

  database:
    deploy:
      resources:
        limits:
          memory: 2G
    command:
      - "postgres"
      - "-c"
      - "max_connections=200"
      - "-c"
      - "shared_buffers=512MB"
```

### Caching

```bash
# Add Varnish or Redis caching layer
# Configure CDN for static files
# Enable Weblate's built-in caching
```

---

## 🎯 Summary

**Production setup removes:**
- ❌ GitLab container (uses your existing GitLab)
- ❌ Development-only settings
- ❌ Self-signed certificates

**Production setup adds:**
- ✅ Real SSL certificates (Let's Encrypt or custom)
- ✅ Production security headers
- ✅ Email notifications
- ✅ Proper backup strategy
- ✅ Monitoring and logging
- ✅ Firewall configuration

**Estimated setup time:** 30-60 minutes

**Maintenance time:** 15 minutes/month (updates + monitoring)

---

**Questions or issues?**
- Check logs: `docker compose -f docker-compose.prod.yml logs -f`
- Review this guide's Troubleshooting section
- Check Weblate documentation: https://docs.weblate.org
