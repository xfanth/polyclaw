#!/usr/bin/env python3
"""
Activity Logging Module

Tracks user activities with details and timestamps.
Stores activities in JSON format for easy parsing and querying.
"""

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Any


class ActivityLogger:
    """Logger for user activities."""

    ACTIVITY_TYPES = {
        "login": "User logged in",
        "logout": "User logged out",
        "config_change": "Configuration changed",
        "input_change": "Input value changed",
        "save": "Data saved",
        "load": "Data loaded",
        "error": "Error occurred",
        "warning": "Warning issued",
        "info": "Informational event",
    }

    def __init__(self, log_dir: str | None = None):
        """Initialize the activity logger.

        Args:
            log_dir: Directory to store activity logs. Defaults to /data/.openclaw/activity
        """
        self.log_dir = Path(
            log_dir or os.environ.get("ACTIVITY_LOG_DIR", "/data/.openclaw/activity")
        )
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.current_log_file = (
            self.log_dir / f"activities_{datetime.now().strftime('%Y-%m-%d')}.jsonl"
        )
        self.enabled = os.environ.get("ACTIVITY_LOG_ENABLED", "true").lower() == "true"

    def log(
        self,
        user: str,
        activity_type: str,
        details: dict[str, Any] | None = None,
        source: str = "system",
    ) -> dict[str, Any]:
        """Log a user activity.

        Args:
            user: The user who performed the activity
            activity_type: Type of activity (login, save, config_change, etc.)
            details: Additional details about the activity
            source: Source of the activity (web, cli, api, system)

        Returns:
            The logged activity entry
        """
        if not self.enabled:
            return {}

        activity = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "user": user,
            "activity": activity_type,
            "description": self.ACTIVITY_TYPES.get(activity_type, activity_type),
            "source": source,
            "details": details or {},
        }

        # Append to JSONL file
        with open(self.current_log_file, "a") as f:
            f.write(json.dumps(activity) + "\n")

        return activity

    def get_activities(
        self,
        user: str | None = None,
        activity_type: str | None = None,
        start_time: str | None = None,
        end_time: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
        """Retrieve activities with optional filtering.

        Args:
            user: Filter by username
            activity_type: Filter by activity type
            start_time: Filter activities after this time (ISO format)
            end_time: Filter activities before this time (ISO format)
            limit: Maximum number of activities to return
            offset: Number of activities to skip

        Returns:
            List of activity entries
        """
        activities = []

        # Read all log files
        log_files = sorted(self.log_dir.glob("activities_*.jsonl"), reverse=True)

        for log_file in log_files:
            if not log_file.exists():
                continue

            with open(log_file) as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue

                    try:
                        activity = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    # Apply filters
                    if user and activity.get("user") != user:
                        continue
                    if activity_type and activity.get("activity") != activity_type:
                        continue
                    if start_time and activity.get("timestamp", "") < start_time:
                        continue
                    if end_time and activity.get("timestamp", "") > end_time:
                        continue

                    activities.append(activity)

        # Sort by timestamp (newest first) and apply pagination
        activities.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
        return activities[offset : offset + limit]

    def get_activity_stats(self, days: int = 7) -> dict[str, Any]:
        """Get activity statistics for the specified number of days.

        Args:
            days: Number of days to analyze

        Returns:
            Dictionary with activity statistics
        """
        from collections import Counter

        activities = self.get_activities(limit=10000)

        # Filter to specified days
        cutoff = datetime.utcnow().timestamp() - (days * 24 * 60 * 60)
        recent_activities = [
            a
            for a in activities
            if datetime.fromisoformat(a["timestamp"].replace("Z", "+00:00")).timestamp() > cutoff
        ]

        stats = {
            "total_activities": len(recent_activities),
            "unique_users": len(set(a["user"] for a in recent_activities)),
            "activity_types": dict(Counter(a["activity"] for a in recent_activities)),
            "top_users": dict(Counter(a["user"] for a in recent_activities).most_common(10)),
            "period_days": days,
        }

        return stats


def get_logger() -> ActivityLogger:
    """Get the singleton activity logger instance."""
    if not hasattr(get_logger, "_instance"):
        get_logger._instance = ActivityLogger()
    return get_logger._instance


# Convenience functions for common activities
def log_login(user: str, source: str = "web", details: dict | None = None) -> dict:
    """Log a user login."""
    return get_logger().log(user, "login", details, source)


def log_logout(user: str, source: str = "web") -> dict:
    """Log a user logout."""
    return get_logger().log(user, "logout", {}, source)


def log_config_change(user: str, changes: dict, source: str = "web") -> dict:
    """Log configuration changes."""
    return get_logger().log(user, "config_change", {"changes": changes}, source)


def log_input_change(
    user: str, field: str, old_value: Any, new_value: Any, source: str = "web"
) -> dict:
    """Log an input field change."""
    return get_logger().log(
        user,
        "input_change",
        {"field": field, "old_value": str(old_value), "new_value": str(new_value)},
        source,
    )


def log_save(user: str, item: str, source: str = "web") -> dict:
    """Log a save operation."""
    return get_logger().log(user, "save", {"item": item}, source)


def log_load(user: str, item: str, source: str = "web") -> dict:
    """Log a load operation."""
    return get_logger().log(user, "load", {"item": item}, source)


def log_error(user: str, error: str, details: dict | None = None, source: str = "system") -> dict:
    """Log an error."""
    return get_logger().log(user, "error", {"error": error, **(details or {})}, source)


def log_warning(
    user: str, warning: str, details: dict | None = None, source: str = "system"
) -> dict:
    """Log a warning."""
    return get_logger().log(user, "warning", {"warning": warning, **(details or {})}, source)


def log_info(user: str, message: str, details: dict | None = None, source: str = "system") -> dict:
    """Log an informational message."""
    return get_logger().log(user, "info", {"message": message, **(details or {})}, source)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Activity Logger CLI")
    parser.add_argument("command", choices=["list", "stats", "log"])
    parser.add_argument("--user", help="Filter by user")
    parser.add_argument("--type", help="Filter by activity type")
    parser.add_argument("--limit", type=int, default=100, help="Limit results")
    parser.add_argument("--days", type=int, default=7, help="Days for stats")

    args = parser.parse_args()

    logger = get_logger()

    if args.command == "list":
        activities = logger.get_activities(
            user=args.user,
            activity_type=args.type,
            limit=args.limit,
        )
        print(json.dumps(activities, indent=2))
    elif args.command == "stats":
        stats = logger.get_activity_stats(days=args.days)
        print(json.dumps(stats, indent=2))
    elif args.command == "log":
        print(f"Activity log directory: {logger.log_dir}")
        print(f"Current log file: {logger.current_log_file}")
        print(f"Logging enabled: {logger.enabled}")
