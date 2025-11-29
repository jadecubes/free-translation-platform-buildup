# Memory Optimization & Multi-Architecture Support

## Memory Optimizations

### Container Memory Limits

All services now have memory limits to prevent resource exhaustion:

| Service | Memory Limit | Reserved | Current Usage |
|---------|-------------|----------|---------------|
| PostgreSQL | 512M | 256M | ~435M |
| Redis | 256M | 64M | ~11M |
| Weblate | 2G | 1G | ~1.3G |
| Nginx | 128M | 64M | ~228M |
| GitLab | 2.5G | 1.5G | ~3.1G → optimized |
| Webhook | 128M | 32M | ~9M |
| **Total** | **~5.5GB** | **~3GB** | Previously ~5GB+ |

### GitLab Optimizations

The GitLab configuration has been tuned to reduce memory usage:

```ruby
# Reduced from 2 to 1 worker
puma['worker_processes'] = 1
puma['worker_timeout'] = 60

# Reduced from 10 to 5 concurrent jobs
sidekiq['max_concurrency'] = 5

# Reduced PostgreSQL buffer
postgresql['shared_buffers'] = "128MB"  # was 256MB
postgresql['max_connections'] = 100

# Disabled Prometheus monitoring
prometheus_monitoring['enable'] = false

# Limited Gitaly resource usage
gitaly['ruby_max_rss'] = 200000000
gitaly['concurrency'] = [...]
```

### Redis Optimizations

Redis now has built-in memory management:

```bash
# Maximum memory cap with LRU eviction
--maxmemory 128mb --maxmemory-policy allkeys-lru
```

## Multi-Architecture Support

### Supported Platforms

The system now automatically detects and supports:

- **linux/amd64** - Intel/AMD 64-bit (x86_64)
- **linux/arm64** - ARM 64-bit (Apple Silicon, AWS Graviton)
- **linux/arm/v7** - ARM 32-bit (Raspberry Pi)

### Quick Start

Use the new `start.sh` script that automatically detects your architecture:

```bash
./start.sh
```

The script will:
1. Detect your CPU architecture
2. Ask for confirmation or allow manual selection
3. Set the appropriate `DOCKER_DEFAULT_PLATFORM`
4. Build and start all services

### Manual Architecture Selection

If you want to override the detected architecture:

```bash
# Set before running docker compose
export DOCKER_DEFAULT_PLATFORM=linux/arm64
docker compose up -d --build
```

Or choose interactively when running `./start.sh`.

### Dockerfile Changes

The `Dockerfile.webhook` now properly supports multi-architecture builds using `$(dpkg --print-architecture)` which automatically selects the correct binaries for your platform.

## Usage

### Starting Services

**Recommended:**
```bash
./start.sh
```

**Manual:**
```bash
docker compose up -d
```

### Monitoring Memory

```bash
# Check current memory usage
docker stats

# Check specific container
docker stats weblate --no-stream
```

### Updating Configuration

If you need to adjust memory limits, edit `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      memory: 2G      # Maximum allowed
    reservations:
      memory: 1G      # Guaranteed minimum
```

Then restart:
```bash
docker compose down
docker compose up -d
```

## Expected Performance

After optimizations:

- **GitLab**: ~1.5-2GB (down from ~3GB)
- **Total system**: ~4-5GB (down from ~6-7GB)
- Faster container builds on ARM platforms
- More predictable resource usage
- Protection against memory exhaustion

## Troubleshooting

### GitLab running slow

If GitLab feels sluggish after optimization, you can increase workers:

```yaml
puma['worker_processes'] = 2  # increase from 1
sidekiq['max_concurrency'] = 10  # increase from 5
```

### Out of Memory errors

Check container logs:
```bash
docker compose logs gitlab
docker compose logs weblate
```

Increase memory limits if needed, but investigate root cause first.

### Architecture detection fails

Manually set the platform:
```bash
export DOCKER_DEFAULT_PLATFORM=linux/amd64
```

Or modify the `start.sh` script to hardcode your platform.
