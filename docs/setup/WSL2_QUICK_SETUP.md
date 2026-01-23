# Quick WSL2 Setup - Your Data is Already Ready!

Good news: Your cloud database is already imported in Docker! WSL2 can connect to it.

## Step 1: Install WSL2 (5 minutes)

Open PowerShell as Administrator:

```powershell
wsl --install -d Ubuntu-24.04
```

Restart your computer when prompted. After restart, Ubuntu will open automatically:
- Set your Ubuntu username
- Set your Ubuntu password

## Step 2: Access Your Project in WSL (1 minute)

Open Ubuntu from Start Menu:

```bash
# Navigate to your Windows project
cd /mnt/c/Users/Gordon/Desktop/WebApps/chatwoot
```

## Step 3: Install Dependencies in WSL (10 minutes)

```bash
# Update system
sudo apt update

# Install Ruby dependencies
sudo apt install -y git curl libssl-dev libreadline-dev zlib1g-dev \
  autoconf bison build-essential libyaml-dev libncurses5-dev \
  libffi-dev libgdbm-dev libpq-dev

# Install rbenv (Ruby version manager)
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash

# Add to shell
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

# Install Ruby 3.4.4 (the correct version)
rbenv install 3.4.4
rbenv global 3.4.4

# Verify
ruby --version  # Should show 3.4.4

# Install Bundler
gem install bundler

# Install pnpm
curl -fsSL https://get.pnpm.io/install.sh | sh -
source ~/.bashrc
```

## Step 4: Install Project Dependencies (5 minutes)

```bash
# Make sure you're in the project directory
cd /mnt/c/Users/Gordon/Desktop/WebApps/chatwoot

# Install Ruby gems
bundle install

# Install Node packages
pnpm install
```

## Step 5: Configure to Use Docker PostgreSQL

Your `.env` file should already have localhost settings. WSL2 can access Windows Docker via `localhost`:

```bash
# Check your .env file
cat .env

# It should have:
# POSTGRES_HOST=localhost
# POSTGRES_PORT=5432
# POSTGRES_DATABASE=chatwoot
# POSTGRES_USERNAME=postgres
# POSTGRES_PASSWORD=postgres
#
# REDIS_URL=redis://localhost:6379
# REDIS_PASSWORD=redis_password
```

## Step 6: Run Migrations (if needed)

```bash
bin/rails db:migrate
```

## Step 7: Start Chatwoot (3 separate terminals)

### Terminal 1 - Rails Server
```bash
cd /mnt/c/Users/Gordon/Desktop/WebApps/chatwoot
bin/rails s -p 3000
```

### Terminal 2 - Sidekiq  
```bash
cd /mnt/c/Users/Gordon/Desktop/WebApps/chatwoot
bundle exec sidekiq -C config/sidekiq.yml
```

### Terminal 3 - Vite
```bash
cd /mnt/c/Users/Gordon/Desktop/WebApps/chatwoot
bin/vite dev
```

## Step 8: Access Your App

Open browser on Windows:
- **Application**: http://localhost:3000
- **Email Testing**: http://localhost:8025
- **Login with your cloud credentials!**

## Managing Docker Services

From Windows PowerShell (keep Docker running):

```powershell
# Check services
docker ps

# Stop services
docker-compose -f docker-compose.simple.yaml down

# Start services
docker-compose -f docker-compose.simple.yaml up -d
```

## Benefits

- ✅ Your 4,681 conversations already imported
- ✅ No native gem compilation issues
- ✅ Use Cursor/VS Code with WSL extension
- ✅ Edit files in Windows, run in Linux
- ✅ Docker PostgreSQL stays on Windows, accessible from WSL

## Editing Code

### Option 1: Cursor with WSL Extension
1. Install "WSL" extension in Cursor
2. Click the green button in bottom-left corner
3. Select "Connect to WSL"
4. Open folder: `/mnt/c/Users/Gordon/Desktop/WebApps/chatwoot`

### Option 2: Edit in Windows
Files in `/mnt/c/` are your Windows files. Edit them normally in Cursor on Windows, run commands in WSL terminal.

## Daily Workflow

1. **Start Docker** (Windows):
   ```powershell
   docker-compose -f docker-compose.simple.yaml up -d
   ```

2. **Open 3 WSL terminals** and start services

3. **Code in Cursor** (Windows or WSL mode)

4. **Test at** http://localhost:3000

## Troubleshooting

### Can't connect to PostgreSQL from WSL?

Check if Windows firewall is blocking. Usually localhost works automatically with WSL2.

### Ruby not found after install?

```bash
source ~/.bashrc
rbenv global 3.4.4
```

### Bundle install fails?

Make sure you have libpq-dev:
```bash
sudo apt install -y libpq-dev
```

## Why This is Better Than Native Windows

- ❌ Windows: Multiple gem compilation failures
- ✅ WSL2: Clean install, no issues
- ❌ Windows: Ruby 3.4.8 vs 3.4.4 mismatch
- ✅ WSL2: Exact version (3.4.4)
- ❌ Windows: Hours of troubleshooting
- ✅ WSL2: 15 minutes total setup

Your data is safe in Docker, accessible from both Windows and WSL! 🎉
