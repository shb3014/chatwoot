# Sync Cloud Chatwoot Data to Local Development

This guide helps you copy your production/cloud Chatwoot data to your local development environment.

## ⚠️ Important Considerations

1. **Data Privacy**: Make sure you're authorized to copy production data locally
2. **Sensitive Data**: Production contains real customer data - handle carefully
3. **Storage Space**: Check you have enough disk space for the database dump
4. **Credentials**: You'll work with sensitive credentials - don't commit them

## 📋 Prerequisites

- Access to your cloud server (SSH)
- PostgreSQL client tools installed locally
- Docker services running locally (`docker ps` shows postgres, redis, mailhog)

## 🔄 Method 1: Direct Database Dump & Restore (Recommended)

### Step 1: Dump Database from Cloud Server

SSH into your cloud server and create a database backup:

```bash
# SSH into your cloud server
ssh user@your-cloud-server.com

# Create a database dump
# Replace with your actual database credentials
pg_dump -h localhost -U chatwoot_user -d chatwoot_production -F c -b -v -f chatwoot_backup.dump

# Or if using Docker on cloud:
docker exec chatwoot-postgres pg_dump -U postgres chatwoot_production -F c -b -v > chatwoot_backup.dump

# Compress the dump (optional but recommended)
gzip chatwoot_backup.dump
```

### Step 2: Download the Dump to Your Local Machine

From your local Windows machine:

```powershell
# Using SCP (in PowerShell)
scp user@your-cloud-server.com:~/chatwoot_backup.dump.gz C:\Users\Gordon\Desktop\

# Or use WinSCP, FileZilla, or any SFTP client
```

### Step 3: Import into Local Docker PostgreSQL

```powershell
# Navigate to where you downloaded the dump
cd C:\Users\Gordon\Desktop\

# If compressed, decompress first
# (You might need 7-Zip or similar on Windows)

# Drop existing local database and recreate (WARNING: destroys local data)
docker exec -it chatwoot-postgres-1 psql -U postgres -c "DROP DATABASE IF EXISTS chatwoot;"
docker exec -it chatwoot-postgres-1 psql -U postgres -c "CREATE DATABASE chatwoot;"

# Restore the dump
# Option A: If you have pg_restore locally
pg_restore -h localhost -p 5432 -U postgres -d chatwoot -v chatwoot_backup.dump

# Option B: Copy dump into container and restore
docker cp chatwoot_backup.dump chatwoot-postgres-1:/tmp/
docker exec -it chatwoot-postgres-1 pg_restore -U postgres -d chatwoot -v /tmp/chatwoot_backup.dump

# If you get errors about existing objects, use --clean flag:
docker exec -it chatwoot-postgres-1 pg_restore -U postgres -d chatwoot -v --clean /tmp/chatwoot_backup.dump
```

### Step 4: Update Local Environment Variables

Your local `.env` file needs to match some cloud settings:

```powershell
# Make sure your .env has:
FRONTEND_URL=http://localhost:3000
RAILS_ENV=development

# Keep your local database credentials:
POSTGRES_HOST=localhost
POSTGRES_DATABASE=chatwoot
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=postgres
```

### Step 5: Run Migrations (if needed)

```powershell
# If your local code is ahead of cloud, run pending migrations
bin/rails db:migrate
```

## 🔄 Method 2: Using Heroku (if on Heroku)

If your cloud instance is on Heroku:

```powershell
# Install Heroku CLI first: https://devcenter.heroku.com/articles/heroku-cli

# Login to Heroku
heroku login

# Get a database backup URL
heroku pg:backups:capture --app your-chatwoot-app
heroku pg:backups:download --app your-chatwoot-app

# This downloads latest.dump
# Import into local Docker
docker cp latest.dump chatwoot-postgres-1:/tmp/
docker exec -it chatwoot-postgres-1 pg_restore -U postgres -d chatwoot -v --clean --no-owner --no-acl /tmp/latest.dump
```

## 📁 Syncing File Uploads/Attachments (Optional)

If you want to sync uploaded files (avatars, attachments):

### If using AWS S3:

```powershell
# Install AWS CLI: https://aws.amazon.com/cli/

# Configure AWS credentials
aws configure

# Sync S3 bucket to local storage directory
# This can be LARGE - consider syncing only recent files
aws s3 sync s3://your-chatwoot-bucket ./storage/
```

### If using local file storage on cloud:

