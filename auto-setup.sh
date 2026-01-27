#!/bin/bash

# ========================================
# Weblate Auto-Setup Script v3
# ========================================
# Fully automated setup - no manual steps required
# Creates GitLab project, adds SSH keys, configures Weblate

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

echo "=========================================="
echo "  Weblate Auto-Setup (Fully Automated)"
echo "=========================================="
echo ""
log_info "Platform: $PLATFORM ($ARCH)"
log_info "GitLab Project: ${GITLAB_PROJECT_NAMESPACE}/${GITLAB_PROJECT_NAME}"
log_info "Target Languages: ${TARGET_LANGUAGES}"
echo ""

# ========================================
# Step 0: Wait for Services to be Ready
# ========================================
log_info "Step 0: Waiting for services to be ready..."

# Wait for GitLab to be ready (check puma status only, skip HTTP check)
log_info "  Checking GitLab..."
GITLAB_READY=false
for i in {1..30}; do
    if docker exec gitlab gitlab-ctl status puma 2>/dev/null | grep -q "run: puma"; then
        GITLAB_READY=true
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ "$GITLAB_READY" = "false" ]; then
    log_warning "GitLab puma not running yet. Waiting 10 more seconds..."
    sleep 10
fi
log_success "GitLab is ready"

# Wait for Weblate to be ready
log_info "  Checking Weblate..."
WEBLATE_READY=false
for i in {1..30}; do
    if curl -sk --max-time 5 "https://localhost:8080/healthz/" 2>/dev/null | grep -q "ok"; then
        WEBLATE_READY=true
        break
    fi
    echo -n "."
    sleep 3
done
echo ""

if [ "$WEBLATE_READY" = "false" ]; then
    log_warning "Weblate may not be fully ready. Continuing anyway..."
else
    log_success "Weblate is ready"
fi
echo ""

# ========================================
# Step 1: Create GitLab API Token
# ========================================
log_info "Step 1: Creating GitLab API token..."

