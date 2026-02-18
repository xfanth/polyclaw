#!/usr/bin/env node
// =============================================================================
// IronClaw Configuration Builder
// =============================================================================
// IronClaw uses TOML config (settings.toml) and requires PostgreSQL
// Configuration is handled via `ironclaw onboard` command
// This module returns empty config - no file is written
// =============================================================================

function buildConfig(STATE_DIR, WORKSPACE_DIR, parseList, PROVIDER_URLS, PROVIDER_MODELS) {
    console.log('[configure] IronClaw uses TOML config and PostgreSQL - skipping JSON config generation');
    console.log('[configure] IronClaw should be configured via: ironclaw onboard');
    return {};
}

module.exports = { buildConfig };
