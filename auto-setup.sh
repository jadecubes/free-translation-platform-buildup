#!/bin/bash

# ========================================
# Weblate Auto-Setup Script v2
# ========================================
# Automatically creates GitLab project and Weblate integration

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

# Load .env file
if [ ! -f .env ]; then
    log_error ".env file not found!"
    log_info "Please create .env from .env.template:"
    log_info "  cp .env.template .env"
    log_info "  nano .env"
    exit 1
fi

source .env

# ========================================
# Detect and Set Architecture
# ========================================
ARCH=$(uname -m)
PLATFORM=""

case $ARCH in
    x86_64)
        PLATFORM="linux/amd64"
        ;;
    aarch64|arm64)
        PLATFORM="linux/arm64"
        ;;
    armv7l)
        PLATFORM="linux/arm/v7"
        ;;
    *)
        PLATFORM="linux/amd64"
        ;;
esac

export DOCKER_DEFAULT_PLATFORM=$PLATFORM

log_info "Starting Weblate auto-setup..."
log_info "Platform: $PLATFORM ($ARCH)"
echo ""

# ========================================
# Step 1: Generate and Save SSH Key
# ========================================
log_info "Step 1: Getting Weblate SSH public key..."

# Generate key if it doesn't exist
docker exec weblate bash -c '
if [ ! -f /app/data/ssh/id_rsa ]; then
    mkdir -p /app/data/ssh
    ssh-keygen -t rsa -b 4096 -f /app/data/ssh/id_rsa -N "" -C "weblate@weblate.local"
fi
' 2>/dev/null

# Get the public key
WEBLATE_SSH_KEY=$(docker exec weblate cat /app/data/ssh/id_rsa.pub 2>/dev/null)

if [ -z "$WEBLATE_SSH_KEY" ]; then
    log_error "Failed to get Weblate SSH key"
    exit 1
fi

# Save to file
echo "$WEBLATE_SSH_KEY" > weblate_ssh_key.pub
log_success "SSH key saved to: weblate_ssh_key.pub"
echo ""

# ========================================
# Step 2: Verify GitLab Project Exists
# ========================================
log_info "Step 2: Verifying GitLab project..."
log_warning "Please ensure your GitLab project exists:"
echo ""
echo "  Project: ${GITLAB_PROJECT_NAMESPACE}/${GITLAB_PROJECT_NAME}"
echo "  URL: https://gitlab.local:8081/${GITLAB_PROJECT_NAMESPACE}/${GITLAB_PROJECT_NAME}"
echo ""
echo "If the project doesn't exist, create it in GitLab with:"
echo "  1. Open https://gitlab.local:8081/projects/new"
echo "  2. Project name: ${GITLAB_PROJECT_NAME}"
echo "  3. Initialize with: ${NEW_BASE} file containing:"
echo '     {"welcome": "Welcome to app"}'
echo ""
read -p "Press Enter when the project exists and has the translation file..."
echo ""
log_success "GitLab project verified"
echo ""

# ========================================
# Step 3: Add SSH Key to GitLab
# ========================================
log_warning "ACTION REQUIRED: Add Weblate SSH key to GitLab"
echo ""
echo "The SSH key has been saved to: weblate_ssh_key.pub"
echo ""
log_error "IMPORTANT: You MUST grant write permissions for Weblate to push translations back to GitLab!"
echo ""
echo "Please add it to GitLab:"
echo "1. Open: https://gitlab.local:8081/${GITLAB_PROJECT_NAMESPACE}/${GITLAB_PROJECT_NAME}/-/settings/repository"
echo "2. Scroll to 'Deploy Keys' → Expand"
echo "3. Click 'Add new key'"
echo "4. Fill in the form:"
echo "   Title: Weblate"
echo "   Key: (paste from weblate_ssh_key.pub)"
echo "   ✓✓✓ CHECK 'Grant write permissions' ✓✓✓  <-- REQUIRED!"
echo "5. Click 'Add key'"
echo ""
read -p "Press Enter after adding the SSH key with WRITE PERMISSIONS..."
echo ""

# Verify SSH key has write access
log_info "Verifying SSH key has write access..."
if docker exec weblate bash -c 'export GIT_SSH_COMMAND="ssh -i /app/data/ssh/id_rsa -o UserKnownHostsFile=/app/data/ssh/known_hosts -o StrictHostKeyChecking=no" && cd /tmp && git ls-remote ssh://git@gitlab:22/'"${GITLAB_PROJECT_NAMESPACE}"'/'"${GITLAB_PROJECT_NAME}"'.git HEAD' &>/dev/null; then
    log_success "SSH key verified - write access granted"
