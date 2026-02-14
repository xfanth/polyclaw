"""Integration tests for GitHub API validation."""

import os

import pytest

from lib.upstream import UPSTREAMS, UpstreamType, get_upstream


@pytest.mark.integration
class TestGitHubIntegration:
    """Integration tests that verify GitHub repository access."""

    @pytest.fixture(autouse=True)
    def setup(self):
        self.skip_if_no_network()

    def skip_if_no_network(self):
        if os.environ.get("SKIP_NETWORK_TESTS"):
            pytest.skip("Network tests disabled")

    def test_openclaw_repo_exists(self):
        """Verify OpenClaw repository exists and is accessible."""
        import requests

        config = get_upstream(UpstreamType.OPENCLAW)
        response = requests.get(
            f"https://api.github.com/repos/{config.github_owner}/{config.github_repo}", timeout=10
        )
        assert response.status_code == 200, f"OpenClaw repo not found: {response.text}"

    def test_picoclaw_repo_exists(self):
        """Verify PicoClaw repository exists and is accessible."""
        import requests

        config = get_upstream(UpstreamType.PICOCLAW)
        response = requests.get(
            f"https://api.github.com/repos/{config.github_owner}/{config.github_repo}", timeout=10
        )
        assert response.status_code == 200, f"PicoClaw repo not found: {response.text}"

    def test_openclaw_has_main_branch(self):
        """Verify OpenClaw has main branch."""
        import requests

        config = get_upstream(UpstreamType.OPENCLAW)
        url = f"https://api.github.com/repos/{config.github_owner}/{config.github_repo}/branches/{config.default_branch}"
        response = requests.get(url, timeout=10)
        assert response.status_code == 200, f"OpenClaw main branch not found: {response.text}"

    def test_picoclaw_has_main_branch(self):
        """Verify PicoClaw has main branch."""
        import requests

        config = get_upstream(UpstreamType.PICOCLAW)
        url = f"https://api.github.com/repos/{config.github_owner}/{config.github_repo}/branches/{config.default_branch}"
        response = requests.get(url, timeout=10)
        assert response.status_code == 200, f"PicoClaw main branch not found: {response.text}"


@pytest.mark.integration
class TestUpstreamConfigIntegration:
    """Integration tests for upstream configuration consistency."""

    def test_all_upstreams_have_valid_configs(self):
        """Verify all defined upstreams have complete configuration."""
        for upstream_type, config in UPSTREAMS.items():
            assert config.name == upstream_type
            assert config.github_owner, f"{upstream_type}: github_owner required"
            assert config.github_repo, f"{upstream_type}: github_repo required"
            assert config.default_branch, f"{upstream_type}: default_branch required"
            assert config.cli_name, f"{upstream_type}: cli_name required"
            assert config.app_directory, f"{upstream_type}: app_directory required"
            assert config.mjs_entrypoint, f"{upstream_type}: mjs_entrypoint required"

    def test_upstream_app_directories_are_unique(self):
        """Verify each upstream has a unique app directory."""
        directories = [config.app_directory for config in UPSTREAMS.values()]
        assert len(directories) == len(set(directories)), "App directories must be unique"

    def test_upstream_cli_names_are_unique(self):
        """Verify each upstream has a unique CLI name."""
        cli_names = [config.cli_name for config in UPSTREAMS.values()]
        assert len(cli_names) == len(set(cli_names)), "CLI names must be unique"
