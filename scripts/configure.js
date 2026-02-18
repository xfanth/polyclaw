#!/usr/bin/env node
// =============================================================================
// OpenClaw Configuration Generator
// =============================================================================
// Generates config from environment variables for all upstream types
// - OpenClaw: ~/.openclaw/openclaw.json (Node.js JSON format)
// - PicoClaw: ~/.picoclaw/config.json (Go JSON format)
// - ZeroClaw: ~/.zeroclaw/config.toml (Rust TOML format)
// - IronClaw: No config file (uses PostgreSQL, configured via `ironclaw onboard`)
// =============================================================================

const fs = require('fs');
const path = require('path');

const UPSTREAM = process.env.UPSTREAM || 'openclaw';
const STATE_DIR = (process.env.OPENCLAW_STATE_DIR || `/data/.${UPSTREAM}`).replace(/\/+$/, '');
const WORKSPACE_DIR = (process.env.OPENCLAW_WORKSPACE_DIR || '/data/workspace').replace(/\/+$/, '');

// Config file path differs by upstream type:
// - OpenClaw uses OPENCLAW_CONFIG_PATH or STATE_DIR/openclaw.json
// - PicoClaw uses ~/.picoclaw/config.json (JSON format)
// - ZeroClaw uses ~/.zeroclaw/config.toml (TOML format!)
// - IronClaw uses ~/.ironclaw/settings.toml (TOML + PostgreSQL, no JSON config)
let CONFIG_FILE;
let CONFIG_FORMAT = 'json';

if (UPSTREAM === 'openclaw') {
    CONFIG_FILE = process.env.OPENCLAW_CONFIG_PATH || path.join(STATE_DIR, `${UPSTREAM}.json`);
    CONFIG_FORMAT = 'json';
} else if (UPSTREAM === 'ironclaw') {
    // IronClaw doesn't use JSON config - it requires TOML and PostgreSQL
    // Config is handled via `ironclaw onboard`
    CONFIG_FILE = null;
    CONFIG_FORMAT = 'none';
} else if (UPSTREAM === 'zeroclaw') {
    // ZeroClaw expects TOML config at ~/.zeroclaw/config.toml
    // STATE_DIR is /data/.zeroclaw, so config is directly in STATE_DIR
    fs.mkdirSync(STATE_DIR, { recursive: true });
    CONFIG_FILE = path.join(STATE_DIR, 'config.toml');
    CONFIG_FORMAT = 'toml';
} else {
    // PicoClaw and other Go binaries use JSON
    const nestedDir = path.join(STATE_DIR, `.${UPSTREAM}`);
    fs.mkdirSync(nestedDir, { recursive: true });
    CONFIG_FILE = path.join(nestedDir, 'config.json');
    CONFIG_FORMAT = 'json';
}

console.log('[configure] upstream:', UPSTREAM);
console.log('[configure] state dir:', STATE_DIR);
console.log('[configure] workspace dir:', WORKSPACE_DIR);
console.log('[configure] config file:', CONFIG_FILE);

fs.mkdirSync(STATE_DIR, { recursive: true });
fs.mkdirSync(WORKSPACE_DIR, { recursive: true });

function parseList(value) {
    if (!value) return [];
    return value.split(',').map(s => s.trim()).filter(s => s);
}

// Provider base URLs
const PROVIDER_URLS = {
    anthropic: 'https://api.anthropic.com',
    openai: 'https://api.openai.com',
    openrouter: 'https://openrouter.ai/api',
    gemini: 'https://generativelanguage.googleapis.com',
    xai: 'https://api.x.ai',
    groq: 'https://api.groq.com/openai',
    mistral: 'https://api.mistral.ai',
    cerebras: 'https://api.cerebras.ai',
    moonshot: 'https://api.moonshot.cn',
    kimi: 'https://api.moonshot.cn',
    zai: 'https://api.z.ai',
    opencode: 'https://api.opencode.ai',
    copilot: 'https://api.githubcopilot.com',
};

// Default models per provider
const PROVIDER_MODELS = {
    anthropic: [{ id: 'claude-sonnet-4-5-20250929', name: 'claude-sonnet-4-5-20250929' }],
    openai: [{ id: 'gpt-4o', name: 'gpt-4o' }],
    openrouter: [{ id: 'anthropic/claude-sonnet-4-5', name: 'anthropic/claude-sonnet-4-5' }],
    gemini: [{ id: 'gemini-2.5-pro', name: 'gemini-2.5-pro' }],
    groq: [{ id: 'llama-3.1-70b-versatile', name: 'llama-3.1-70b-versatile' }],
    cerebras: [{ id: 'llama-3.1-70b', name: 'llama-3.1-70b' }],
    kimi: [{ id: 'kimi-k2.5', name: 'kimi-k2.5' }],
    zai: [{ id: 'glm-4.7', name: 'glm-4.7' }],
    opencode: [{ id: 'kimi-k2.5', name: 'kimi-k2.5' }],
    copilot: [{ id: 'gpt-4o', name: 'gpt-4o' }],
};

