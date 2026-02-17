"""Unit tests for upstream configuration module."""

import pytest

from lib.upstream import (
    UpstreamConfig,
    UpstreamType,
    UPSTREAMS,
    get_all_upstreams,
    get_dockerfile_build_args,
    get_upstream,
    validate_version_format,
)


class TestUpstreamType:
    """Tests for UpstreamType enum."""

    def test_openclaw_value(self):
        assert UpstreamType.OPENCLAW.value == "openclaw"

    def test_picoclaw_value(self):
        assert UpstreamType.PICOCLAW.value == "picoclaw"

    def test_zeroclaw_value(self):
        assert UpstreamType.ZEROCLAW.value == "zeroclaw"

    def test_from_string_openclaw(self):
        result = UpstreamType.from_string("openclaw")
        assert result == UpstreamType.OPENCLAW

    def test_from_string_picoclaw(self):
        result = UpstreamType.from_string("picoclaw")
        assert result == UpstreamType.PICOCLAW

    def test_from_string_zeroclaw(self):
        result = UpstreamType.from_string("zeroclaw")
        assert result == UpstreamType.ZEROCLAW

    def test_from_string_case_insensitive(self):
        assert UpstreamType.from_string("OPENCLAW") == UpstreamType.OPENCLAW
        assert UpstreamType.from_string("PicoClaw") == UpstreamType.PICOCLAW
        assert UpstreamType.from_string("ZEROCLAW") == UpstreamType.ZEROCLAW
        assert UpstreamType.from_string("  openclaw  ") == UpstreamType.OPENCLAW

    def test_from_string_invalid(self):
        with pytest.raises(ValueError, match="Invalid upstream"):
            UpstreamType.from_string("invalid")

    def test_from_string_empty(self):
        with pytest.raises(ValueError, match="Invalid upstream"):
            UpstreamType.from_string("")


class TestUpstreamConfig:
    """Tests for UpstreamConfig dataclass."""

    @pytest.fixture
    def openclaw_config(self):
        return UPSTREAMS[UpstreamType.OPENCLAW]

    @pytest.fixture
    def picoclaw_config(self):
        return UPSTREAMS[UpstreamType.PICOCLAW]

    @pytest.fixture
    def zeroclaw_config(self):
        return UPSTREAMS[UpstreamType.ZEROCLAW]

    def test_github_url_openclaw(self, openclaw_config):
        assert openclaw_config.github_url == "https://github.com/openclaw/openclaw"

    def test_github_url_picoclaw(self, picoclaw_config):
        assert picoclaw_config.github_url == "https://github.com/sipeed/picoclaw"

    def test_github_url_zeroclaw(self, zeroclaw_config):
        assert zeroclaw_config.github_url == "https://github.com/zeroclaw-labs/zeroclaw"

    def test_clone_url_openclaw(self, openclaw_config):
        assert openclaw_config.clone_url == "https://github.com/openclaw/openclaw.git"

    def test_clone_url_picoclaw(self, picoclaw_config):
        assert picoclaw_config.clone_url == "https://github.com/sipeed/picoclaw.git"

    def test_clone_url_zeroclaw(self, zeroclaw_config):
        assert zeroclaw_config.clone_url == "https://github.com/zeroclaw-labs/zeroclaw.git"

    def test_get_clone_command_with_version(self, openclaw_config):
        result = openclaw_config.get_clone_command("v2026.2.1", "/build")
        expected = (
            "git clone --depth 1 --branch v2026.2.1 https://github.com/openclaw/openclaw.git /build"
        )
        assert result == expected

    def test_get_clone_command_main_branch(self, openclaw_config):
        result = openclaw_config.get_clone_command("main", ".")
        assert " --branch main " in result
        assert "openclaw/openclaw.git" in result

    def test_should_patch_workspace_openclaw(self, openclaw_config):
        assert openclaw_config.should_patch_workspace() is True

    def test_should_patch_workspace_picoclaw(self, picoclaw_config):
        assert picoclaw_config.should_patch_workspace() is False

    def test_should_patch_workspace_zeroclaw(self, zeroclaw_config):
        assert zeroclaw_config.should_patch_workspace() is False

    def test_frozen_dataclass_cannot_modify(self, openclaw_config):
        with pytest.raises(AttributeError):
            openclaw_config.github_owner = "modified"


class TestGetUpstream:
    """Tests for get_upstream function."""

    def test_get_openclaw_by_enum(self):
        result = get_upstream(UpstreamType.OPENCLAW)
        assert result.name == UpstreamType.OPENCLAW
        assert result.github_owner == "openclaw"

    def test_get_picoclaw_by_enum(self):
        result = get_upstream(UpstreamType.PICOCLAW)
        assert result.name == UpstreamType.PICOCLAW
        assert result.github_owner == "sipeed"

    def test_get_zeroclaw_by_enum(self):
        result = get_upstream(UpstreamType.ZEROCLAW)
        assert result.name == UpstreamType.ZEROCLAW
        assert result.github_owner == "zeroclaw-labs"

    def test_get_openclaw_by_string(self):
        result = get_upstream("openclaw")
        assert result.name == UpstreamType.OPENCLAW

    def test_get_picoclaw_by_string(self):
        result = get_upstream("picoclaw")
        assert result.name == UpstreamType.PICOCLAW

    def test_get_zeroclaw_by_string(self):
        result = get_upstream("zeroclaw")
        assert result.name == UpstreamType.ZEROCLAW

    def test_get_invalid_upstream(self):
        with pytest.raises(ValueError):
            get_upstream("nonexistent")