else
    log_error "SSH key verification failed!"
    log_warning "Please ensure the deploy key has 'Grant write permissions' checked in GitLab"
    log_info "Continuing anyway, but push to GitLab may fail..."
fi
echo ""

# ========================================
# Step 4: Configure SSH for GitLab
# ========================================
log_info "Step 4: Configuring SSH for GitLab..."
docker exec weblate bash -c "
mkdir -p /app/data/ssh
ssh-keyscan -p 22 gitlab >> /app/data/ssh/known_hosts 2>/dev/null
chmod 600 /app/data/ssh/known_hosts

# Create SSH config for automatic authentication
cat > /app/data/ssh/config << 'EOF'
Host gitlab
    HostName gitlab
    User git
    IdentityFile /app/data/ssh/id_rsa
    UserKnownHostsFile /app/data/ssh/known_hosts
    StrictHostKeyChecking no
EOF
chmod 600 /app/data/ssh/config
" || true
log_success "GitLab SSH configuration complete"
echo ""

# ========================================
# Step 5: Create Weblate Project
# ========================================
log_info "Step 5: Creating Weblate project..."
docker exec weblate bash -c "weblate shell << PYEOF
from weblate.trans.models import Project
from weblate.auth.models import User

admin = User.objects.get(username='${WEBLATE_ADMIN_USER}')

project, created = Project.objects.get_or_create(
    slug='${WEBLATE_PROJECT_SLUG}',
    defaults={
        'name': '${WEBLATE_PROJECT_NAME}',
        'web': 'https://gitlab.local:8081/${GITLAB_PROJECT_NAMESPACE}/${GITLAB_PROJECT_NAME}',
    }
)

if created:
    print('✓ Project created: ${WEBLATE_PROJECT_NAME}')
else:
    print('✓ Project already exists: ${WEBLATE_PROJECT_NAME}')
PYEOF"

log_success "Weblate project ready"
echo ""

# ========================================
# Step 6: Create Weblate Component
# ========================================
log_info "Step 6: Creating Weblate component..."
docker exec weblate bash -c "weblate shell << PYEOF
from weblate.trans.models import Project, Component

project = Project.objects.get(slug='${WEBLATE_PROJECT_SLUG}')

push_on_commit = '${PUSH_ON_COMMIT}'.lower() == 'true'

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
        'push_on_commit': push_on_commit,
        'commit_pending_age': 0,
        'manage_units': True,
        'update_linguas': True,
        'update_interval': 1,
    }
)

if created:
    print('✓ Component created: ${WEBLATE_COMPONENT_NAME}')
    component.do_update()
    print('✓ Initial repository update complete')
else:
    print('✓ Component already exists: ${WEBLATE_COMPONENT_NAME}')
    # Update settings for existing component
    component.manage_units = True
    component.update_linguas = True
    component.update_interval = 1
    component.push_on_commit = True
    component.save()
    component.do_update()
    print('✓ Repository updated and settings configured')
PYEOF"

log_success "Component configured and synced with GitLab"
echo ""

# ========================================
# Step 7: Add Target Languages
# ========================================
log_info "Step 7: Adding target languages..."
IFS=',' read -ra LANGS <<< "$TARGET_LANGUAGES"
for lang in "${LANGS[@]}"; do
    lang=$(echo "$lang" | xargs)
    log_info "  Adding language: $lang"
    docker exec weblate bash -c "weblate shell << PYEOF
from weblate.trans.models import Component
from weblate.lang.models import Language

component = Component.objects.get(slug='${WEBLATE_COMPONENT_SLUG}', project__slug='${WEBLATE_PROJECT_SLUG}')
language = Language.objects.get(code='$lang')

translation, created = component.translation_set.get_or_create(language=language)

if created:
    print('  ✓ Added: $lang')
else:
    print('  ✓ Exists: $lang')
PYEOF" 2>/dev/null || log_warning "Language $lang may not be available"
done

log_success "Languages configured"
echo ""

# ========================================
# Step 8: Verify Google Translate
# ========================================
log_info "Step 8: Verifying Google Translate configuration..."
docker exec weblate bash -c 'weblate shell << "PYEOF"
import os

api_key = os.environ.get("WEBLATE_MT_GOOGLE_KEY", "")
if api_key:
    print(f"✓ Google Translate API key configured: {api_key[:20]}...")
else:
    print("✗ Warning: WEBLATE_MT_GOOGLE_KEY not set")
PYEOF' || log_warning "Could not verify Google Translate"
echo ""