function buildOpenClawConfig() {
    const config = {
        agents: {
            defaults: {
                workspace: WORKSPACE_DIR
            }
        }
    };

    if (process.env.OPENCLAW_PRIMARY_MODEL) {
        config.agents.defaults.model = {
            primary: process.env.OPENCLAW_PRIMARY_MODEL
        };
    }

    const providers = {};
    const providerKeys = {
        anthropic: process.env.ANTHROPIC_API_KEY,
        openai: process.env.OPENAI_API_KEY,
        openrouter: process.env.OPENROUTER_API_KEY,
        gemini: process.env.GEMINI_API_KEY,
        xai: process.env.XAI_API_KEY,
        groq: process.env.GROQ_API_KEY,
        mistral: process.env.MISTRAL_API_KEY,
        cerebras: process.env.CEREBRAS_API_KEY,
        moonshot: process.env.MOONSHOT_API_KEY,
        kimi: process.env.KIMI_API_KEY,
        zai: process.env.ZAI_API_KEY,
        opencode: process.env.OPENCODE_API_KEY,
        copilot: process.env.COPILOT_GITHUB_TOKEN,
        xiaomi: process.env.XIAOMI_API_KEY,
    };

    for (const [name, apiKey] of Object.entries(providerKeys)) {
        if (apiKey) {
            providers[name] = {
                apiKey,
                baseUrl: PROVIDER_URLS[name] || '',
                models: PROVIDER_MODELS[name] || []
            };
        }
    }

    if (Object.keys(providers).length > 0) {
        config.models = { providers };
    }

    config.gateway = {
        mode: 'local'
    };
    if (process.env.OPENCLAW_GATEWAY_TOKEN) {
        config.gateway.auth = { token: process.env.OPENCLAW_GATEWAY_TOKEN };
    }
    if (process.env.OPENCLAW_GATEWAY_BIND) {
        config.gateway.bind = process.env.OPENCLAW_GATEWAY_BIND;
    }

    config.gateway.controlUi = {};

    const allowedOriginsValue = process.env.OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS || '';
    if (allowedOriginsValue && allowedOriginsValue !== '*') {
        config.gateway.controlUi.allowedOrigins = parseList(allowedOriginsValue);
    } else if (allowedOriginsValue === '*') {
        console.log('[configure] WARNING: OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS=* does not work as a wildcard in openclaw.');
        console.log('[configure] Specify exact origins like: http://hostname:port,http://otherhost:port');
    }

    if (process.env.OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH === 'true') {
        config.gateway.controlUi.allowInsecureAuth = true;
    }

    if (process.env.BROWSER_CDP_URL) {
        config.browser = {
            enabled: true,
            defaultProfile: process.env.BROWSER_DEFAULT_PROFILE || 'remote',
            profiles: {
                remote: {
                    cdpUrl: process.env.BROWSER_CDP_URL,
                    color: '#FF4500'
                }
            }
        };
    }

    if (process.env.WHATSAPP_ENABLED === 'true' || process.env.WHATSAPP_DM_POLICY) {
        config.channels = config.channels || {};
        config.channels.whatsapp = {
            dmPolicy: process.env.WHATSAPP_DM_POLICY || 'pairing'
        };
        if (process.env.WHATSAPP_ALLOW_FROM) {
            config.channels.whatsapp.allowFrom = parseList(process.env.WHATSAPP_ALLOW_FROM);
        }
    }

    if (process.env.TELEGRAM_BOT_TOKEN) {
        config.channels = config.channels || {};
        config.channels.telegram = {
            botToken: process.env.TELEGRAM_BOT_TOKEN,
            dmPolicy: process.env.TELEGRAM_DM_POLICY || 'pairing'
        };
    }

    if (process.env.DISCORD_BOT_TOKEN) {
        config.channels = config.channels || {};
        config.channels.discord = {
            botToken: process.env.DISCORD_BOT_TOKEN,
            dmPolicy: process.env.DISCORD_DM_POLICY || 'pairing'
        };
    }

    if (process.env.SLACK_BOT_TOKEN) {
        config.channels = config.channels || {};
        config.channels.slack = {
            botToken: process.env.SLACK_BOT_TOKEN,
            dmPolicy: process.env.SLACK_DM_POLICY || 'pairing'
        };
    }

    if (process.env.HOOKS_ENABLED === 'true') {
        config.hooks = {
            enabled: true,
            token: process.env.HOOKS_TOKEN,
            path: process.env.HOOKS_PATH || '/hooks'
        };
    }

    return config;
}

