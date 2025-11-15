# Weblate + GitLab Docker Setup

This project contains a complete Docker-based setup for running Weblate (a web-based translation tool) and GitLab (a Git repository platform) for testing version control integration.

## Prerequisites

- Docker installed on your system
- Docker Compose installed on your system

## Project Structure

```
.
├── docker-compose.yml      # Docker services configuration
├── .env                    # Environment variables (DO NOT COMMIT TO GIT)
├── weblate-data/          # Weblate data directory (auto-created)
├── postgres-data/         # PostgreSQL data (auto-created)
├── gitlab-data/           # GitLab data directory (auto-created)
└── README.md              # This file
```

## Quick Start

### 1. Configure Environment Variables

Edit the `.env` file and update the following important settings:

- `WEBLATE_ADMIN_PASSWORD`: Change to a secure password
- `POSTGRES_PASSWORD`: Change to a secure password
- `WEBLATE_ADMIN_EMAIL`: Set your admin email
- `WEBLATE_SECRET_KEY`: Generate a random secret key for production
- `GITLAB_ROOT_PASSWORD`: Change to a secure password for GitLab

### 2. Start the Services

Run the following command to start all services:

```bash
docker-compose up -d
```

This will:
- Download the required Docker images (PostgreSQL, Redis, Weblate, GitLab)
- Create the necessary containers
- Set up the database
- Start Weblate on port 8080
- Start GitLab on port 8081

**Note:** GitLab takes 3-5 minutes to fully start up for the first time.

### 3. Access the Services

Once the containers are running:

**Weblate:** http://localhost:8080
- **Username**: `admin`
- **Password**: The value of `WEBLATE_ADMIN_PASSWORD`

**GitLab:** http://localhost:8081
- **Username**: `root`
- **Password**: The value of `GITLAB_ROOT_PASSWORD`

**Important:** GitLab requires 3-5 minutes to initialize on first startup. Check status with:
```bash
docker compose logs -f gitlab
```

## Managing the Services

### View logs

```bash
docker-compose logs -f
```

### View logs for a specific service

```bash
docker-compose logs -f weblate
docker-compose logs -f gitlab
docker-compose logs -f database
docker-compose logs -f redis
```

### Stop the services

```bash
docker-compose down
```

### Stop and remove all data

```bash
docker-compose down -v
rm -rf weblate-data postgres-data
```

### Restart services

```bash
docker-compose restart
```

### Update Weblate to the latest version

```bash
docker-compose pull weblate
docker-compose up -d weblate
```

## Data Persistence

All data is stored in local directories:

- `./weblate-data/`: Weblate application data, translations, and files
- `./postgres-data/`: PostgreSQL database files
- `./gitlab-data/`: GitLab configuration, logs, and repositories
- Redis data is stored in a Docker volume

## Integrating Weblate with GitLab

### 1. Create a GitLab Project

1. Access GitLab at http://localhost:8081
2. Login with username `root` and your `GITLAB_ROOT_PASSWORD`
3. Create a new project for your translations
4. Note the project's Git URL (e.g., `http://gitlab/root/my-translations.git`)

### 2. Generate GitLab Personal Access Token

1. In GitLab: User Settings → Access Tokens
2. Create a token with `api`, `read_repository`, and `write_repository` scopes
3. Copy the token (you'll need it in Weblate)

### 3. Configure Weblate to Use GitLab

1. Access Weblate at http://localhost:8080
2. Go to Settings → Version control systems
3. Add GitLab as a VCS backend:
   - Repository URL: Use `http://gitlab/root/your-project.git` (use container name `gitlab`)
   - Authentication: Use the personal access token from step 2

### 4. SSH Configuration (Alternative)

For SSH access between containers:

1. Generate SSH keys in Weblate container
2. Add the public key to GitLab Deploy Keys
3. Use SSH URL: `git@gitlab:root/your-project.git`

**Note:** Both containers are on the same Docker network (`weblate-network`), so they can communicate using container names (`gitlab`, `weblate`).

## Troubleshooting

### Container won't start

Check the logs:
```bash
docker-compose logs
```

### Port 8080 already in use

Edit `docker-compose.yml` and change the port mapping:
```yaml
ports:
  - "8081:8080"  # Change 8081 to any available port
```

### Reset admin password

```bash
docker-compose exec weblate weblate changepassword admin
```

### Database connection issues

Make sure all containers are running:
```bash
docker-compose ps
```

### GitLab takes too long to start

GitLab is resource-intensive and requires:
- At least 4GB RAM allocated to Docker
- 3-5 minutes for initial startup
- Check startup progress: `docker compose logs -f gitlab`

### GitLab shows 502 error

Wait a few more minutes - GitLab is still initializing. Check logs for "Listening on" message.

## Email Configuration (Optional)

To enable email notifications, update these variables in `.env`:

```env
WEBLATE_EMAIL_HOST=smtp.example.com
WEBLATE_EMAIL_HOST_USER=your-email@example.com
WEBLATE_EMAIL_HOST_PASSWORD=your-password
WEBLATE_SERVER_EMAIL=weblate@example.com
WEBLATE_DEFAULT_FROM_EMAIL=weblate@example.com
```

Then restart the services:
```bash
docker-compose restart weblate
```

## Security Notes

- Change all default passwords before deploying to production
- Generate a strong random secret key for `WEBLATE_SECRET_KEY`
- Set `WEBLATE_DEBUG=0` in production
- Update `WEBLATE_ALLOWED_HOSTS` with your actual domain
- Keep your `.env` file secure and never commit it to version control
- Regularly backup the `weblate-data` and `postgres-data` directories

## Backup

To backup your data:

```bash
# Stop the containers
docker-compose down

# Backup all data directories
tar -czf backup-$(date +%Y%m%d).tar.gz weblate-data postgres-data gitlab-data

# Restart the containers
docker-compose up -d
```

## Resources

- [Weblate Documentation](https://docs.weblate.org/)
- [Weblate Docker Image](https://hub.docker.com/r/weblate/weblate)
- [GitLab Documentation](https://docs.gitlab.com/)
- [GitLab Docker Image](https://hub.docker.com/r/gitlab/gitlab-ce)
- [Docker Documentation](https://docs.docker.com/)
