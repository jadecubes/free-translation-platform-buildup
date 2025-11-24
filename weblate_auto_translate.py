#!/usr/bin/env python3
"""
Auto-translate script for Weblate
Translates all untranslated units using Google Translate and saves to JSON files
"""

import sys
import json
import os

# Django setup
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'weblate.settings')
import django
django.setup()

from weblate.trans.models import Component, Unit
from weblate.machinery.google import GoogleTranslation


def auto_translate_component(project_slug, component_slug):
    """Auto-translate all languages in a component."""

    # Get component
    c = Component.objects.get(slug=component_slug, project__slug=project_slug)

    # Get Google Translate API key from environment
    api_key = os.environ.get('WEBLATE_MT_GOOGLE_KEY')
    if not api_key:
        print("ERROR: WEBLATE_MT_GOOGLE_KEY not set")
        return False

    # Initialize Google Translate
    gt = GoogleTranslation(settings={'key': api_key})

    # Process each translation (except source language)
    for trans in c.translation_set.all():
        if trans.language.code == c.source_language.code:
            continue

        print(f"Translating {trans.language.code}...")
        translated_count = 0

        # Translate untranslated units
        for unit in Unit.objects.filter(translation=trans):
            if not unit.target or unit.target == '':
                try:
                    result_list = list(gt.translate(unit, user=None))
                    if result_list and len(result_list) > 0:
                        first_result = result_list[0]
                        if isinstance(first_result, list) and len(first_result) > 0:
                            translation_dict = first_result[0]
                            unit.target = translation_dict['text']
                            unit.state = 20  # Translated state
                            unit.save()
                            translated_count += 1
                except Exception as e:
                    print(f"  Error translating {unit.context}: {e}")

        print(f"  Translated {translated_count} strings")

        # Refresh stats
        trans.invalidate_cache()
        trans.stats.update_stats()

        # Write to JSON file
        translations = {}
        for unit in Unit.objects.filter(translation=trans, state__gte=20):
            if unit.target:
                translations[unit.context] = unit.target

        filename = trans.get_filename()
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(translations, f, ensure_ascii=False, indent=4)

        print(f"  Saved {len(translations)} translations to {filename}")

    return True


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: weblate_auto_translate.py <project-slug> <component-slug>")
        sys.exit(1)

    project_slug = sys.argv[1]
    component_slug = sys.argv[2]

    if auto_translate_component(project_slug, component_slug):
        print("✓ Auto-translation complete")
        sys.exit(0)
    else:
        print("✗ Auto-translation failed")
        sys.exit(1)