function buildPicoClawConfig() {
    // PicoClaw config format (Go)
    // See: https://github.com/sipeed/picoclaw
    const primaryModel = process.env.OPENCLAW_PRIMARY_MODEL || 'glm-4.7';
    const provider = primaryModel.includes('/') ? primaryModel.split('/')[0] : 'zhipu';
    const model = primaryModel.includes('/') ? primaryModel.split('/')[1] : primaryModel;

    const config = {
        agents: {
            defaults: {
                workspace: `${STATE_DIR}/workspace`,
                restrict_to_workspace: true,
                model: model,
                max_tokens: 8192,
                temperature: 0.7,
                max_tool_iterations: 20
            }
        },
        providers: {},
        gateway: {
            host: '127.0.0.1',
            port: 18789
        },
        tools: {
            web: {
                brave: {
                    enabled: false,
                    api_key: '',
                    max_results: 5
                },
                duckduckgo: {
                    enabled: true,
                    max_results: 5
                }
            },
            cron: {
                exec_timeout_minutes: 5
            }
        },
        heartbeat: {
            enabled: true,
            interval: 30
        },
        channels: {}
    };

    // Map API keys to PicoClaw provider format
    const providerKeys = {
        openrouter: process.env.OPENROUTER_API_KEY,
        anthropic: process.env.ANTHROPIC_API_KEY,
        openai: process.env.OPENAI_API_KEY,
        gemini: process.env.GEMINI_API_KEY,
        zhipu: process.env.ZAI_API_KEY,
        groq: process.env.GROQ_API_KEY,
    };

    for (const [name, apiKey] of Object.entries(providerKeys)) {
        if (apiKey) {
            config.providers[name] = {
                api_key: apiKey
            };
            if (PROVIDER_URLS[name]) {
                config.providers[name].api_base = PROVIDER_URLS[name];
            }
        }
    }

    if (process.env.TELEGRAM_BOT_TOKEN) {
        config.channels.telegram = {
            enabled: true,
            token: process.env.TELEGRAM_BOT_TOKEN,
            allow_from: []
        };
    }

    if (process.env.DISCORD_BOT_TOKEN) {
        config.channels.discord = {
            enabled: true,
            token: process.env.DISCORD_BOT_TOKEN,
            allow_from: []
        };
    }

    return config;
}

function buildZeroClawConfig() {
    // ZeroClaw config format (Rust) - uses TOML
    // See: https://github.com/zeroclaw-labs/zeroclaw/blob/main/dev/config.template.toml
    // ZeroClaw uses a flat config structure with top-level fields
    const primaryModel = process.env.OPENCLAW_PRIMARY_MODEL || 'zhipu/glm-4.7';
    const parts = primaryModel.split('/');
    const provider = parts.length > 1 ? parts[0] : 'zhipu';
    const model = parts.length > 1 ? parts.slice(1).join('/') : primaryModel;

    // Find the first available API key
    const providerKeys = {
        openrouter: process.env.OPENROUTER_API_KEY,
        anthropic: process.env.ANTHROPIC_API_KEY,
        openai: process.env.OPENAI_API_KEY,
        gemini: process.env.GEMINI_API_KEY,
        zhipu: process.env.ZAI_API_KEY,
        groq: process.env.GROQ_API_KEY,
    };

    let apiKey = '';
    let defaultProvider = provider;
    for (const [name, key] of Object.entries(providerKeys)) {
        if (key) {
            apiKey = key;
            if (provider === name || !providerKeys[provider]) {
                defaultProvider = name;
            }
            break;
        }
    }

    const gatewayPort = parseInt(process.env.OPENCLAW_GATEWAY_PORT || '18789', 10);
    const gatewayHost = process.env.ZEROCLAW_GATEWAY_HOST || '127.0.0.1';

    const config = {
        workspace_dir: `${STATE_DIR}/workspace`,
        // ZeroClaw expects config at ~/.zeroclaw/config.toml, and STATE_DIR is /data/.zeroclaw
        // So the config path is just ${STATE_DIR}/config.toml (not ${STATE_DIR}/.zeroclaw/config.toml)
        config_path: `${STATE_DIR}/config.toml`,
        api_key: apiKey,
        default_provider: defaultProvider,
        default_model: model,
        default_temperature: 0.7,
        gateway: {
            port: gatewayPort,
            host: gatewayHost,
            allow_public_bind: false
        }
    };

    return config;
}

