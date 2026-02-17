# Security Policy

## Supported Versions

| Version | Supported |
| ------- | ------------------ |
| latest  | :white_check_mark: |
| main    | :white_check_mark: |
| < 2025  | :x:                |

## Security Features

This Docker image includes several security hardening measures:

- **Non-root user**: Container runs as UID/GID 10000 by default
- **Minimal capabilities**: Container drops all capabilities except those required
- **HTTP Basic Auth**: Web interface protected with username/password
- **Gateway token**: API access requires bearer token authentication
- **Nginx reverse proxy**: Provides security headers and rate limiting
- **No secrets in images**: All sensitive data provided via environment variables

## Reporting a Vulnerability

If you discover a security vulnerability, please report it by:

1. **Email**: Open a GitHub Security Advisory at https://github.com/xfanth/openclaw/security/advisories
2. **Response time**: Expect an initial response within 48 hours
3. **Disclosure**: We follow responsible disclosure - please do not publicly disclose until a fix is available

## Security Best Practices

When deploying this image:

1. **Always set `AUTH_PASSWORD`** for production deployments
2. **Use strong `OPENCLAW_GATEWAY_TOKEN`** (generate with `openssl rand -hex 32`)
3. **Keep API keys in `.env` file** - never commit them to version control
4. **Use HTTPS** in production (deploy behind a reverse proxy with SSL)
5. **Restrict channel allowlists** (WhatsApp, Telegram, Discord) to known contacts
6. **Regularly update** the Docker image for security patches
7. **Review logs** periodically for suspicious activity
8. **Use Docker secrets** or external secret management for sensitive values

## Known Security Considerations

- **Browser automation**: The optional browser sidecar runs Chrome with `--no-sandbox`. Only enable in trusted environments.
- **Bind mounts**: Data directories should have restricted permissions (owner-only access recommended)
- **Gateway token**: If compromised, regenerate immediately and update all connected clients