```powershell
# Use rsync (via WSL) or WinSCP to sync the storage directory
scp -r user@your-cloud-server.com:/path/to/chatwoot/storage/* ./storage/
```

## 🔧 Post-Import Tasks

### 1. Verify Database Connection

```powershell
# Try connecting to local database
docker exec -it chatwoot-postgres-1 psql -U postgres -d chatwoot -c "SELECT COUNT(*) FROM accounts;"
```

### 2. Reset Admin Password (Recommended for Security)

```powershell
# Start Rails console
bin/rails console

# In the Rails console, reset a user's password:
user = User.find_by(email: 'your-email@example.com')
user.password = 'newlocalpassword'
user.password_confirmation = 'newlocalpassword'
user.save!

# Exit console
exit
```

### 3. Disable External Services (Optional)

To avoid accidentally sending real emails or notifications from local:

```powershell
# Add to your .env:
# SMTP_ADDRESS=localhost
# SMTP_PORT=1025
# (Already set for MailHog)
```

### 4. Start Your Local Chatwoot

```powershell
# Terminal 1: Rails
bin/rails s -p 3000

# Terminal 2: Sidekiq
bundle exec sidekiq -C config/sidekiq.yml

# Terminal 3: Vite
bin/vite dev
```

### 5. Test the Application

Visit http://localhost:3000 and login with your cloud credentials (or reset password).

## 🔄 Keeping Local Data in Sync

### Option A: Automated Script (Create a sync script)

Create `sync_from_cloud.ps1`:

```powershell
# sync_from_cloud.ps1
Write-Host "Syncing data from cloud..." -ForegroundColor Green

# Dump from cloud
ssh user@cloud "pg_dump -U postgres chatwoot_production -F c > /tmp/latest.dump"

# Download
scp user@cloud:/tmp/latest.dump ./

# Import locally
docker exec -it chatwoot-postgres-1 psql -U postgres -c "DROP DATABASE IF EXISTS chatwoot;"
docker exec -it chatwoot-postgres-1 psql -U postgres -c "CREATE DATABASE chatwoot;"
docker cp latest.dump chatwoot-postgres-1:/tmp/
docker exec -it chatwoot-postgres-1 pg_restore -U postgres -d chatwoot --clean --no-owner --no-acl /tmp/latest.dump

Write-Host "Sync complete!" -ForegroundColor Green
```

Run it: `.\sync_from_cloud.ps1`

### Option B: Manual Sync as Needed

Just repeat Steps 1-3 whenever you need fresh data.

## 🐛 Troubleshooting

### Error: "role does not exist"

```powershell
# Restore with --no-owner flag
docker exec -it chatwoot-postgres-1 pg_restore -U postgres -d chatwoot --no-owner --no-acl /tmp/chatwoot_backup.dump
```

### Error: "database is being accessed by other users"

```powershell
# Stop Rails/Sidekiq first, then:
docker exec -it chatwoot-postgres-1 psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='chatwoot';"
docker exec -it chatwoot-postgres-1 psql -U postgres -c "DROP DATABASE chatwoot;"
docker exec -it chatwoot-postgres-1 psql -U postgres -c "CREATE DATABASE chatwoot;"
```

### Dump file is too large

```powershell
# Dump only schema and recent data
# On cloud server:
pg_dump -U postgres chatwoot_production \
  --exclude-table-data='action_mailbox_inbound_emails' \
  --exclude-table-data='active_storage_blobs' \
  -F c > smaller_dump.dump
```

### SSL/Connection issues

```powershell
# If cloud database requires SSL, on cloud:
pg_dump "postgresql://user:pass@host:5432/dbname?sslmode=require" -F c > dump.dump
```

## 📊 Alternative: Copy Specific Data Only

If you only need specific accounts or conversations:

```powershell
# On cloud, export specific account data
pg_dump -U postgres chatwoot_production \
  --table=accounts \
  --table=users \
  --table=conversations \
  --table=messages \
  -F c > partial_dump.dump
```

## 🔒 Security Best Practices

1. **Never commit dumps** to Git - add `*.dump` to `.gitignore`
2. **Delete dumps after import** - they contain sensitive data
3. **Use different passwords** locally than production
4. **Disable production integrations** in local `.env`
5. **Consider anonymizing data** for development if required by policy

## 📝 Summary

1. Dump cloud database
2. Download to local machine
3. Import into local Docker PostgreSQL
4. Update `.env` for local settings
5. Run migrations if needed
6. Test at http://localhost:3000

Your local environment now mirrors your cloud data! 🎉