function toTomlValue(value) {
    if (value === null || value === undefined) {
        return '';
    }
    if (typeof value === 'string') {
        const escaped = value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
        return `"${escaped}"`;
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
        return String(value);
    }
    if (Array.isArray(value)) {
        if (value.length === 0) return '[]';
        const items = value.map(v => toTomlValue(v));
        return '[' + items.join(', ') + ']';
    }
    return '';
}

function writeTomlSection(obj, prefix, output) {
    const nestedObjects = [];
    const simpleValues = [];

    for (const [key, value] of Object.entries(obj)) {
        if (value === null || value === undefined) continue;
        if (typeof value === 'object' && !Array.isArray(value)) {
            nestedObjects.push([key, value]);
        } else {
            simpleValues.push([key, value]);
        }
    }

    // Write section header if this is a nested object and it has values
    if (prefix && (simpleValues.length > 0 || nestedObjects.length > 0)) {
        output.push(`[${prefix}]`);
    }

    // Write simple values
    for (const [key, value] of simpleValues) {
        const tomlValue = toTomlValue(value);
        if (tomlValue !== '') {
            output.push(`${key} = ${tomlValue}`);
        }
    }

    // Add blank line after values if we have nested objects
    if (simpleValues.length > 0 && nestedObjects.length > 0) {
        output.push('');
    }

    // Recursively handle nested objects
    for (const [key, value] of nestedObjects) {
        const nestedPrefix = prefix ? `${prefix}.${key}` : key;
        writeTomlSection(value, nestedPrefix, output);
    }
}

function jsonToToml(config) {
    const output = [
        '# ZeroClaw Configuration',
        '# Generated by Docker entrypoint',
        ''
    ];

    // Collect top-level nested objects
    const topLevelSections = [];
    const topLevelValues = [];

    for (const [key, value] of Object.entries(config)) {
        if (value === null || value === undefined) continue;
        if (typeof value === 'object' && !Array.isArray(value)) {
            topLevelSections.push([key, value]);
        } else {
            topLevelValues.push([key, value]);
        }
    }

    // Write top-level simple values
    for (const [key, value] of topLevelValues) {
        const tomlValue = toTomlValue(value);
        if (tomlValue !== '') {
            output.push(`${key} = ${tomlValue}`);
        }
    }

    if (topLevelValues.length > 0 && topLevelSections.length > 0) {
        output.push('');
    }

    // Write nested sections
    for (const [key, value] of topLevelSections) {
        writeTomlSection(value, key, output);
        output.push('');
    }

    return output.join('\n');
}

function buildIronClawConfig() {
    // IronClaw uses TOML config (settings.toml) and requires PostgreSQL
    // It cannot use JSON config. Return empty object - IronClaw handles its own config via `ironclaw onboard`
    console.log('[configure] IronClaw uses TOML config and PostgreSQL - skipping JSON config generation');
    console.log('[configure] IronClaw should be configured via: ironclaw onboard');
    return {};
}

function buildConfig() {
    switch (UPSTREAM) {
        case 'openclaw':
            return buildOpenClawConfig();
        case 'picoclaw':
            return buildPicoClawConfig();
        case 'zeroclaw':
            return buildZeroClawConfig();
        case 'ironclaw':
            return buildIronClawConfig();
        default:
            console.log(`[configure] Unknown upstream ${UPSTREAM}, using OpenClaw format`);
            return buildOpenClawConfig();
    }
}

const config = buildConfig();

// Skip config file writing for upstreams that don't use JSON/TOML config
if (CONFIG_FILE === null) {
    console.log('[configure] No config file needed for', UPSTREAM);
    console.log('[configure] configuration complete');
    process.exit(0);
}

let configContent;
let configFormat;
if (CONFIG_FORMAT === 'toml') {
    configContent = jsonToToml(config);
    configFormat = 'TOML';
} else {
    configContent = JSON.stringify(config, null, 2);
    configFormat = 'JSON';
}

fs.writeFileSync(CONFIG_FILE, configContent, 'utf8');
console.log(`[configure] wrote ${configFormat} config to`, CONFIG_FILE);

// Backup (use same format as config)
const backupExt = CONFIG_FORMAT === 'toml' ? 'toml' : 'json';
const backupFile = path.join(STATE_DIR, `${UPSTREAM}.${backupExt}.backup`);
fs.writeFileSync(backupFile, configContent, 'utf8');

try {
    fs.chmodSync(CONFIG_FILE, 0o600);
    fs.chmodSync(backupFile, 0o600);
} catch (e) {
    // Ignore permission errors
}

console.log('[configure] configuration complete');
