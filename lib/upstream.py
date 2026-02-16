"""
Upstream configuration module for OpenClaw Docker.

This module provides configuration and validation for different upstream
sources (openclaw, picoclaw, ironclaw).
"""

from dataclasses import dataclass
from enum import Enum
from typing import Self


class UpstreamType(str, Enum):
    """Supported upstream types."""

    OPENCLAW = "openclaw"
    PICOCLAW = "picoclaw"
    IRONCLAW = "ironclaw"

    @classmethod
    def from_string(cls, value: str) -> Self:
        """Parse upstream type from string."""
        normalized = value.lower().strip()
        for upstream in cls:
            if upstream.value == normalized:
                return upstream
        valid = ", ".join(u.value for u in cls)
        raise ValueError(f"Invalid upstream '{value}'. Valid options: {valid}")


@dataclass(frozen=True)
class UpstreamConfig:
    """Configuration for an upstream source."""

    name: UpstreamType
    github_owner: str
    github_repo: str
    default_branch: str
    description: str
    cli_name: str
    app_directory: str
    mjs_entrypoint: str

    @property
    def github_url(self) -> str:
        """Full GitHub URL for the upstream."""
        return f"https://github.com/{self.github_owner}/{self.github_repo}"

    @property
    def clone_url(self) -> str:
        """Git clone URL for the upstream."""
        return f"{self.github_url}.git"

    def get_clone_command(self, version: str, target_dir: str = ".") -> str:
        """Generate git clone command for this upstream."""
        branch = version if version not in ("main", "latest") else self.default_branch
        return f"git clone --depth 1 --branch {branch} {self.clone_url} {target_dir}"

    def should_patch_workspace(self) -> bool:
        """Check if workspace dependencies need patching."""
        return self.name == UpstreamType.OPENCLAW


UPSTREAMS: dict[UpstreamType, UpstreamConfig] = {
    UpstreamType.OPENCLAW: UpstreamConfig(
        name=UpstreamType.OPENCLAW,
        github_owner="openclaw",
        github_repo="openclaw",
        default_branch="main",
        description="Official OpenClaw - self-hosted AI agent gateway",
        cli_name="openclaw",
        app_directory="/opt/openclaw/app",
        mjs_entrypoint="openclaw.mjs",
    ),
    UpstreamType.PICOCLAW: UpstreamConfig(
        name=UpstreamType.PICOCLAW,
        github_owner="sipeed",
        github_repo="picoclaw",
        default_branch="main",
        description="PicoClaw by Sipeed - lightweight AI agent gateway",
        cli_name="picoclaw",
        app_directory="/opt/picoclaw/app",
        mjs_entrypoint="picoclaw.mjs",
    ),
    UpstreamType.IRONCLAW: UpstreamConfig(
        name=UpstreamType.IRONCLAW,
        github_owner="nearai",
        github_repo="ironclaw",
        default_branch="main",
        description="IronClaw by NEAR AI - AI agent gateway",
        cli_name="ironclaw",
        app_directory="/opt/ironclaw/app",
        mjs_entrypoint="ironclaw.mjs",
    ),
}


def get_upstream(upstream_type: UpstreamType | str) -> UpstreamConfig:
    """Get upstream configuration by type."""
    if isinstance(upstream_type, str):
        upstream_type = UpstreamType.from_string(upstream_type)
    if upstream_type not in UPSTREAMS:
        raise ValueError(f"Unknown upstream: {upstream_type}")
    return UPSTREAMS[upstream_type]


def get_all_upstreams() -> list[UpstreamConfig]:
    """Get all supported upstream configurations."""
    return list(UPSTREAMS.values())


def validate_version_format(version: str) -> bool:
    """Validate version string format."""
    if not version:
        return False
    valid_prefixes = ("v", "main", "latest", "oc_", "pc_", "ic_")
    return version.startswith(valid_prefixes) or version.replace(".", "").isdigit()


def get_dockerfile_build_args(
    upstream: UpstreamType | str,
    version: str = "main",
) -> dict[str, str]:
    """Generate Dockerfile build arguments for given upstream and version."""
    config = get_upstream(upstream)
    normalized_version = _normalize_version(version, config)
    return {
        "UPSTREAM": config.name.value,
        "UPSTREAM_VERSION": normalized_version,
        "GITHUB_OWNER": config.github_owner,
        "GITHUB_REPO": config.github_repo,
        "CLI_NAME": config.cli_name,
        "APP_DIR": config.app_directory,
    }


def _normalize_version(version: str, config: UpstreamConfig) -> str:
    """Normalize version string based on upstream type."""
    if version in ("main", "latest"):
        return config.default_branch
    if version.startswith(f"{config.name.value}_"):
        return config.default_branch
    return version


def generate_dockerfile_clone_block(
    upstream: UpstreamType | str,
    version: str = "main",
) -> str:
    """Generate the Dockerfile RUN block for cloning the upstream repository."""
    config = get_upstream(upstream)
    normalized_version = _normalize_version(version, config)

    if normalized_version == config.default_branch:
        clone_cmd = config.get_clone_command(config.default_branch)
    else:
        clone_cmd = config.get_clone_command(normalized_version)

    return f"""# Clone {config.name.value} repository
WORKDIR /build
ARG UPSTREAM_VERSION={normalized_version}
RUN {clone_cmd}"""