# ========================================
# Step 9: Enable Auto-Translation
# ========================================
if [ "$AUTO_TRANSLATE_ENABLED" = "true" ]; then
    log_info "Step 9: Enabling auto-translation (mode: ${AUTO_TRANSLATE_MODE})..."
    docker exec weblate weblate install_addon \
        --addon weblate.autotranslate.autotranslate \
        --configuration "{\"mode\": \"${AUTO_TRANSLATE_MODE}\", \"filter_type\": \"todo\", \"auto_source\": \"mt\", \"threshold\": \"${AUTO_TRANSLATE_THRESHOLD}\"}" \
        "${WEBLATE_PROJECT_SLUG}" "${WEBLATE_COMPONENT_SLUG}" 2>/dev/null || log_warning "Addon may already be installed"

    log_success "Auto-translation enabled"
    echo ""
else
    log_info "Step 9: Auto-translation disabled (set AUTO_TRANSLATE_ENABLED=true to enable)"
    echo ""
fi

# ========================================
# Step 10: Trigger Initial Translation
# ========================================
if [ "$AUTO_TRANSLATE_ENABLED" = "true" ]; then
    log_info "Step 10: Triggering initial translation..."
    for lang in "${LANGS[@]}"; do
        lang=$(echo "$lang" | xargs)
        log_info "  Translating to $lang..."
        docker exec weblate weblate auto_translate \
            --user "${WEBLATE_ADMIN_USER}" \
            --mode "${AUTO_TRANSLATE_MODE}" \
            --threshold "${AUTO_TRANSLATE_THRESHOLD}" \
            --mt google-translate \
            "${WEBLATE_PROJECT_SLUG}" "${WEBLATE_COMPONENT_SLUG}" "$lang" 2>/dev/null || log_warning "Translation may have failed for $lang"
    done

    log_success "Initial translation complete"
    echo ""
fi

# ========================================
# Step 11: Fix SSH Known Hosts
# ========================================
log_info "Step 11: Fixing SSH known_hosts for GitLab..."
docker exec weblate bash -c 'ssh-keyscan -p 22 gitlab > /app/data/ssh/known_hosts 2>/dev/null && chmod 600 /app/data/ssh/known_hosts'
log_success "SSH known_hosts updated"
echo ""

# ========================================
# Step 12: Create GitLab Webhook
# ========================================
log_info "Step 12: Creating GitLab webhook for automatic updates..."

