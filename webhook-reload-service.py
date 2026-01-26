#!/usr/bin/env python3
"""
Webhook Reload Service for Weblate

Receives webhooks from GitLab when source files are updated, then triggers:
1. Pull changes from GitLab
2. Reload translation units
3. Auto-translate new strings using Google Translate
4. Push translations back to GitLab

Configuration via environment variables:
- WEBLATE_PROJECT: Project slug (default: test-translation)
- WEBLATE_COMPONENT: Component slug (default: gitlab)
- TARGET_LANGUAGES: Comma-separated language codes (default: ja,fr,zh_Hant_HK)
- GITLAB_BRANCH: Branch to watch (default: main)
"""

from flask import Flask, request, jsonify
import subprocess
import logging
import os

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Configuration from environment
PROJECT = os.environ.get('WEBLATE_PROJECT', 'test-translation')
COMPONENT = os.environ.get('WEBLATE_COMPONENT', 'gitlab')
TARGET_LANGUAGES = os.environ.get('TARGET_LANGUAGES', 'ja,fr,zh_Hant_HK').split(',')
BRANCH = os.environ.get('GITLAB_BRANCH', 'main')


def run_command(cmd, timeout=60):
    """Run a docker exec command and return success status."""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return False, '', 'Command timeout'


@app.route('/reload', methods=['POST'])
def reload_webhook():
    """Handle webhook from GitLab."""
    logger.info("Received webhook from GitLab")

    try:
        data = request.json or {}
        ref = data.get('ref', '')

        # Only process main branch pushes
        if ref and ref != f'refs/heads/{BRANCH}':
            logger.info(f"Ignoring push to {ref}")
            return jsonify({'status': 'ignored', 'reason': f'not {BRANCH} branch'}), 200

        logger.info(f"Processing update for {PROJECT}/{COMPONENT}...")
        component_path = f'{PROJECT}/{COMPONENT}'

        # Step 1: Pull from GitLab
        logger.info("Step 1: Pulling from GitLab...")
        success, stdout, stderr = run_command(
            ['docker', 'exec', 'weblate', 'weblate', 'updategit', component_path]
        )
        if not success:
            logger.error(f"Pull failed: {stderr}")
            return jsonify({'status': 'error', 'step': 'pull', 'message': stderr}), 500
        logger.info("Pull complete")

        # Step 2: Reload translation units
        logger.info("Step 2: Reloading translation units...")
        success, stdout, stderr = run_command(
            ['docker', 'exec', 'weblate', 'weblate', 'loadpo', component_path]
        )
        if not success:
            logger.warning(f"Reload warning: {stderr}")
        logger.info("Reload complete")

        # Step 3: Auto-translate each target language
        logger.info("Step 3: Auto-translating...")
        translated = []
        for lang in TARGET_LANGUAGES:
            lang = lang.strip()
            if not lang:
                continue
            logger.info(f"  Translating to {lang}...")
            success, stdout, stderr = run_command(
                ['docker', 'exec', 'weblate', 'weblate', 'auto_translate',
                 '--user', 'admin',
                 '--mode', 'translate',
                 '--mt', 'google-translate',
                 '--threshold', '80',
                 PROJECT, COMPONENT, lang],
                timeout=120
            )
            if success:
                translated.append(lang)
                logger.info(f"  {lang}: done")
            else:
                logger.warning(f"  {lang}: {stderr}")

        logger.info(f"Translated: {translated}")

        # Step 4: Commit pending changes
        logger.info("Step 4: Committing...")
        run_command(
            ['docker', 'exec', 'weblate', 'weblate', 'commit_pending', '--age', '0', component_path]
        )

        # Step 5: Push to GitLab
        logger.info("Step 5: Pushing to GitLab...")
        success, stdout, stderr = run_command(
            ['docker', 'exec', 'weblate', 'weblate', 'pushgit', component_path]
        )
        if not success:
            logger.warning(f"Push warning: {stderr}")

        logger.info("Complete!")
        return jsonify({
            'status': 'success',
            'translated': translated,
            'message': 'Auto-translation complete'
        }), 200

    except Exception as e:
        logger.error(f"Error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500


@app.route('/health', methods=['GET'])
def health():
    """Health check."""
    return jsonify({'status': 'healthy'}), 200


if __name__ == '__main__':
    logger.info(f"Starting Webhook Service - Project: {PROJECT}/{COMPONENT}, Languages: {TARGET_LANGUAGES}")
    app.run(host='0.0.0.0', port=5000, debug=False)