GITLAB_API_TOKEN=$(docker exec gitlab gitlab-rails runner '
user = User.find_by(username: "root")
if user.nil?
  puts "ERROR"
  exit 1
end
# Revoke existing token (token value cannot be retrieved after creation)
old_token = user.personal_access_tokens.find_by(name: "auto-setup")
old_token.revoke! if old_token
# Create new token
token = user.personal_access_tokens.create!(
  name: "auto-setup",
  scopes: [:api, :write_repository, :read_repository],
  expires_at: 365.days.from_now
)
puts token.token
' 2>/dev/null)

if [ -z "$GITLAB_API_TOKEN" ] || [ "$GITLAB_API_TOKEN" = "ERROR" ]; then
    log_error "Failed to create GitLab API token"
    exit 1
fi
log_success "GitLab API token created"
echo ""

# ========================================
# Step 2: Create GitLab Project (if not exists)
# ========================================
log_info "Step 2: Creating GitLab project..."

# Check if project exists
PROJECT_EXISTS=$(curl -sk "https://localhost:8081/api/v4/projects/${GITLAB_PROJECT_NAMESPACE}%2F${GITLAB_PROJECT_NAME}" \
    --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if 'id' in d else 'no')" 2>/dev/null || echo "no")

if [ "$PROJECT_EXISTS" = "yes" ]; then
    log_success "Project already exists: ${GITLAB_PROJECT_NAMESPACE}/${GITLAB_PROJECT_NAME}"
else
    # Create project
    CREATE_RESULT=$(curl -sk --request POST "https://localhost:8081/api/v4/projects" \
        --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{
            \"name\": \"${GITLAB_PROJECT_NAME}\",
            \"path\": \"${GITLAB_PROJECT_NAME}\",
            \"visibility\": \"public\",
            \"initialize_with_readme\": true
        }" | python3 -c "import sys,json; d=json.load(sys.stdin); print('success' if 'id' in d else d.get('message', 'failed'))" 2>/dev/null)

    if [ "$CREATE_RESULT" = "success" ]; then
        log_success "Project created: ${GITLAB_PROJECT_NAMESPACE}/${GITLAB_PROJECT_NAME}"
        sleep 2  # Wait for project to be ready
    else
        log_warning "Project creation result: $CREATE_RESULT"
    fi
fi
echo ""

# ========================================
# Step 3: Create Source Translation File
# ========================================
log_info "Step 3: Creating source translation file (${NEW_BASE})..."

# Check if source file exists
SOURCE_EXISTS=$(curl -sk "https://localhost:8081/api/v4/projects/${GITLAB_PROJECT_NAMESPACE}%2F${GITLAB_PROJECT_NAME}/repository/files/${NEW_BASE}?ref=${GITLAB_BRANCH}" \
    --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if 'file_name' in d else 'no')" 2>/dev/null || echo "no")

if [ "$SOURCE_EXISTS" = "yes" ]; then
    log_success "Source file already exists: ${NEW_BASE}"
else
    # Create source file with sample content
    SOURCE_CONTENT=$(cat << 'JSONEOF'
{
  "app.title": "Translation Demo",
  "app.welcome": "Welcome to our application",
  "app.description": "This is a demo of automatic translation",
  "button.submit": "Submit",
  "button.cancel": "Cancel",
  "button.save": "Save",
  "message.success": "Operation completed successfully",
  "message.error": "An error occurred",
  "message.loading": "Loading, please wait..."
}
JSONEOF
)

    # Base64 encode the content for GitLab API
    ENCODED_CONTENT=$(echo "$SOURCE_CONTENT" | base64 | tr -d '\n')

    curl -sk --request POST "https://localhost:8081/api/v4/projects/${GITLAB_PROJECT_NAMESPACE}%2F${GITLAB_PROJECT_NAME}/repository/files/${NEW_BASE}" \
        --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{
            \"branch\": \"${GITLAB_BRANCH}\",
            \"commit_message\": \"Add source translation file\",
            \"encoding\": \"base64\",
            \"content\": \"${ENCODED_CONTENT}\"
        }" > /dev/null 2>&1

    log_success "Source file created: ${NEW_BASE}"
fi
echo ""

# ========================================
# Step 4: Create Translation Files for Target Languages
# ========================================
log_info "Step 4: Creating translation files for target languages..."

IFS=',' read -ra LANGS <<< "$TARGET_LANGUAGES"
for lang in "${LANGS[@]}"; do
    lang=$(echo "$lang" | xargs)
    LANG_FILE="${lang}.json"

    # Check if file exists
    FILE_EXISTS=$(curl -sk "https://localhost:8081/api/v4/projects/${GITLAB_PROJECT_NAMESPACE}%2F${GITLAB_PROJECT_NAME}/repository/files/${LANG_FILE}?ref=${GITLAB_BRANCH}" \
        --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if 'file_name' in d else 'no')" 2>/dev/null || echo "no")

    if [ "$FILE_EXISTS" = "yes" ]; then
        log_info "  ✓ ${LANG_FILE} already exists"
    else
        # Create empty translation file
        EMPTY_CONTENT=$(echo "{}" | base64 | tr -d '\n')

        curl -sk --request POST "https://localhost:8081/api/v4/projects/${GITLAB_PROJECT_NAMESPACE}%2F${GITLAB_PROJECT_NAME}/repository/files/${LANG_FILE}" \
            --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
            --header "Content-Type: application/json" \
            --data "{
                \"branch\": \"${GITLAB_BRANCH}\",
                \"commit_message\": \"Add ${lang} translation file\",
                \"encoding\": \"base64\",
                \"content\": \"${EMPTY_CONTENT}\"
            }" > /dev/null 2>&1

        log_info "  ✓ ${LANG_FILE} created"
    fi
done

log_success "Translation files ready"
echo ""

# ========================================
# Step 5: Generate Weblate SSH Key
# ========================================
log_info "Step 5: Generating Weblate SSH key..."

docker exec weblate bash -c '
if [ ! -f /app/data/ssh/id_rsa ]; then
    mkdir -p /app/data/ssh
    ssh-keygen -t rsa -b 4096 -f /app/data/ssh/id_rsa -N "" -C "weblate@weblate.local"
fi
' 2>/dev/null

WEBLATE_SSH_KEY=$(docker exec weblate cat /app/data/ssh/id_rsa.pub 2>/dev/null)

if [ -z "$WEBLATE_SSH_KEY" ]; then
    log_error "Failed to get Weblate SSH key"
    exit 1
fi

echo "$WEBLATE_SSH_KEY" > weblate_ssh_key.pub
log_success "SSH key generated"
echo ""

# ========================================
# Step 6: Add SSH Deploy Key to GitLab (Automated)
# ========================================
log_info "Step 6: Adding SSH deploy key to GitLab..."

# Get project ID
PROJECT_ID=$(curl -sk "https://localhost:8081/api/v4/projects/${GITLAB_PROJECT_NAMESPACE}%2F${GITLAB_PROJECT_NAME}" \
    --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null)

if [ -z "$PROJECT_ID" ]; then
    log_error "Failed to get project ID"
    exit 1
fi

# Check if deploy key already exists and get its ID and can_push status
EXISTING_KEY_INFO=$(curl -sk "https://localhost:8081/api/v4/projects/${PROJECT_ID}/deploy_keys" \
    --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" | python3 -c "
import sys,json
keys = json.load(sys.stdin)
for k in keys:
    if 'weblate' in k.get('title', '').lower():
        print(f\"{k['id']}:{k.get('can_push', False)}\")
        break
else:
    print('not_found')
" 2>/dev/null)

if [ "$EXISTING_KEY_INFO" = "not_found" ]; then
    # Add deploy key with write access
    DEPLOY_KEY_RESULT=$(curl -sk --request POST "https://localhost:8081/api/v4/projects/${PROJECT_ID}/deploy_keys" \
        --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{
            \"title\": \"Weblate Auto-Setup\",
            \"key\": \"${WEBLATE_SSH_KEY}\",
            \"can_push\": true
        }" | python3 -c "import sys,json; d=json.load(sys.stdin); print('success' if 'id' in d else d.get('message', 'failed'))" 2>/dev/null)

    if [ "$DEPLOY_KEY_RESULT" = "success" ]; then
        log_success "Deploy key added with write permissions"
    else
        log_warning "Deploy key result: $DEPLOY_KEY_RESULT"
    fi
else
    # Key exists - check if can_push is enabled
    KEY_ID=$(echo "$EXISTING_KEY_INFO" | cut -d':' -f1)
    CAN_PUSH=$(echo "$EXISTING_KEY_INFO" | cut -d':' -f2)

    if [ "$CAN_PUSH" = "True" ]; then
        log_success "Deploy key already exists with write permissions"
    else
        # Update existing key to enable can_push
        log_info "Enabling write permissions on existing deploy key..."
        curl -sk --request PUT "https://localhost:8081/api/v4/projects/${PROJECT_ID}/deploy_keys/${KEY_ID}" \
            --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
            --header "Content-Type: application/json" \
            --data '{"can_push": true}' > /dev/null 2>&1
        log_success "Deploy key updated with write permissions"
    fi
fi
echo ""

# ========================================
# Step 7: Configure SSH for GitLab
# ========================================
log_info "Step 7: Configuring SSH for GitLab..."
docker exec weblate bash -c "
mkdir -p /app/data/ssh
ssh-keyscan -p 22 gitlab >> /app/data/ssh/known_hosts 2>/dev/null
chmod 600 /app/data/ssh/known_hosts

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
log_success "SSH configuration complete"
echo ""

# ========================================
# Step 7.5: Configure Weblate Machine Translation
# ========================================
log_info "Step 7.5: Configuring machine translation settings..."
docker exec weblate bash -c "cat > /app/data/settings-override.py << 'EOF'
import os

# Google Translate API Key
MT_GOOGLE_KEY = os.environ.get('WEBLATE_MT_GOOGLE_KEY', '')

# Enable machine translation services
MT_SERVICES = (
    'weblate.machinery.google.GoogleTranslation',
)
EOF" 2>/dev/null
log_success "Machine translation settings configured"
echo ""

# ========================================
# Step 8: Create Weblate Project
# ========================================
log_info "Step 8: Creating Weblate project..."
docker exec weblate bash -c "weblate shell << PYEOF
from weblate.trans.models import Project
from weblate.auth.models import User

try:
    admin = User.objects.get(username='${WEBLATE_ADMIN_USER}')
except User.DoesNotExist:
    admin = User.objects.filter(is_superuser=True).first()

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

# Configure machine translation for the project
import os
api_key = os.environ.get('WEBLATE_MT_GOOGLE_KEY', '')
if api_key:
    project.machinery_settings = {'google-translate': {'key': api_key}}
    project.save()
    print('✓ Google Translate enabled for project')
else:
    print('⚠ No Google API key - machine translation disabled')
PYEOF"

log_success "Weblate project ready"
echo ""

# ========================================
# Step 9: Create Weblate Component
# ========================================
log_info "Step 9: Creating Weblate component..."
docker exec weblate bash -c "weblate shell << PYEOF
from weblate.trans.models import Project, Component

project = Project.objects.get(slug='${WEBLATE_PROJECT_SLUG}')

push_on_commit = '${PUSH_ON_COMMIT:-true}'.lower() == 'true'

component, created = Component.objects.get_or_create(
    project=project,
    slug='${WEBLATE_COMPONENT_SLUG}',
    defaults={
        'name': '${WEBLATE_COMPONENT_NAME}',
        'repo': '${GITLAB_REPO_URL}',
        'push': '${GITLAB_REPO_URL}',
        'branch': '${GITLAB_BRANCH}',
        'filemask': '${FILE_MASK}',
        'template': '${NEW_BASE}',
        'file_format': '${FILE_FORMAT}',
        'new_base': '${NEW_BASE}',
        'vcs': 'git',
        'push_on_commit': push_on_commit,
        'commit_pending_age': 0,
        'manage_units': True,
    }
)

if created:
    print('✓ Component created: ${WEBLATE_COMPONENT_NAME}')
else:
    print('✓ Component already exists: ${WEBLATE_COMPONENT_NAME}')
    component.push = '${GITLAB_REPO_URL}'
    component.template = '${NEW_BASE}'
    component.manage_units = True
    component.push_on_commit = push_on_commit
    component.save()

# Update from repository
try:
    component.do_update()
    print('✓ Repository synced')
except Exception as e:
    print(f'Warning: Repository sync issue: {e}')

# Fix branch if cloned to wrong branch (git defaults to master, but we use main)
import subprocess
repo_path = component.full_path
result = subprocess.run(['git', '-C', repo_path, 'branch', '--show-current'], capture_output=True, text=True)
current_branch = result.stdout.strip()
if current_branch != '${GITLAB_BRANCH}':
    print(f'Switching from {current_branch} to ${GITLAB_BRANCH}...')
    subprocess.run(['git', '-C', repo_path, 'checkout', '${GITLAB_BRANCH}'], capture_output=True)
    subprocess.run(['git', '-C', repo_path, 'checkout', '-b', '${GITLAB_BRANCH}', 'origin/${GITLAB_BRANCH}'], capture_output=True)
    print('✓ Branch switched')

# Rescan translations to pick up all language files
component.create_translations()
print('✓ Translations rescanned')
PYEOF"

log_success "Component configured"

# Force reload translation files to create units from template
log_info "  Reloading translation files..."
docker exec weblate weblate loadpo test-translation/gitlab 2>/dev/null || true
log_success "Translation units created"
echo ""

# ========================================
# Step 10: Verify Google Translate
# ========================================
log_info "Step 10: Verifying Google Translate configuration..."
docker exec weblate bash -c 'weblate shell << "PYEOF"
import os

api_key = os.environ.get("WEBLATE_MT_GOOGLE_KEY", "")
if api_key and api_key != "MY_WEBLATE_MT_GOOGLE_KEY":
    print(f"✓ Google Translate API key configured")
else:
    print("✗ Warning: WEBLATE_MT_GOOGLE_KEY not set - auto-translation will not work")
PYEOF' || log_warning "Could not verify Google Translate"
echo ""

# ========================================
# Step 11: Enable Auto-Translation Addon
# ========================================
if [ "$AUTO_TRANSLATE_ENABLED" = "true" ]; then
    log_info "Step 11: Enabling auto-translation addon..."
    docker exec weblate weblate install_addon \
        --addon weblate.autotranslate.autotranslate \
        --configuration "{\"mode\": \"${AUTO_TRANSLATE_MODE}\", \"filter_type\": \"todo\", \"auto_source\": \"mt\", \"engines\": [\"google-translate\"], \"threshold\": ${AUTO_TRANSLATE_THRESHOLD}}" \
        "${WEBLATE_PROJECT_SLUG}/${WEBLATE_COMPONENT_SLUG}" 2>/dev/null || log_warning "Addon may already be installed"

    log_success "Auto-translation addon enabled"

    # Also add cleanup addon to remove obsolete strings from translation files
    log_info "  Enabling cleanup addon (removes obsolete translations)..."
    docker exec weblate weblate install_addon \
        --addon weblate.cleanup.generic \
        --configuration "{}" \
        "${WEBLATE_PROJECT_SLUG}/${WEBLATE_COMPONENT_SLUG}" 2>/dev/null || log_warning "Cleanup addon may already be installed"
    log_success "Cleanup addon enabled"
else
    log_info "Step 11: Auto-translation disabled (set AUTO_TRANSLATE_ENABLED=true to enable)"
fi
echo ""

# ========================================
# Step 12: Trigger Initial Translation
# ========================================
if [ "$AUTO_TRANSLATE_ENABLED" = "true" ]; then
    log_info "Step 12: Triggering initial translation..."
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
else
    log_info "Step 12: Skipping translation (AUTO_TRANSLATE_ENABLED=false)"
fi
echo ""

# ========================================
# Step 13: Create GitLab Webhooks
# ========================================
log_info "Step 13: Creating GitLab webhooks..."

# Enable local network requests in GitLab (required for internal Docker URLs)
docker exec gitlab gitlab-rails runner "
ApplicationSetting.current.update!(
  allow_local_requests_from_web_hooks_and_services: true,
  allow_local_requests_from_system_hooks: true
)
" 2>/dev/null
log_info "  Enabled local network requests in GitLab"

# Check if webhooks already exist
EXISTING_HOOKS=$(curl -sk "https://localhost:8081/api/v4/projects/${PROJECT_ID}/hooks" \
    --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" | python3 -c "
import sys,json
hooks = json.load(sys.stdin)
urls = [h.get('url', '') for h in hooks]
print(','.join(urls))
" 2>/dev/null)

# Webhook 1: Weblate notification
WEBLATE_WEBHOOK_URL="http://weblate:8080/hooks/gitlab/"
if [[ "$EXISTING_HOOKS" == *"weblate"* ]]; then
    log_info "  ✓ Weblate webhook already exists"
else
    WEBHOOK_RESULT=$(curl -sk --request POST "https://localhost:8081/api/v4/projects/${PROJECT_ID}/hooks" \
        --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{
            \"url\": \"${WEBLATE_WEBHOOK_URL}\",
            \"push_events\": true,
            \"enable_ssl_verification\": false
        }" 2>&1)
    if echo "$WEBHOOK_RESULT" | grep -q '"id"'; then
        log_info "  ✓ Weblate webhook created"
    else
        log_warning "  Weblate webhook failed: $WEBHOOK_RESULT"
    fi
fi

# Webhook 2: Auto-translation trigger
RELOAD_WEBHOOK_URL="http://webhook-reloader:5000/reload"
if [[ "$EXISTING_HOOKS" == *"webhook-reloader"* ]]; then
    log_info "  ✓ Auto-translation webhook already exists"
else
    WEBHOOK_RESULT=$(curl -sk --request POST "https://localhost:8081/api/v4/projects/${PROJECT_ID}/hooks" \
        --header "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
        --header "Content-Type: application/json" \
        --data "{
            \"url\": \"${RELOAD_WEBHOOK_URL}\",
            \"push_events\": true,
            \"enable_ssl_verification\": false
        }" 2>&1)
    if echo "$WEBHOOK_RESULT" | grep -q '"id"'; then
        log_info "  ✓ Auto-translation webhook created"
    else
        log_warning "  Auto-translation webhook failed: $WEBHOOK_RESULT"
    fi
fi

log_success "Webhooks configured"
echo ""

# ========================================
# Step 14: Commit and Push Translations
# ========================================
log_info "Step 14: Committing and pushing translations..."
docker exec weblate weblate commit_pending "${WEBLATE_PROJECT_SLUG}/${WEBLATE_COMPONENT_SLUG}" --age 0 2>/dev/null || true
docker exec weblate weblate pushgit "${WEBLATE_PROJECT_SLUG}/${WEBLATE_COMPONENT_SLUG}" 2>/dev/null || log_warning "Push may have failed"

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
echo "  - Source language: ${SOURCE_LANGUAGE} (${NEW_BASE})"
echo "  - Target languages: ${TARGET_LANGUAGES}"
echo "  - Auto-translation: ${AUTO_TRANSLATE_ENABLED}"
echo "  - Push on commit: ${PUSH_ON_COMMIT:-true}"
echo ""
log_info "To test the workflow:"
echo "  1. Edit ${NEW_BASE} in GitLab"
echo "  2. Add a new translation key"
echo "  3. Commit and push"
echo "  4. Wait 5-10 seconds"
echo "  5. Check target language files for translations"
echo ""
