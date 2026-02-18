#!/usr/bin/env node
// =============================================================================
// PicoClaw Configuration Builder
// =============================================================================
// Generates PicoClaw config from environment variables
// Output: ~/.picoclaw/config.json (Go JSON format)
// See: https://github.com/sipeed/picoclaw
// =============================================================================

function buildConfig(STATE_DIR, WORKSPACE_DIR, parseList, PROVIDER_URLS, PROVIDER_MODELS) {
    const primaryModel = process.env.OPENCLAW_PRIMARY_MODEL || 'glm-4.7';
    const provider = primaryModel.includes('/') ? primaryModel.split('/')[0] : 'zhipu';
    const model = primaryModel.includes('/') ? primaryModel.split('/')[1] : primaryModel;
    const gatewayPort = parseInt(process.env.OPENCLAW_INTERNAL_GATEWAY_PORT || '18789', 10);

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
            port: gatewayPort
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

module.exports = { buildConfig };
