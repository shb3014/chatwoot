# Quick Sync Commands - VPS to Local

## On Your VPS (via SSH)

```bash
# Navigate to a temporary directory
cd /tmp

# Option A: If Chatwoot is running with Docker on VPS
docker exec chatwoot-postgres-1 pg_dump -U postgres chatwoot_production -F c -b -v > chatwoot_backup.dump

# Option B: If PostgreSQL is installed natively on VPS
# Replace with your actual credentials:
pg_dump -h localhost -U chatwoot_db_user -d chatwoot_production -F c -b -v -f chatwoot_backup.dump

# Compress the backup
gzip chatwoot_backup.dump

# Check the file size
ls -lh chatwoot_backup.dump.gz

# Make it accessible for download (optional, if permissions needed)
chmod 644 chatwoot_backup.dump.gz
```

## On Your Windows Machine

```powershell
# Download the backup (replace with your VPS details)
scp your_user@your_vps_ip:/tmp/chatwoot_backup.dump.gz C:\Users\Gordon\Desktop\

# Decompress (if you have 7-Zip installed)
# Right-click the file and "Extract Here"
# Or use PowerShell:
# Expand-Archive requires .zip, so for .gz you might need 7-Zip or:
# Install 7-Zip, then:
& "C:\Program Files\7-Zip\7z.exe" x C:\Users\Gordon\Desktop\chatwoot_backup.dump.gz

# OR download uncompressed directly (if file isn't too large):
scp your_user@your_vps_ip:/tmp/chatwoot_backup.dump C:\Users\Gordon\Desktop\
```

## Import to Local Docker PostgreSQL

```powershell
# Make sure Docker services are running
docker ps

# Copy dump to Docker container
docker cp C:\Users\Gordon\Desktop\chatwoot_backup.dump chatwoot-postgres-1:/tmp/

# Drop existing database (WARNING: destroys local data)
docker exec -it chatwoot-postgres-1 psql -U postgres -c "DROP DATABASE IF EXISTS chatwoot;"

# Create fresh database
docker exec -it chatwoot-postgres-1 psql -U postgres -c "CREATE DATABASE chatwoot;"

# Restore the backup
docker exec -it chatwoot-postgres-1 pg_restore -U postgres -d chatwoot --clean --no-owner --no-acl -v /tmp/chatwoot_backup.dump

# Verify data was imported
docker exec -it chatwoot-postgres-1 psql -U postgres -d chatwoot -c "SELECT COUNT(*) FROM accounts;"
docker exec -it chatwoot-postgres-1 psql -U postgres -d chatwoot -c "SELECT COUNT(*) FROM users;"
```

## Run Migrations (if local code is newer)

```powershell
cd C:\Users\Gordon\Desktop\WebApps\chatwoot

# Run any pending migrations
bin/rails db:migrate
```

## Start Local Chatwoot

```powershell
# Terminal 1 - Rails Server
bin/rails s -p 3000

# Terminal 2 - Sidekiq (Background Jobs)
bundle exec sidekiq -C config/sidekiq.yml

# Terminal 3 - Vite (Frontend Assets)
bin/vite dev
```

## Access Your Local Instance

- **Application**: http://localhost:3000
- **Email Testing**: http://localhost:8025
- **Login**: Use your cloud credentials

## Optional: Reset Admin Password for Local

```powershell
# Start Rails console
bin/rails console

# In console:
user = User.find_by(email: 'your-admin@email.com')
user.password = 'local-dev-password'
user.password_confirmation = 'local-dev-password'
user.save!
exit
```

## Cleanup (Optional)

```powershell
# Delete local dump file after import
Remove-Item C:\Users\Gordon\Desktop\chatwoot_backup.dump

# On VPS (via SSH):
rm /tmp/chatwoot_backup.dump.gz
```

## Common Issues

### If restore fails with "already exists" errors:
```powershell
# Use --clean flag (already included above)
# Or manually drop all tables first
```

### If you get "permission denied":
```powershell
# On VPS, check file permissions:
chmod 644 /tmp/chatwoot_backup.dump.gz
```

### If database is in use:
```powershell
# Terminate all connections first
docker exec -it chatwoot-postgres-1 psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='chatwoot' AND pid <> pg_backend_pid();"
```
