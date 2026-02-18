#!/usr/bin/env node
// =============================================================================
// OpenClaw Configuration Builder
// =============================================================================
// Generates OpenClaw config from environment variables
// Output: ~/.openclaw/openclaw.json (Node.js JSON format)
// =============================================================================

function buildConfig(STATE_DIR, WORKSPACE_DIR, parseList, PROVIDER_URLS, PROVIDER_MODELS) {
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

module.exports = { buildConfig };
