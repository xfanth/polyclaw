#!/usr/bin/env node
// =============================================================================
// OpenClaw Configuration Generator
// =============================================================================
// Generates config from environment variables for all upstream types
// - OpenClaw: ~/.openclaw/openclaw.json (Node.js format)
// - PicoClaw: ~/.picoclaw/config.json (Go format)
// - ZeroClaw: ~/.zeroclaw/config.json (Rust format)
// - IronClaw: ~/.ironclaw/config.json (Rust format)
// =============================================================================

const fs = require('fs');
const path = require('path');

const UPSTREAM = process.env.UPSTREAM || 'openclaw';
const STATE_DIR = (process.env.OPENCLAW_STATE_DIR || `/data/.${UPSTREAM}`).replace(/\/+$/, '');
const WORKSPACE_DIR = (process.env.OPENCLAW_WORKSPACE_DIR || '/data/workspace').replace(/\/+$/, '');

// Config file path differs by upstream type:
// - OpenClaw uses OPENCLAW_CONFIG_PATH or STATE_DIR/openclaw.json
// - PicoClaw/ZeroClaw/IronClaw use ~/.picoclaw/config.json pattern
//   But since we set HOME to STATE_DIR, they look for STATE_DIR/.picoclaw/config.json
//   So we need to create a nested directory structure or use config.json directly
let CONFIG_FILE;
if (UPSTREAM === 'openclaw') {
    CONFIG_FILE = process.env.OPENCLAW_CONFIG_PATH || path.join(STATE_DIR, `${UPSTREAM}.json`);
} else {
    // For Go/Rust binaries, they expect $HOME/.${UPSTREAM}/config.json
    // Since HOME is set to STATE_DIR in entrypoint, they look for STATE_DIR/.${UPSTREAM}/config.json
    // We create this nested structure
    const nestedDir = path.join(STATE_DIR, `.${UPSTREAM}`);
    fs.mkdirSync(nestedDir, { recursive: true });
    CONFIG_FILE = path.join(nestedDir, 'config.json');
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
    // ZeroClaw config format (Rust) - similar to PicoClaw
    return buildPicoClawConfig();
}

function buildIronClawConfig() {
    // IronClaw config format (Rust) - similar to PicoClaw
    return buildPicoClawConfig();
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

const configJson = JSON.stringify(config, null, 2);
fs.writeFileSync(CONFIG_FILE, configJson, 'utf8');
console.log('[configure] wrote config to', CONFIG_FILE);

// Backup
const backupFile = path.join(STATE_DIR, `${UPSTREAM}.json.backup`);
fs.writeFileSync(backupFile, configJson, 'utf8');

try {
    fs.chmodSync(CONFIG_FILE, 0o600);
    fs.chmodSync(backupFile, 0o600);
} catch (e) {
    // Ignore permission errors
}

console.log('[configure] configuration complete');
