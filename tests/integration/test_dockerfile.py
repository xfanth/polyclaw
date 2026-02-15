"""Tests for Dockerfile generation with upstream support."""

import pytest

from lib.upstream import (
    UpstreamType,
    generate_dockerfile_clone_block,
    get_dockerfile_build_args,
    get_upstream,
)


class TestDockerfileGeneration:
    """Tests for Dockerfile generation functions."""

    def test_generate_clone_block_openclaw(self):
        result = generate_dockerfile_clone_block(UpstreamType.OPENCLAW, "main")
        assert "openclaw" in result.lower()
        assert "github.com/openclaw/openclaw" in result
        assert "git clone" in result

    def test_generate_clone_block_picoclaw(self):
        result = generate_dockerfile_clone_block(UpstreamType.PICOCLAW, "main")
        assert "picoclaw" in result.lower()
        assert "github.com/sipeed/picoclaw" in result
        assert "git clone" in result

    def test_generate_clone_block_with_version(self):
        result = generate_dockerfile_clone_block("openclaw", "v2026.2.1")
        assert "v2026.2.1" in result

    def test_dockerfile_build_args_structure(self):
        result = get_dockerfile_build_args(UpstreamType.OPENCLAW, "main")
        required_keys = [
            "UPSTREAM",
            "UPSTREAM_VERSION",
            "GITHUB_OWNER",
            "GITHUB_REPO",
            "CLI_NAME",
            "APP_DIR",
        ]
        for key in required_keys:
            assert key in result, f"Missing required key: {key}"

    def test_dockerfile_build_args_openclaw_values(self):
        result = get_dockerfile_build_args(UpstreamType.OPENCLAW, "v1.0.0")
        assert result["UPSTREAM"] == "openclaw"
        assert result["UPSTREAM_VERSION"] == "v1.0.0"
        assert result["GITHUB_OWNER"] == "openclaw"
        assert result["GITHUB_REPO"] == "openclaw"
        assert result["CLI_NAME"] == "openclaw"
        assert result["APP_DIR"] == "/opt/openclaw/app"

    def test_dockerfile_build_args_picoclaw_values(self):
        result = get_dockerfile_build_args(UpstreamType.PICOCLAW, "v1.0.0")
        assert result["UPSTREAM"] == "picoclaw"
        assert result["UPSTREAM_VERSION"] == "v1.0.0"
        assert result["GITHUB_OWNER"] == "sipeed"
        assert result["GITHUB_REPO"] == "picoclaw"
        assert result["CLI_NAME"] == "picoclaw"
        assert result["APP_DIR"] == "/opt/picoclaw/app"


class TestDockerfileValidation:
    """Tests for validating Dockerfile content."""

    @pytest.fixture
    def dockerfile_content(self):
        with open("Dockerfile") as f:
            return f.read()

    def test_dockerfile_has_upstream_arg(self, dockerfile_content):
        assert "ARG UPSTREAM=" in dockerfile_content or "ARG UPSTREAM" in dockerfile_content

    def test_dockerfile_has_version_arg(self, dockerfile_content):
        assert (
            "ARG UPSTREAM_VERSION" in dockerfile_content or "OPENCLAW_VERSION" in dockerfile_content
        )

    def test_dockerfile_uses_conditional_clone(self, dockerfile_content):
        assert "git clone" in dockerfile_content

    def test_dockerfile_has_openclaw_reference(self, dockerfile_content):
        assert "openclaw" in dockerfile_content.lower()

    def test_dockerfile_supports_picoclaw(self, dockerfile_content):
        assert "picoclaw" in dockerfile_content.lower() or "UPSTREAM" in dockerfile_content


class TestEnvExampleValidation:
    """Tests for validating .env.example content."""

    @pytest.fixture
    def env_example_content(self):
        with open(".env.example") as f:
            return f.read()

    def test_env_has_upstream_option(self, env_example_content):
        assert "UPSTREAM" in env_example_content

    def test_env_documents_openclaw(self, env_example_content):
        assert "openclaw" in env_example_content.lower()

    def test_env_documents_picoclaw(self, env_example_content):
        assert "picoclaw" in env_example_content.lower()

    def test_env_has_upstream_version_option(self, env_example_content):
        assert (
            "VERSION" in env_example_content.upper()
            or "UPSTREAM_VERSION" in env_example_content.upper()
        )


class TestDockerComposeValidation:
    """Tests for validating docker-compose.yml content."""

    @pytest.fixture
    def compose_content(self):
        with open("docker-compose.yml") as f:
            return f.read()

    def test_compose_has_upstream_env(self, compose_content):
        assert "UPSTREAM" in compose_content

    def test_compose_has_version_env(self, compose_content):
        assert "VERSION" in compose_content or "UPSTREAM_VERSION" in compose_content

    def test_compose_uses_env_var_for_image(self, compose_content):
        assert "${OPENCLAW_IMAGE" in compose_content or "${UPSTREAM_IMAGE" in compose_content
