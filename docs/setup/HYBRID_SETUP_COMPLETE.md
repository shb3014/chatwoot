# Chatwoot Hybrid Setup - Docker + Native Rails

## ✅ Already Done:

- Docker services running (PostgreSQL, Redis, MailHog)
- `.env` file configured
- Node.js and pnpm installed

## 📦 Install Ruby 3.4.4

### Download and Install:

1. **Download RubyInstaller**:
   - Go to: https://rubyinstaller.org/downloads/
   - Download: **Ruby 3.4.4-1 (x64)** with Devkit
   - Run the installer

2. **During installation**:
   - ✅ Check "Add Ruby executables to PATH"
   - ✅ Check "Associate .rb files with this Ruby installation"
   - ✅ Run `ridk install` at the end (choose option 3 - MSYS2 and MINGW development toolchain)

3. **Restart your terminal** after installation

## 🚀 Start Chatwoot

### 1. Install Dependencies

Open a NEW terminal (PowerShell or CMD) in the project directory:

```powershell
# Install Ruby gems
bundle install

# Install Node packages (if not done already)
pnpm install
```

### 2. Setup Database

```powershell
# Create and migrate database
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

### 3. Start the Application

You'll need 3 separate terminal windows:

**Terminal 1 - Rails Server:**
```powershell
bin/rails s -p 3000
```

**Terminal 2 - Sidekiq (Background Jobs):**
```powershell
bundle exec sidekiq -C config/sidekiq.yml
```

**Terminal 3 - Vite (Frontend):**
```powershell
bin/vite dev
```

### 4. Access Your Local Chatwoot

- **Application**: http://localhost:3000
- **Email Testing (MailHog)**: http://localhost:8025

Create your first account by visiting http://localhost:3000 and completing the signup form.

## 🛠️ Troubleshooting

### PostgreSQL Connection Error

Check Docker services are running:
```powershell
docker ps
```

Should show 3 containers running. If not:
```powershell
docker-compose -f docker-compose.simple.yaml up -d
```

### Redis Connection Error

Check Redis is accessible:
```powershell
docker logs chatwoot-redis-1
```

### Bundle Install Fails

Make sure you ran `ridk install` and chose option 3 during Ruby installation.

If still failing, try:
```powershell
ridk enable
bundle install
```

### Port Already in Use

Check what's using port 3000:
```powershell
netstat -ano | findstr :3000
```

Kill the process or change the port:
```powershell
bin/rails s -p 3001
```

## 📊 Verify Docker Services

```powershell
# Check all containers are running
docker ps

# Check PostgreSQL logs
docker logs chatwoot-postgres-1

# Check Redis logs
docker logs chatwoot-redis-1

# Stop all services
docker-compose -f docker-compose.simple.yaml down

# Start all services
docker-compose -f docker-compose.simple.yaml up -d
```

## 💡 Development Tips

- **Hot Reload**: Vite automatically reloads frontend changes
- **Rails Reload**: Code changes reload automatically in development
- **View Emails**: Check http://localhost:8025 for all sent emails
- **Database GUI**: Use any PostgreSQL client to connect to `localhost:5432`
  - Database: `chatwoot`
  - Username: `postgres`
  - Password: `postgres`

## 🧪 Testing

```powershell
# Frontend tests
pnpm test

# Backend tests  
bundle exec rspec

# Linting
pnpm eslint:fix
bundle exec rubocop -a
```

## 📝 Git Commits

The pre-commit hook has been fixed. If you still have issues:

```powershell
# Commit without hooks (temporary)
git commit --no-verify -m "your message"

# Or fix linting first
pnpm eslint:fix
bundle exec rubocop -a
git commit -m "your message"
```

## 🔄 Daily Workflow

1. Start Docker services (if not running):
   ```powershell
   docker-compose -f docker-compose.simple.yaml up -d
   ```

2. Start Rails, Sidekiq, and Vite in 3 terminals

3. Code and test at http://localhost:3000

4. Stop services when done:
   ```powershell
   # Ctrl+C in each terminal
   docker-compose -f docker-compose.simple.yaml down
   ```

## Alternative: WSL2

If you have issues with Ruby on Windows, WSL2 is a great alternative.
See `WSL_SETUP_GUIDE.md` for instructions.
