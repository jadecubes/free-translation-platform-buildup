#!/usr/bin/env python3
"""
Webhook Reload Service for Weblate + react-i18next

This service receives webhooks from GitLab when en-US.json is updated
(via i18n scan), then triggers Weblate to:
1. Pull from GitLab
2. Reload translation units from the updated en-US.json
3. Auto-translate new/changed keys
4. Push translations back to GitLab

Usage: python3 webhook-reload-service.py
"""

from flask import Flask, request, jsonify
import subprocess
import logging
import time

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@app.route('/reload', methods=['POST'])
def reload_webhook():
    """Handle webhook from GitLab and reload Weblate units."""

    logger.info("Received webhook from GitLab")

    try:
        # Parse webhook data
        data = request.json
        ref = data.get('ref', '')

        # Only reload on main branch pushes
        if ref != 'refs/heads/main':
            logger.info(f"Ignoring push to {ref}")
            return jsonify({'status': 'ignored', 'reason': 'not main branch'}), 200

        logger.info("Main branch updated, triggering Weblate reload...")

        # Step 1: Update repository (pull from GitLab)
        logger.info("Step 1: Updating repository from GitLab...")
        result = subprocess.run(
            ['docker', 'exec', 'weblate', 'weblate', 'updategit', 'test-translation/gitlab'],
            capture_output=True,
            text=True,
            timeout=60
        )

        if result.returncode != 0:
            logger.error(f"❌ Failed to update repository: {result.stderr}")
            return jsonify({'status': 'error', 'message': f'Update failed: {result.stderr}'}), 500

        logger.info("✅ Repository updated")

        # Wait a moment for file system sync
        time.sleep(1)

        # Step 2: Reload translation units from updated files
        logger.info("Step 2: Reloading translation units from en-US.json...")
        result = subprocess.run(
            ['docker', 'exec', 'weblate', 'weblate', 'loadpo', '--force', 'test-translation/gitlab'],
            capture_output=True,
            text=True,
            timeout=60
        )

        if result.returncode != 0:
            logger.error(f"❌ Failed to reload units: {result.stderr}")
            return jsonify({'status': 'error', 'message': f'Reload failed: {result.stderr}'}), 500

        logger.info("✅ Translation units reloaded")

        # Step 3: Auto-translate all target languages using Google Translate
        logger.info("Step 3: Auto-translating to target languages...")
        result = subprocess.run(
            ['docker', 'exec', 'weblate', 'python3', '/app/data/weblate_auto_translate.py',
             'test-translation', 'gitlab'],
            capture_output=True,
            text=True,
            timeout=180
        )

        if result.returncode != 0:
            logger.error(f"❌ Auto-translation failed: {result.stderr}")
            return jsonify({'status': 'error', 'message': f'Auto-translate failed: {result.stderr}'}), 500

        logger.info("✅ Auto-translation complete")
        logger.info(result.stdout)

        # Step 4: Commit translations using git directly
        logger.info("Step 4: Committing translations...")
        result = subprocess.run(
            ['docker', 'exec', 'weblate', 'bash', '-c',
             'cd /app/data/vcs/test-translation/gitlab && '
             'git config user.email "weblate@local" && '
             'git config user.name "Weblate" && '
             'git add *.json && '
             'git diff --staged --quiet || '
             'git commit -m "Translated using Weblate\n\nCo-authored-by: Weblate <noreply@weblate.org>"'],
            capture_output=True,
            text=True,
            timeout=60
        )

        if result.returncode != 0 and 'nothing to commit' not in result.stdout:
            logger.warning(f"⚠️  Commit had issues: {result.stderr}")
        else:
            logger.info("✅ Translations committed")

        # Step 5: Push to GitLab
        logger.info("Step 5: Pushing to GitLab...")
        result = subprocess.run(
            ['docker', 'exec', 'weblate', 'bash', '-c',
             'cd /app/data/vcs/test-translation/gitlab && git push origin main'],
            capture_output=True,
            text=True,
            timeout=60
        )

        if result.returncode != 0:
            logger.warning(f"⚠️  Push had issues: {result.stderr}")
        else:
            logger.info("✅ Pushed to GitLab")

        logger.info("✅ Complete! Auto-translation done and pushed to GitLab")
        return jsonify({
            'status': 'success',
            'message': 'Units reloaded, auto-translation triggered'
        }), 200

    except subprocess.TimeoutExpired:
        logger.error("❌ Command timeout")
        return jsonify({'status': 'error', 'message': 'Command timeout'}), 500
    except Exception as e:
        logger.error(f"❌ Error handling webhook: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({'status': 'healthy'}), 200


if __name__ == '__main__':
    logger.info("Starting Webhook Reload Service for react-i18next on port 5000...")
    app.run(host='0.0.0.0', port=5000, debug=False)
