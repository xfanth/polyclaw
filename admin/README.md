# Admin Activity Dashboard

This feature provides an admin interface for monitoring user activities in the OpenClaw/PicoClaw/IronClaw/ZeroClaw Docker container.

## Features

- **Activity Logging**: Automatically logs user activities including:
  - Login/logout events
  - Configuration changes
  - Input changes
  - Save/load operations
  - Errors and warnings

- **Admin Dashboard**: Web interface to view and filter activities
  - Filter by user, activity type, date range
  - View activity statistics
  - Pagination support
  - Real-time activity stream

## Configuration

Add to your `.env` file:

```env
# Enable activity logging (default: true)
ACTIVITY_LOG_ENABLED=true

# Activity log directory (default: /data/.{UPSTREAM}/activity)
# ACTIVITY_LOG_DIR=/data/.zeroclaw/activity

# Admin API port for dashboard (default: 8888)
ADMIN_API_PORT=8888
```

## Accessing the Dashboard

After starting the container, access the admin dashboard at:

```
http://localhost:8888/admin
```

Replace `8888` with your configured `ADMIN_API_PORT` if different.

## Activity Log Format

Activities are stored in JSON Lines format (one JSON object per line) in:

```
/data/.{UPSTREAM}/activity/activities_YYYY-MM-DD.jsonl
```

Example activity entry:

```json
{
  "timestamp": "2026-02-19T10:30:00.000Z",
  "user": "admin",
  "activity": "login",
  "description": "User logged in",
  "source": "web",
  "details": {
    "ip": "192.168.1.100"
  }
}
```

## API Endpoints

### GET /api/admin/activities

Retrieve activities with optional filters.

Query parameters:
- `user` - Filter by username
- `type` - Filter by activity type
- `start` - Start time (ISO format)
- `end` - End time (ISO format)
- `limit` - Maximum results (default: 100)
- `offset` - Pagination offset (default: 0)

Example:

```bash
curl "http://localhost:8888/api/admin/activities?user=admin&type=login&limit=10"
```

### GET /api/admin/stats

Get activity statistics.

Query parameters:
- `days` - Number of days to analyze (default: 7)

Example:

```bash
curl "http://localhost:8888/api/admin/stats?days=7"
```

Response:

```json
{
  "total_activities": 150,
  "unique_users": 5,
  "activity_types": {
    "login": 50,
    "config_change": 30,
    "save": 70
  },
  "top_users": {
    "admin": 100,
    "user1": 50
  },
  "period_days": 7
}
```

## Programmatic Usage

### Python

```python
from activity import log_login, log_config_change, get_logger

# Log a user login
log_login('john_doe', source='web', details={'ip': '192.168.1.100'})

# Log a configuration change
log_config_change('admin', changes={'model': 'gpt-4'}, source='api')

# Query activities
logger = get_logger()
activities = logger.get_activities(user='admin', limit=10)
```

### Node.js

```javascript
const { logLogin, logConfigChange, getLogger } = require('./lib/activity.js');

// Log a user login
logLogin('john_doe', 'web', { ip: '192.168.1.100' });

// Log a configuration change
logConfigChange('admin', { model: 'gpt-4' }, 'api');

// Query activities
const logger = getLogger();
const activities = logger.getActivities({ user: 'admin', limit: 10 });
```

## Activity Types

| Type | Description |
|------|-------------|
| `login` | User logged in |
| `logout` | User logged out |
| `config_change` | Configuration changed |
| `input_change` | Input value changed |
| `save` | Data saved |
| `load` | Data loaded |
| `error` | Error occurred |
| `warning` | Warning issued |
| `info` | Informational event |

## Log Rotation

Activity logs are rotated daily. Each day's activities are stored in a separate file:

- `activities_2026-02-19.jsonl`
- `activities_2026-02-20.jsonl`
- etc.

To clean up old logs, set up a cron job or use logrotate.

## Security Considerations

- The admin API runs on a separate port from the main gateway
- Consider using a reverse proxy with authentication for the admin port
- Activity logs may contain sensitive information - secure the log directory
- The dashboard is read-only and doesn't allow modifying activities

## Troubleshooting

### Dashboard not accessible

1. Check if the admin API is running:
   ```bash
   docker exec <container> ps aux | grep api_server
   ```

2. Check the admin API logs:
   ```bash
   docker logs <container> | grep admin-api
   ```

3. Verify the port is exposed:
   ```bash
   docker exec <container> netstat -tlnp | grep 8888
   ```

### Activities not being logged

1. Check if activity logging is enabled:
   ```bash
   docker exec <container> echo $ACTIVITY_LOG_ENABLED
   ```

2. Verify the log directory exists and is writable:
   ```bash
   docker exec <container> ls -la /data/.zeroclaw/activity
   ```

3. Check the activity log files:
   ```bash
   docker exec <container> cat /data/.zeroclaw/activity/activities_$(date +%Y-%m-%d).jsonl
   ```
