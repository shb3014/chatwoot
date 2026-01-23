# Chatwoot Setup on WSL2 (Windows Subsystem for Linux)

This is the recommended approach for Windows when Docker has network issues.

## Step 1: Install WSL2

Open PowerShell as Administrator and run:

```powershell
wsl --install -d Ubuntu-24.04
```

Restart your computer when prompted, then set up your Ubuntu username/password.

## Step 2: Open WSL Terminal

Open Ubuntu from Start Menu or run:

```powershell
wsl
```

## Step 3: Navigate to Project

```bash
# Navigate to your Windows project folder from WSL
cd /mnt/c/Users/Gordon/Desktop/WebApps/chatwoot
```

## Step 4: Install Dependencies in WSL

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install PostgreSQL with pgvector
sudo apt install -y postgresql postgresql-contrib libpq-dev
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Install Redis
sudo apt install -y redis-server
sudo systemctl start redis
sudo systemctl enable redis

# Install Ruby dependencies
sudo apt install -y git curl libssl-dev libreadline-dev zlib1g-dev \
  autoconf bison build-essential libyaml-dev libreadline-dev \
  libncurses5-dev libffi-dev libgdbm-dev

# Install rbenv (Ruby version manager)
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash

# Add rbenv to your PATH
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

# Install Ruby (check .ruby-version file for exact version needed)
rbenv install 3.3.6  # or version from .ruby-version
rbenv global 3.3.6

# Install Node.js 23
curl -fsSL https://deb.nodesource.com/setup_23.x | sudo -E bash -
sudo apt install -y nodejs

# Install pnpm
sudo npm install -g pnpm@10

# Install Bundler
gem install bundler
```

## Step 5: Setup Database

```bash
# Create PostgreSQL user
sudo -u postgres createuser -s $USER
sudo -u postgres psql -c "ALTER USER $USER WITH PASSWORD '';"

# Enable pgvector extension
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

## Step 6: Install Project Dependencies

```bash
# Install Ruby gems
bundle install

# Install Node packages
pnpm install
```

## Step 7: Setup Database

```bash
# Create and migrate database
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

## Step 8: Create .env file

Create a `.env` file in the project root:

```bash
# Rails
RAILS_ENV=development
NODE_ENV=development
FRONTEND_URL=http://localhost:3000

# Database
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DATABASE=chatwoot_dev
POSTGRES_USERNAME=$USER
POSTGRES_PASSWORD=

# Redis
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=

# Mailer
MAILER_SENDER_EMAIL=dev@chatwoot.local

# Storage
ACTIVE_STORAGE_SERVICE=local
LOG_LEVEL=debug
```

## Step 9: Start the Application

### Option A: Using overmind (recommended)

```bash
# Install overmind
sudo apt install -y tmux
wget https://github.com/DarthSim/overmind/releases/download/v2.5.1/overmind-v2.5.1-linux-amd64.gz
gunzip overmind-v2.5.1-linux-amd64.gz
chmod +x overmind-v2.5.1-linux-amd64
sudo mv overmind-v2.5.1-linux-amd64 /usr/local/bin/overmind

# Start all services
pnpm dev
```

### Option B: Manual in separate terminals

Terminal 1:
```bash
bin/rails s -p 3000
```

Terminal 2:
```bash
bundle exec sidekiq -C config/sidekiq.yml
```

Terminal 3:
```bash
bin/vite dev
```

## Step 10: Access the Application

Open your browser on Windows and visit:
- **App**: http://localhost:3000
- **Sign up** to create your first user account

## Troubleshooting

### PostgreSQL connection error
```bash
sudo systemctl status postgresql
sudo systemctl restart postgresql
```

### Redis connection error
```bash
sudo systemctl status redis
sudo systemctl restart redis
```

### Permission issues
```bash
# Fix file permissions
chmod +x bin/*
```

## Benefits of WSL2

- ✅ Native Linux environment on Windows
- ✅ Better performance than Docker on Windows
- ✅ Direct access to Windows files
- ✅ Better network handling
- ✅ Can use Linux development tools

## Notes

- Your files are accessible from Windows at `\\wsl$\Ubuntu-24.04\home\<username>`
- You can edit files with VS Code/Cursor using the WSL extension
- Services in WSL can be accessed from Windows via localhost
