# Cron Module

This module manages cron jobs at container startup using a **custom container-compatible cron engine**. Perfect for web applications and automated tasks.

## Features

- ✅ **Container-native cron engine** - no system cron dependency required
- ✅ Conditional execution based on `CRON_STATUS` (1/0)
- ✅ Configurable crontab file location  
- ✅ Automatic creation of helpful crontab template
- ✅ Robust syntax validation and error handling
- ✅ Background cron daemon with PID management
- ✅ Comprehensive logging without sensitive data exposure
- ✅ Handles command substitution (`$(date)`, `$USER`, etc.) safely
- ✅ GDPR-compliant logging (no user data in logs)

## Configuration

| Environment Variable | Default                            | Description                                    |
|----------------------|------------------------------------|--------------------------------------------- |
| `CRON_STATUS`        | `false`                            | Enable (`true`/`1`) or disable (`false`/`0`) |
| `CRON_CONFIG_FILE`   | `/home/container/crontab`          | Path to the crontab configuration file       |
| `CRON_LOG_FILE`      | `/home/container/logs/cron.log`    | Path to cron engine log file                 |
| `CRON_PID_FILE`      | `/home/container/tmp/cron.pid`     | Path to store cron engine PID                |

## Usage

### 1. Enable Cron Module
Set `CRON_STATUS=1` in your Pelican panel variables.

### 2. Configure Cron Jobs
Edit `/home/container/crontab` with your cron jobs:

```bash
# Web application maintenance every hour
0 * * * * /home/container/www/maintenance.sh >> /home/container/logs/maintenance.log 2>&1

# Database backup daily at 2 AM
0 2 * * * mysqldump -u user -p database > /home/container/backups/db-$(date +%Y%m%d).sql 2>/dev/null

# Daily maintenance reminder (never delete live runtime files)
0 0 * * * echo "Daily maintenance reminder"

# Weekly rotation reminder (configure your own rotation policy)
0 0 * * 0 echo "Review log rotation and backups"
```

### 3. Common Use Cases

#### System Maintenance
```bash
# Clean cache every hour
0 * * * * rm -rf /home/container/www/cache/* >> /home/container/logs/cache-clean.log 2>&1

# Update application every night
0 3 * * * cd /home/container/www && git pull origin main >> /home/container/logs/git-update.log 2>&1
```

#### Backups and Monitoring
```bash
# Create daily backup with timestamp
0 2 * * * tar -czf /home/container/backups/backup-$(date +%Y%m%d).tar.gz /home/container/www

# Monitor disk space every 6 hours
0 */6 * * * df -h > /home/container/logs/disk-usage-$(date +%Y%m%d).log
```

#### Dynamic Commands with Variables
```bash
# Commands with date substitution work perfectly
0 3 * * * echo "Backup completed at $(date)" >> /home/container/logs/backup-$(date +%Y%m%d).log

# Environment variables are supported
* * * * * echo "Running as user: $USER" >> /home/container/logs/user.log

# Complex commands with variables
0 1 * * * cd /home/container/www && ./backup.sh --filename=backup-$(date +%Y%m%d-%H%M).zip
```

## How It Works

This module uses a **custom cron engine** written in Bash that:

1. 🔄 **Runs continuously** in the background as a daemon
2. ⏱️ **Checks every minute** for jobs to execute  
3. 🎯 **Parses crontab safely** without shell expansion issues
4. 📝 **Logs all activity** to dedicated log files
5. 🚀 **Executes commands** with full shell capabilities

The five time fields support numeric values, `*`, inclusive ranges (`1-5`),
comma lists (`0,15,30,45`), and positive steps (`*/6`, `1-23/2`).
A numeric step such as `5/10` runs from 5 through the field's maximum.
Values must be in the field's normal cron range; steps are 1–99.
Sunday can be `0` or `7`. If both day-of-month and day-of-week are restricted,
either may match; if either starts with `*`, both must match.
Invalid fields (including names such as `MON` and shortcuts such as `@daily`)
are logged and skipped. Commands are executed by Bash, so only trusted users
should edit the crontab.

## Egg JSON Configuration

Add these variables to your `egg-nginx-v2.json`:

```json
{
  "name": "Enable Cron Module",
  "description": "Enable container-native cron job scheduling",
  "env_variable": "CRON_STATUS", 
  "default_value": "0",
  "user_viewable": true,
  "user_editable": true,
  "rules": "required|boolean",
  "field_type": "text"
},
{
  "name": "Cron Config File",
  "description": "Path to crontab configuration file",
  "env_variable": "CRON_CONFIG_FILE",
  "default_value": "/home/container/crontab",
  "user_viewable": true,
  "user_editable": true,
  "rules": "required|string", 
  "field_type": "text"
}
```

## Docker Requirements

**No additional packages required!** This module uses a pure Bash implementation.

~~```dockerfile~~
~~RUN apt-get update && apt-get install -y \~~
~~    cron \~~
~~    && rm -rf /var/lib/apt/lists/*~~
~~```~~

## Troubleshooting

### Check Cron Status
```bash
# View cron engine log
tail -f /home/container/logs/cron.log

# Check if cron engine is running
ps aux | grep cron-engine

# View PID file
cat /home/container/tmp/cron.pid

# Check active cron jobs
cat /home/container/crontab
```

### Common Issues

1. **Jobs not executing**: Check `/home/container/logs/cron.log` for errors
2. **Syntax errors**: Ensure each line has 5 time fields + command
3. **Path issues**: Always use absolute paths in commands
4. **Script failures**: Verify script permissions and paths
5. **Command substitution**: Our engine handles `$(date)`, `$USER` etc. correctly

### Debug Mode
Add test jobs to verify functionality:
```bash
# Simple test every minute
* * * * * echo "Test: $(date)" >> /home/container/logs/cron-test.log

# Environment test
* * * * * env > /home/container/logs/cron-env.log 2>&1

# Script execution test
* * * * * /home/container/www/test-script.sh >> /home/container/logs/script-test.log 2>&1
```

## Best Practices

1. ✅ **Use absolute paths** in all commands
2. ✅ **Redirect output** to log files for debugging  
3. ✅ **Make scripts executable** with `chmod +x`
4. ✅ **Monitor log files** regularly for errors
5. ✅ **Test commands manually** before adding to crontab
6. ✅ **Use meaningful log filenames** with dates when needed
7. ✅ **Set proper file permissions** for security

## Example Cron Patterns

```bash
# Every minute
* * * * * command

# Every hour at minute 0
0 * * * * command

# Daily at 2:30 AM
30 2 * * * command

# Weekly on Sundays at midnight
0 0 * * 0 command

# Monthly on the 1st at 3:00 AM
0 3 1 * * command

# Every 15 minutes
*/15 * * * * command

# Every 6 hours
0 */6 * * * command

# Weekdays only at 9 AM
0 9 * * 1-5 command
```

## Module Architecture

```
modules/cron/
├── start.sh          # Module initialization and cron engine startup
├── cron-engine.sh    # Custom container-compatible cron daemon  
└── README.md         # This documentation
```

The cron engine runs as a background process and continuously monitors the crontab file for jobs to execute, providing a robust alternative to system cron in containerized environments.