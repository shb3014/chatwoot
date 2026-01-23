# WSL2 Setup - Complete Guide

## ✅ What's Already Done

1. **Docker Services Running** ✅
   - PostgreSQL with your 4,681 conversations
   - Redis 
   - MailHog

2. **Configuration Files Ready** ✅
   - `.env` configured for localhost
   - `docker-compose.simple.yaml` for infrastructure

3. **Code Cleaned Up** ✅
   - Ruby version files reverted to 3.4.4
   - No Windows-specific changes in code

## 🚀 WSL2 Installation Steps

### Step 1: Install WSL2 (Run as Administrator)

Open **PowerShell as Administrator** (Right-click Start → Windows PowerShell (Admin)):

```powershell
wsl --install -d Ubuntu-24.04
```

This will:
- Enable WSL2 feature
- Download Ubuntu 24.04
- Set it as default

**Restart your computer when prompted.**

### Step 2: Initial Ubuntu Setup (After Restart)

Ubuntu will open automatically. Set up your account:

```
Enter new UNIX username: gordon  (or whatever you prefer)
New password: [enter password]
Retype new password: [enter password]
```

### Step 3: Install System Dependencies

In the Ubuntu terminal:

```bash
# Update package list
sudo apt update

# Install build tools and Ruby dependencies
sudo apt install -y \
  git \
  curl \
  build-essential \
  libssl-dev \
  libreadline-dev \
  zlib1g-dev \
  autoconf \
  bison \
  libyaml-dev \
  libncurses5-dev \
  libffi-dev \
  libgdbm-dev \
  libpq-dev
```

### Step 4: Install rbenv (Ruby Version Manager)

```bash
# Download and install rbenv
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash

# Add rbenv to your shell
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc

# Reload shell configuration
source ~/.bashrc

# Verify rbenv is installed
rbenv --version
```

### Step 5: Install Ruby 3.4.4

```bash
# Install Ruby 3.4.4 (this takes 5-10 minutes)
rbenv install 3.4.4

# Set as global default
rbenv global 3.4.4

# Verify installation
ruby --version
# Should output: ruby 3.4.4

# Install Bundler
gem install bundler
```

### Step 6: Install Node.js and pnpm

```bash
# Install Node.js 23.x
curl -fsSL https://deb.nodesource.com/setup_23.x | sudo -E bash -
sudo apt install -y nodejs

# Verify Node.js
node --version  # Should be v23.x

# Install pnpm
curl -fsSL https://get.pnpm.io/install.sh | sh -

# Reload shell to get pnpm in PATH
source ~/.bashrc

# Verify pnpm
pnpm --version  # Should be 10.x
```

### Step 7: Navigate to Your Project

```bash
# Go to your Windows project folder
cd /mnt/c/Users/Gordon/Desktop/WebApps/chatwoot

# Verify you're in the right place
ls -la  # Should see Gemfile, package.json, etc.
```

### Step 8: Install Project Dependencies

```bash
# Install Ruby gems (takes 5-10 minutes)
bundle install

# Install Node packages (takes 3-5 minutes)
pnpm install
```

### Step 9: Run Database Migrations (If Needed)

```bash
# Check if migrations are needed
bin/rails db:migrate:status

# Run migrations
bin/rails db:migrate
```

### Step 10: Start Chatwoot Services

Open **3 separate WSL terminals** (you can open new Ubuntu terminals from Start menu):

#### Terminal 1 - Rails Server
```bash
cd /mnt/c/Users/Gordon/Desktop/WebApps/chatwoot
bin/rails s -p 3000 -b 0.0.0.0
```

#### Terminal 2 - Sidekiq (Background Jobs)
```bash
cd /mnt/c/Users/Gordon/Desktop/WebApps/chatwoot
bundle exec sidekiq -C config/sidekiq.yml
```

#### Terminal 3 - Vite (Frontend Assets)
```bash
cd /mnt/c/Users/Gordon/Desktop/WebApps/chatwoot
bin/vite dev
```

### Step 11: Access Your Application

Open your Windows browser:
- **Chatwoot**: http://localhost:3000
- **MailHog**: http://localhost:8025

Login with your cloud credentials! 🎉

## 🔧 Development Workflow

### Daily Startup

1. **Start Docker** (Windows PowerShell):
   ```powershell
   docker-compose -f docker-compose.simple.yaml up -d
   ```

2. **Start Chatwoot** (3 WSL terminals as shown above)

### Editing Code

**Option A: Cursor with WSL Extension (Recommended)**
1. Install "WSL" extension in Cursor
2. Click green icon in bottom-left corner
3. Select "Connect to WSL"
4. Open folder: `/mnt/c/Users/Gordon/Desktop/WebApps/chatwoot`

**Option B: Edit in Windows**
- Files in `/mnt/c/` are your Windows files
- Edit normally in Cursor on Windows
- Run commands in WSL terminal

### Stopping Services

```powershell
# In each WSL terminal: Ctrl+C

# Stop Docker (Windows PowerShell):
docker-compose -f docker-compose.simple.yaml down
```

## 🧪 Testing Your Changes

```bash
# Frontend tests
pnpm test

# Backend tests
bundle exec rspec

# Linting
pnpm eslint:fix
bundle exec rubocop -a
```

## 🐛 Troubleshooting

### Can't connect to PostgreSQL?

Make sure Docker is running on Windows:
```powershell
docker ps  # Should show 3 containers
```

WSL2 can access Windows localhost automatically.

### Ruby command not found?

```bash
source ~/.bashrc
rbenv global 3.4.4
ruby --version
```

### Bundle install fails?

Make sure you have all dependencies:
```bash
sudo apt install -y libpq-dev libssl-dev libreadline-dev
bundle install
```

### Port 3000 already in use?

Check what's using it:
```bash
lsof -i :3000
# Kill the process or use a different port:
bin/rails s -p 3001
```

## 📊 What's Where

- **Docker** (Windows): PostgreSQL, Redis, MailHog
- **Code** (Windows): C:\Users\Gordon\Desktop\WebApps\chatwoot
- **WSL Access**: /mnt/c/Users/Gordon/Desktop/WebApps/chatwoot
- **Ruby/Node** (WSL): Linux environment, no compilation issues
- **Browser** (Windows): http://localhost:3000

## ✨ Benefits

- ✅ Native Linux environment (no gem compilation issues)
- ✅ Correct Ruby 3.4.4 (matches project)
- ✅ All 4,681 conversations ready to use
- ✅ Edit in Windows, run in Linux
- ✅ Fast, reliable, industry-standard setup

## 📝 Summary

1. Install WSL2 (restart required)
2. Install Ruby 3.4.4 via rbenv
3. Install Node.js 23 and pnpm
4. Navigate to `/mnt/c/Users/Gordon/Desktop/WebApps/chatwoot`
5. Run `bundle install` and `pnpm install`
6. Start 3 services in 3 terminals
7. Access at http://localhost:3000

Your cloud data is waiting! 🚀