# Generate GitLab API token if not exists
if [ -z "$GITLAB_API_TOKEN" ]; then
    log_info "Creating GitLab personal access token..."
    log_warning "This may take 30-60 seconds (GitLab Rails is loading)..."

    # Create a personal access token using GitLab Rails console
    GITLAB_API_TOKEN=$(docker exec gitlab gitlab-rails runner "
      user = User.find_by(username: 'test')
      if user.nil?
        puts 'ERROR: User test not found'
        exit 1
      end

      # Check if token already exists
      existing_token = user.personal_access_tokens.find_by(name: 'Weblate Webhook')
      if existing_token && existing_token.active?
        puts 'EXISTING_TOKEN_FOUND'
        exit 0
      end

      token = user.personal_access_tokens.create(
        name: 'Weblate Webhook',
        scopes: ['api'],
        expires_at: Date.today + 365
      )
      token.set_token('$(openssl rand -hex 20)')
      token.save!
      puts token.token
    " 2>/dev/null | tail -1)

    if [ "$GITLAB_API_TOKEN" = "EXISTING_TOKEN_FOUND" ]; then
        log_warning "A token named 'Weblate Webhook' already exists in GitLab"
        log_info "Skipping token creation. Please add existing token to .env if webhook creation fails."
        GITLAB_API_TOKEN=""
    elif [ "$GITLAB_API_TOKEN" = "ERROR: User test not found" ]; then
        log_error "GitLab user 'test' not found"
        log_warning "Skipping webhook creation"
        GITLAB_API_TOKEN=""
    elif [ -n "$GITLAB_API_TOKEN" ]; then
        log_success "GitLab API token created: ${GITLAB_API_TOKEN:0:10}..."

        # Add to .env file if not present
        if ! grep -q "GITLAB_API_TOKEN" .env; then
            echo "" >> .env
            echo "# GitLab API Token (auto-generated)" >> .env
            echo "GITLAB_API_TOKEN=${GITLAB_API_TOKEN}" >> .env
            log_success "Token saved to .env file"
        fi
    else
        log_error "Failed to create GitLab API token"
        log_warning "You'll need to create the webhook manually"
    fi
else
    log_info "Using existing GitLab API token from .env"
fi

if [ -n "$GITLAB_API_TOKEN" ]; then
    # Create TWO webhooks in GitLab for complete workflow
    log_info "Creating GitLab webhooks for automatic translation..."

    # Webhook 1: Weblate's built-in GitLab webhook
    # This notifies Weblate about GitLab pushes and updates Weblate's UI/tracking
    log_info "Creating Weblate notification webhook..."
    WEBLATE_WEBHOOK_URL="http://weblate:8080/hooks/gitlab/"

    WEBHOOK_RESPONSE_1=$(docker exec gitlab curl -s \
        --request POST \
        --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "{
            \"url\": \"${WEBLATE_WEBHOOK_URL}\",
            \"push_events\": true,
            \"enable_ssl_verification\": false,
            \"token\": \"\"
        }" \
        "http://127.0.0.1:8181/api/v4/projects/${GITLAB_PROJECT_NAMESPACE}%2F${GITLAB_PROJECT_NAME}/hooks" 2>/dev/null)

    if echo "$WEBHOOK_RESPONSE_1" | grep -q '"id"'; then
        log_success "✓ Weblate notification webhook created"
        log_info "  URL: ${WEBLATE_WEBHOOK_URL}"
    else
        log_warning "Weblate webhook creation failed or already exists"
    fi

    # Webhook 2: Custom auto-translation webhook
    # This triggers: pull → loadpo → auto-translate → commit → push
    log_info "Creating auto-translation workflow webhook..."
    RELOAD_WEBHOOK_URL="http://webhook-reloader:5000/reload"

    WEBHOOK_RESPONSE_2=$(docker exec gitlab curl -s \
        --request POST \
        --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "{
            \"url\": \"${RELOAD_WEBHOOK_URL}\",
            \"push_events\": true,
            \"enable_ssl_verification\": false,
            \"token\": \"\"
        }" \
        "http://127.0.0.1:8181/api/v4/projects/${GITLAB_PROJECT_NAMESPACE}%2F${GITLAB_PROJECT_NAME}/hooks" 2>/dev/null)

    if echo "$WEBHOOK_RESPONSE_2" | grep -q '"id"'; then
        log_success "✓ Auto-translation webhook created"
        log_info "  URL: ${RELOAD_WEBHOOK_URL}"
        echo ""
        log_success "✓✓ Complete automatic translation workflow enabled!"
        log_info "  Webhook 1: Keeps Weblate in sync with GitLab"
        log_info "  Webhook 2: Auto-translates and pushes translations back"
        log_info "  Total time: ~5-10 seconds from push to translated files"
    else
        log_warning "Auto-translation webhook creation failed or already exists"
    fi
else
    log_warning "Skipping webhook creation (no API token)"
    log_info "To enable automatic translation workflow, manually create TWO webhooks:"
    echo ""
    log_info "Webhook 1 - Weblate Notification:"
    log_info "  URL: http://weblate:8080/hooks/gitlab/"
    log_info "  Purpose: Notifies Weblate about GitLab pushes"
    echo ""
    log_info "Webhook 2 - Auto-Translation:"
    log_info "  URL: http://webhook-reloader:5000/reload"
    log_info "  Purpose: Triggers auto-translation workflow"
    echo ""
    log_info "Add both at: https://gitlab.local:8081/${GITLAB_PROJECT_NAMESPACE}/${GITLAB_PROJECT_NAME}/-/hooks"
    log_info "Settings: Push events enabled, SSL verification disabled"
fi
echo ""

# ========================================
# Step 13: Commit and Push
# ========================================
log_info "Step 13: Committing and pushing translations..."
docker exec weblate weblate commit_pending "${WEBLATE_PROJECT_SLUG}/${WEBLATE_COMPONENT_SLUG}" --age 0 || true
docker exec weblate weblate pushgit "${WEBLATE_PROJECT_SLUG}/${WEBLATE_COMPONENT_SLUG}" || log_warning "Push may have failed - check SSH key"

log_success "Translations committed"
echo ""

# ========================================
# Summary
# ========================================
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
log_success "Weblate: https://${WEBLATE_SITE_DOMAIN}/projects/${WEBLATE_PROJECT_SLUG}/"
log_success "GitLab: https://gitlab.local:8081/${GITLAB_PROJECT_NAMESPACE}/${GITLAB_PROJECT_NAME}"
echo ""
log_info "Configuration:"
echo "  - Source language: ${SOURCE_LANGUAGE}"
echo "  - Target languages: ${TARGET_LANGUAGES}"
echo "  - Auto-translation: ${AUTO_TRANSLATE_ENABLED} (mode: ${AUTO_TRANSLATE_MODE})"
echo "  - Admin user: ${WEBLATE_ADMIN_USER}"
echo "  - Auto-sync: GitLab → Weblate (via webhook)"
echo ""
if [ -n "$GITLAB_API_TOKEN" ]; then
    log_info "GitLab API Token (saved in .env):"
    echo "  ${GITLAB_API_TOKEN:0:10}...${GITLAB_API_TOKEN: -10}"
    echo ""
fi
