# GitLab + Gemini Auto-Translation

![Unit Tests](https://github.com/jadecubes/free-translation-platform-buildup/actions/workflows/test.yml/badge.svg?branch=main)

A small, self-hosted demo that translates JSON locale files with Gemini and opens a GitLab Merge Request for human review.

```text
Push en-US.json → run the manual translate job → Gemini → review the generated MR
```

The translator sends only new keys and keys whose English value or context changed. It validates returned values and placeholders before writing them.

## Requirements

- Docker with Docker Compose
- At least 4 GB of available memory for the local GitLab instance
- A Gemini API key from [Google AI Studio](https://aistudio.google.com/app/apikey)

The bundled GitLab instance uses HTTP and is intended only for local development. Do not expose it to an untrusted network.

## Quick Start

### 1. Start GitLab

```bash
git clone https://github.com/jadecubes/free-translation-platform-buildup.git
cd free-translation-platform-buildup
cp .env.template .env
```

Set a strong `GITLAB_ROOT_PASSWORD` in `.env`, then make `gitlab.local` resolve to your machine:

```text
127.0.0.1 gitlab.local
```

Add that line to `/etc/hosts` on macOS/Linux or the Windows hosts file, then run:

```bash
./setup.sh
```

Open `http://gitlab.local:8081` and sign in as `root`.

### 2. Create a GitLab project

Create a blank project, for example `translation-demo`. Do not initialize it with a README because this repository already has a `main` branch.

### 3. Register the runner

In the new project, open **Settings > CI/CD > Runners**, create a project runner, and copy its authentication token (`glrt-...`). Register it with:

```bash
docker exec -it gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "http://gitlab.local:8081" \
  --token "glrt-your-runner-token" \
  --executor "docker" \
  --docker-image "node:20-alpine" \
  --docker-network-mode "translation-network" \
  --description "translation-runner"
```

The network option is required: build and helper containers must be able to resolve the GitLab service as `gitlab.local`.

### 4. Add CI/CD variables

Open **Settings > CI/CD > Variables** and add:

| Variable | Value | Options |
|---|---|---|
| `GEMINI_API_KEY` | Your Gemini API key | Masked |
| `PROJECT_TOKEN` | Project access token described below | Masked |

Create `PROJECT_TOKEN` under **Settings > Access tokens** with role `Developer` and scope `write_repository`. The translation job uses it to push a branch and create the MR through Git push options.

Optional variables:

| Variable | Default | Purpose |
|---|---|---|
| `TARGET_LANGUAGES` | `fr,ja,zh-Hant-HK` | Comma-separated target language codes |
| `GEMINI_MODEL` | `gemini-3.6-flash` | Supported Gemini model to call |

### 5. Push this repository to local GitLab

Copy the HTTP project URL from GitLab, then add it as a separate remote:

```bash
git remote add local-gitlab http://gitlab.local:8081/root/translation-demo.git
git push -u local-gitlab main
```

Using a separate remote avoids accidentally pushing back to the GitHub repository.

### 6. Translate

Open **Build > Pipelines** and run the manual `translate` job. You can also use **Run pipeline** and override `TARGET_LANGUAGES` before starting the job.

When translations change, the job pushes a `translate/<timestamp>` branch and opens an MR against the branch that ran the pipeline. Review the locale diff before merging.

The job is intentionally `allow_failure: true`, so inspect its log if translation does not produce an MR.

## Translation Files

`locales/en-US.json` is the source of truth. Each key has a value and optional usage context:

```json
{
  "submit": {
    "value": "Submit",
    "context": "Primary action button on forms"
  },
  "itemCount": {
    "value": "{count} items",
    "context": "Cart item count; {count} is a placeholder"
  }
}
```

The generated `locales/{language}.json` files are flat key/value maps suitable for normal i18n libraries:

```json
{
  "submit": "Envoyer",
  "itemCount": "{count} articles"
}
```

`locales/.translation-hashes.json` records the English value and context each translation came from. Commit it with the generated locale files so copy or context changes are translated again.

Model output is accepted only when:

- The requested key is present.
- Its value is a non-empty string.
- Placeholder names match the source for `{name}`, `{{name}}`, and ICU arguments.

Rejected or omitted keys keep their old hash and are retried on the next run. Consuming applications should fall back to `en-US` when a target key is absent.

## Run Locally

The translation tool can run without GitLab:

```bash
cd tools/translate
npm ci
PROJECT_ROOT=../.. GEMINI_API_KEY=your-key TARGET_LANGUAGES=fr,ja npm run translate
```

`PROJECT_ROOT=../..` points the nested tool back to this repository's `locales/` directory.

## Development

```bash
cd tools/translate
npm ci
npm test
```

`npm test` runs the TypeScript typecheck and unit suite. The tests mock the external Gemini request.

Run the real API integration suite manually:

```bash
GEMINI_API_KEY=your-key npm run test:e2e
```

GitHub Actions runs the unit suite on changes under `tools/translate/`. The real Gemini suite is not run in CI because it consumes API quota.

## Operations

```bash
# Start or stop GitLab
docker compose up -d
docker compose down

# Follow service logs
docker logs -f gitlab
docker logs -f gitlab-runner

# Check registered runners
docker exec gitlab-runner gitlab-runner list
```

Persistent GitLab and runner data is stored in ignored `gitlab-data/` and `gitlab-runner-config/` directories.

## Troubleshooting

### GitLab does not become ready

GitLab can take several minutes on its first start. Check:

```bash
docker logs gitlab
```

Also confirm `gitlab.local` resolves to `127.0.0.1` on the host.

### Runner cannot clone the project

Confirm the runner was registered with `--docker-network-mode translation-network`:

```bash
docker network inspect translation-network
docker exec gitlab-runner gitlab-runner list
```

If it was registered without that option, unregister it in GitLab, remove its entry from `gitlab-runner-config/config.toml`, and register it again.

### The job reports `Missing PROJECT_TOKEN`

Add a project access token with role `Developer` and scope `write_repository` as the masked `PROJECT_TOKEN` CI/CD variable. The check happens before Gemini is called, so this failure does not consume API quota.

### An English edit is not translated again

Confirm `locales/.translation-hashes.json` is committed. Without the manifest, existing translations are trusted and their hashes are backfilled.

## Limitations

- Human corrections are overwritten if that key's English value or context later changes.
- Validation checks output shape and placeholders, not linguistic quality.
- printf-style placeholders such as `%s` and `%d` are not validated.
- Requests have no retry/backoff and are sent as one prompt per language, so very large batches may exceed model output limits.
- The bundled GitLab uses local HTTP. Use your organization's HTTPS GitLab instance for real deployments.

## Project Layout

```text
docker-compose.yml          Local GitLab and Runner
.gitlab-ci.yml              Test and manual translation jobs
setup.sh                    Local GitLab startup helper
locales/en-US.json          Source strings and context
tools/translate/src/        Translation implementation and unit tests
tools/translate/e2e/        Real Gemini integration tests
```
