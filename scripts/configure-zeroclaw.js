#!/usr/bin/env node
// =============================================================================
// ZeroClaw Configuration Builder
// =============================================================================
// Generates ZeroClaw config from environment variables
// Output: ~/.zeroclaw/config.toml (Rust TOML format)
// See: https://github.com/zeroclaw-labs/zeroclaw/blob/main/dev/config.template.toml
// =============================================================================

function buildConfig(STATE_DIR, WORKSPACE_DIR, parseList, PROVIDER_URLS, PROVIDER_MODELS) {
    const primaryModel = process.env.OPENCLAW_PRIMARY_MODEL || 'zhipu/glm-4.7';
    const parts = primaryModel.split('/');
    const provider = parts.length > 1 ? parts[0] : 'zhipu';
    const model = parts.length > 1 ? parts.slice(1).join('/') : primaryModel;

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

module.exports = { buildConfig };