class TestGetAllUpstreams:
    """Tests for get_all_upstreams function."""

    def test_returns_list(self):
        result = get_all_upstreams()
        assert isinstance(result, list)

    def test_contains_openclaw(self):
        result = get_all_upstreams()
        names = [u.name for u in result]
        assert UpstreamType.OPENCLAW in names

    def test_contains_picoclaw(self):
        result = get_all_upstreams()
        names = [u.name for u in result]
        assert UpstreamType.PICOCLAW in names

    def test_contains_zeroclaw(self):
        result = get_all_upstreams()
        names = [u.name for u in result]
        assert UpstreamType.ZEROCLAW in names

    def test_returns_at_least_two_upstreams(self):
        result = get_all_upstreams()
        assert len(result) >= 4


class TestValidateVersionFormat:
    """Tests for validate_version_format function."""

    def test_valid_version_with_v_prefix(self):
        assert validate_version_format("v2026.2.1") is True
        assert validate_version_format("v1.0.0") is True

    def test_valid_version_main(self):
        assert validate_version_format("main") is True

    def test_valid_version_latest(self):
        assert validate_version_format("latest") is True

    def test_valid_version_with_oc_prefix(self):
        assert validate_version_format("oc_main") is True
        assert validate_version_format("oc_v2026.2.1") is True

    def test_valid_version_with_pc_prefix(self):
        assert validate_version_format("pc_main") is True

    def test_valid_version_with_zc_prefix(self):
        assert validate_version_format("zc_main") is True

    def test_valid_version_numeric_only(self):
        assert validate_version_format("2026.2.1") is True
        assert validate_version_format("1.0.0") is True

    def test_invalid_empty(self):
        assert validate_version_format("") is False

    def test_invalid_none(self):
        assert validate_version_format(None) is False


class TestGetDockerfileBuildArgs:
    """Tests for get_dockerfile_build_args function."""

    def test_openclaw_main(self):
        result = get_dockerfile_build_args(UpstreamType.OPENCLAW, "main")
        assert result["UPSTREAM"] == "openclaw"
        assert result["UPSTREAM_VERSION"] == "main"
        assert result["GITHUB_OWNER"] == "openclaw"
        assert result["GITHUB_REPO"] == "openclaw"
        assert result["CLI_NAME"] == "openclaw"

    def test_picoclaw_main(self):
        result = get_dockerfile_build_args(UpstreamType.PICOCLAW, "main")
        assert result["UPSTREAM"] == "picoclaw"
        assert result["UPSTREAM_VERSION"] == "main"
        assert result["GITHUB_OWNER"] == "sipeed"
        assert result["GITHUB_REPO"] == "picoclaw"
        assert result["CLI_NAME"] == "picoclaw"

    def test_with_string_upstream(self):
        result = get_dockerfile_build_args("openclaw", "v2026.2.1")
        assert result["UPSTREAM"] == "openclaw"
        assert result["UPSTREAM_VERSION"] == "v2026.2.1"

    def test_latest_normalizes_to_main(self):
        result = get_dockerfile_build_args("openclaw", "latest")
        assert result["UPSTREAM_VERSION"] == "main"


class TestUpstreamsDict:
    """Tests for UPSTREAMS dictionary."""

    def test_has_openclaw(self):
        assert UpstreamType.OPENCLAW in UPSTREAMS

    def test_has_picoclaw(self):
        assert UpstreamType.PICOCLAW in UPSTREAMS

    def test_has_zeroclaw(self):
        assert UpstreamType.ZEROCLAW in UPSTREAMS

    def test_values_are_configs(self):
        for config in UPSTREAMS.values():
            assert isinstance(config, UpstreamConfig)

    def test_names_match_keys(self):
        for key, config in UPSTREAMS.items():
            assert config.name == key


class TestUpstreamConfigProperties:
    """Tests for UpstreamConfig computed properties."""

    def test_openclaw_app_directory(self):
        config = UPSTREAMS[UpstreamType.OPENCLAW]
        assert config.app_directory == "/opt/openclaw/app"

    def test_picoclaw_app_directory(self):
        config = UPSTREAMS[UpstreamType.PICOCLAW]
        assert config.app_directory == "/opt/picoclaw/app"

    def test_openclaw_mjs_entrypoint(self):
        config = UPSTREAMS[UpstreamType.OPENCLAW]
        assert config.mjs_entrypoint == "openclaw.mjs"

    def test_picoclaw_mjs_entrypoint(self):
        config = UPSTREAMS[UpstreamType.PICOCLAW]
        assert config.mjs_entrypoint == "picoclaw.mjs"

    def test_zeroclaw_mjs_entrypoint(self):
        config = UPSTREAMS[UpstreamType.ZEROCLAW]
        assert config.mjs_entrypoint == "zeroclaw"

    def test_openclaw_cli_name(self):
        config = UPSTREAMS[UpstreamType.OPENCLAW]
        assert config.cli_name == "openclaw"

    def test_picoclaw_cli_name(self):
        config = UPSTREAMS[UpstreamType.PICOCLAW]
        assert config.cli_name == "picoclaw"

    def test_zeroclaw_cli_name(self):
        config = UPSTREAMS[UpstreamType.ZEROCLAW]
        assert config.cli_name == "zeroclaw"

    def test_zeroclaw_app_directory(self):
        config = UPSTREAMS[UpstreamType.ZEROCLAW]
        assert config.app_directory == "/opt/zeroclaw/app"
