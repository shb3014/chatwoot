# Chatwoot Local Development Setup Guide

This guide will help you set up Chatwoot for local development on Windows.

## Prerequisites

You need to install the following:

1. **Docker Desktop** (Recommended for Windows) - [Download](https://www.docker.com/products/docker-desktop)
   - OR -
2. **Native Setup**:
   - PostgreSQL 16 with pgvector extension
   - Redis
   - Ruby (check `.ruby-version` file)
   - Node.js 23.x
   - pnpm 10.x

## Setup Method 1: Docker (Recommended for Windows)

This is the easiest method and includes all dependencies.

### Step 1: Create .env file

Create a file named `.env` in the project root with this content:

```bash
# Rails
RAILS_ENV=development
NODE_ENV=development

# Frontend URL
FRONTEND_URL=http://localhost:3000

# Database
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DATABASE=chatwoot
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=

# Redis
REDIS_URL=redis://redis:6379
REDIS_PASSWORD=redis_password
REDIS_OPENID_REDIS_URL=redis://redis:6379

# Mailer
MAILER_SENDER_EMAIL=dev@chatwoot.local
SMTP_ADDRESS=mailhog
SMTP_PORT=1025
SMTP_DOMAIN=chatwoot.local

# Storage
ACTIVE_STORAGE_SERVICE=local

# Log level
LOG_LEVEL=debug
```

### Step 2: Start Docker containers

```bash
docker-compose up
```

### Step 3: Access the application

- **Chatwoot App**: http://localhost:3000
- **MailHog UI** (email testing): http://localhost:8025

### Step 4: Create your first user

Visit http://localhost:3000 and complete the signup form.

## Setup Method 2: Native Installation

### Step 1: Install PostgreSQL with pgvector

1. Install PostgreSQL 16
2. Install pgvector extension
3. Create a user and ensure PostgreSQL is running on port 5432

### Step 2: Install Redis

1. Install Redis (or use WSL)
2. Start Redis server on port 6379

### Step 3: Create .env file

Create a file named `.env` in the project root:

```bash
# Rails
RAILS_ENV=development
NODE_ENV=development

# Frontend URL
FRONTEND_URL=http://localhost:3000

# Database
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DATABASE=chatwoot_dev
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=

# Redis
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=

# Mailer (optional - for email testing)
MAILER_SENDER_EMAIL=dev@chatwoot.local

# Storage
ACTIVE_STORAGE_SERVICE=local

# Log level
LOG_LEVEL=debug
```

### Step 4: Install dependencies

```bash
# Install Ruby dependencies
bundle install

# Install Node dependencies
pnpm install
```

### Step 5: Setup database

```bash
# Create and migrate database
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

### Step 6: Start the application

**Option A: Using overmind (if installed)**
```bash
pnpm dev
```

**Option B: Manual (separate terminals)**

Terminal 1 - Rails server:
```bash
bin/rails s -p 3000
```

Terminal 2 - Sidekiq (background jobs):
```bash
bundle exec sidekiq -C config/sidekiq.yml
```

Terminal 3 - Vite (frontend assets):
```bash
bin/vite dev
```

### Step 7: Access the application

- Visit http://localhost:3000
- Complete the signup form to create your first user

## Common Issues

### Husky pre-commit hook error

If you get an npx error when committing, the hook has been updated to use `pnpm exec` instead.

If you still have issues, you can:
1. Comment out the lint-staged line in `.husky/pre-commit`
2. Or commit with `git commit --no-verify -m "message"` to skip hooks

### Port already in use

If port 3000 or 5432 is in use:
- Check what's using it with `netstat -ano | findstr :3000`
- Kill the process or change the port in Procfile.dev

### PostgreSQL connection error

Make sure:
- PostgreSQL is running
- The credentials in `.env` match your PostgreSQL setup
- The database exists (`bin/rails db:create`)

## Testing

### Frontend tests
```bash
pnpm test
```

### Backend tests
```bash
bundle exec rspec
```

### Linting
```bash
# JavaScript/Vue
pnpm eslint:fix

# Ruby
bundle exec rubocop -a
```

## Development Workflow

1. Make changes to code
2. Changes auto-reload (Vite for frontend, Rails for backend)
3. Run tests
4. Commit changes (lint runs automatically)
5. Test in browser at http://localhost:3000

## Next Steps

- Read the [Contributing Guide](CONTRIBUTING.md)
- Check the [Development Guidelines](CLAUDE.md)
- Join the [Discord community](https://discord.gg/cJXdrwS)
