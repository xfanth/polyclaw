#!/usr/bin/env node
// =============================================================================
// OpenClaw Configuration Generator
// =============================================================================
// Generates openclaw.json from environment variables
// =============================================================================

const fs = require('fs');
const path = require('path');

const STATE_DIR = (process.env.OPENCLAW_STATE_DIR || '/data/.openclaw').replace(/\/+$/, '');
const WORKSPACE_DIR = (process.env.OPENCLAW_WORKSPACE_DIR || '/data/workspace').replace(/\/+$/, '');
const CONFIG_FILE = process.env.OPENCLAW_CONFIG_PATH || path.join(STATE_DIR, 'openclaw.json');

console.log('[configure] state dir:', STATE_DIR);
console.log('[configure] workspace dir:', WORKSPACE_DIR);

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
// Models are objects with id field
const PROVIDER_MODELS = {
    anthropic: [{ id: 'claude-sonnet-4-5-20250929' }],
    openai: [{ id: 'gpt-4o' }],
    openrouter: [{ id: 'anthropic/claude-sonnet-4-5' }],
    gemini: [{ id: 'gemini-2.5-pro' }],
    groq: [{ id: 'llama-3.1-70b-versatile' }],
    cerebras: [{ id: 'llama-3.1-70b' }],
    kimi: [{ id: 'kimi-k2.5' }],
    zai: [{ id: 'glm-4.7' }],
    opencode: [{ id: 'kimi-k2.5' }],
    copilot: [{ id: 'gpt-4o' }],
};

function buildConfig() {
    const config = {
        agents: {
            defaults: {
                workspace: WORKSPACE_DIR
            }
        }
    };

    // Primary model
    if (process.env.OPENCLAW_PRIMARY_MODEL) {
        config.agents.defaults.model = {
            primary: process.env.OPENCLAW_PRIMARY_MODEL
        };
    }

    // Providers
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

    // Gateway
    if (process.env.OPENCLAW_GATEWAY_TOKEN) {
        config.gateway = {
            auth: { token: process.env.OPENCLAW_GATEWAY_TOKEN }
        };
    }
    if (process.env.OPENCLAW_GATEWAY_BIND) {
        config.gateway = config.gateway || {};
        config.gateway.bind = process.env.OPENCLAW_GATEWAY_BIND;
    }

    // Browser - at root level, not under tools
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

    // Channels
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

    // Hooks
    if (process.env.HOOKS_ENABLED === 'true') {
        config.hooks = {
            enabled: true,
            token: process.env.HOOKS_TOKEN,
            path: process.env.HOOKS_PATH || '/hooks'
        };
    }

    return config;
}

const config = buildConfig();

const configJson = JSON.stringify(config, null, 2);
fs.writeFileSync(CONFIG_FILE, configJson, 'utf8');
console.log('[configure] wrote config to', CONFIG_FILE);

// Backup
const backupFile = path.join(STATE_DIR, 'openclaw.json.backup');
fs.writeFileSync(backupFile, configJson, 'utf8');

try {
    fs.chmodSync(CONFIG_FILE, 0o600);
    fs.chmodSync(backupFile, 0o600);
} catch (e) {
    // Ignore permission errors
}

console.log('[configure] configuration complete');
