/**
 * Activity Logging Module (Node.js)
 * 
 * Tracks user activities with details and timestamps.
 * Stores activities in JSON format for easy parsing and querying.
 */

const fs = require('fs');
const path = require('path');

const ACTIVITY_TYPES = {
  login: 'User logged in',
  logout: 'User logged out',
  config_change: 'Configuration changed',
  input_change: 'Input value changed',
  save: 'Data saved',
  load: 'Data loaded',
  error: 'Error occurred',
  warning: 'Warning issued',
  info: 'Informational event',
};

class ActivityLogger {
  constructor(logDir = null) {
    this.logDir = logDir || process.env.ACTIVITY_LOG_DIR || '/data/.openclaw/activity';
    
    // Ensure directory exists
    if (!fs.existsSync(this.logDir)) {
      fs.mkdirSync(this.logDir, { recursive: true });
    }
    
    const date = new Date().toISOString().split('T')[0];
    this.currentLogFile = path.join(this.logDir, `activities_${date}.jsonl`);
    this.enabled = (process.env.ACTIVITY_LOG_ENABLED || 'true').toLowerCase() === 'true';
  }

  /**
   * Log a user activity
   * @param {string} user - The user who performed the activity
   * @param {string} activityType - Type of activity
   * @param {object} details - Additional details
   * @param {string} source - Source of the activity (web, cli, api, system)
   * @returns {object} The logged activity entry
   */
  log(user, activityType, details = {}, source = 'system') {
    if (!this.enabled) {
      return {};
    }

    const activity = {
      timestamp: new Date().toISOString(),
      user,
      activity: activityType,
      description: ACTIVITY_TYPES[activityType] || activityType,
      source,
      details,
    };

    // Append to JSONL file
    fs.appendFileSync(this.currentLogFile, JSON.stringify(activity) + '\n');

    return activity;
  }

  /**
   * Retrieve activities with optional filtering
   * @param {object} filters - Filter options
   * @returns {Array} List of activity entries
   */
  getActivities(filters = {}) {
    const { user, activityType, startTime, endTime, limit = 100, offset = 0 } = filters;
    const activities = [];

    // Read all log files
    const files = fs.readdirSync(this.logDir)
      .filter(f => f.startsWith('activities_') && f.endsWith('.jsonl'))
      .sort()
      .reverse();

    for (const file of files) {
      const filePath = path.join(this.logDir, file);
      const content = fs.readFileSync(filePath, 'utf8');
      const lines = content.split('\n').filter(line => line.trim());

      for (const line of lines) {
        try {
          const activity = JSON.parse(line);

          // Apply filters
          if (user && activity.user !== user) continue;
          if (activityType && activity.activity !== activityType) continue;
          if (startTime && activity.timestamp < startTime) continue;
          if (endTime && activity.timestamp > endTime) continue;

          activities.push(activity);
        } catch (e) {
          // Skip invalid JSON lines
        }
      }
    }

    // Sort by timestamp (newest first) and apply pagination
    activities.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
    return activities.slice(offset, offset + limit);
  }

  /**
   * Get activity statistics
   * @param {number} days - Number of days to analyze
   * @returns {object} Activity statistics
   */
  getActivityStats(days = 7) {
    const activities = this.getActivities({ limit: 10000 });
    
    const cutoff = Date.now() - (days * 24 * 60 * 60 * 1000);
    const recentActivities = activities.filter(a => 
      new Date(a.timestamp).getTime() > cutoff
    );

    const activityTypes = {};
    const users = {};

    for (const activity of recentActivities) {
      activityTypes[activity.activity] = (activityTypes[activity.activity] || 0) + 1;
      users[activity.user] = (users[activity.user] || 0) + 1;
    }

    // Get top activity type
    const topActivity = Object.entries(activityTypes)
      .sort((a, b) => b[1] - a[1])[0];

    return {
      total_activities: recentActivities.length,
      unique_users: Object.keys(users).length,
      activity_types: activityTypes,
      top_users: Object.entries(users)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 10)
        .reduce((obj, [key, val]) => { obj[key] = val; return obj; }, {}),
      period_days: days,
    };
  }
}

// Singleton instance
let loggerInstance = null;

function getLogger() {
  if (!loggerInstance) {
    loggerInstance = new ActivityLogger();
  }
  return loggerInstance;
}

// Convenience functions
function logLogin(user, source = 'web', details = {}) {
  return getLogger().log(user, 'login', details, source);
}

function logLogout(user, source = 'web') {
  return getLogger().log(user, 'logout', {}, source);
}

function logConfigChange(user, changes, source = 'web') {
  return getLogger().log(user, 'config_change', { changes }, source);
}

function logInputChange(user, field, oldValue, newValue, source = 'web') {
  return getLogger().log(user, 'input_change', { 
    field, 
    old_value: String(oldValue), 
    new_value: String(newValue) 
  }, source);
}

function logSave(user, item, source = 'web') {
  return getLogger().log(user, 'save', { item }, source);
}

function logLoad(user, item, source = 'web') {
  return getLogger().log(user, 'load', { item }, source);
}

function logError(user, error, details = {}, source = 'system') {
  return getLogger().log(user, 'error', { error, ...details }, source);
}

function logWarning(user, warning, details = {}, source = 'system') {
  return getLogger().log(user, 'warning', { warning, ...details }, source);
}

function logInfo(user, message, details = {}, source = 'system') {
  return getLogger().log(user, 'info', { message, ...details }, source);
}

module.exports = {
  ActivityLogger,
  getLogger,
  logLogin,
  logLogout,
  logConfigChange,
  logInputChange,
  logSave,
  logLoad,
  logError,
  logWarning,
  logInfo,
  ACTIVITY_TYPES,
};
