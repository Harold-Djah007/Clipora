from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_render_blueprint_uses_backend_docker_and_free_health_checked_service():
    blueprint = (ROOT / "render.yaml").read_text(encoding="utf-8")

    assert "runtime: docker" in blueprint
    assert "plan: free" in blueprint
    assert "dockerfilePath: ./backend/Dockerfile" in blueprint
    assert "dockerContext: ./backend" in blueprint
    assert "healthCheckPath: /health" in blueprint
    assert "autoDeployTrigger: checksPass" in blueprint


def test_backend_container_is_field_host_ready():
    dockerfile = (ROOT / "backend" / "Dockerfile").read_text(encoding="utf-8")

    assert "ffmpeg" in dockerfile
    assert "USER clipora" in dockerfile
    assert "${PORT:-8000}" in dockerfile
    assert "HEALTHCHECK" in dockerfile


def test_field_apk_workflow_requires_public_https_resolver():
    workflow = (ROOT / ".github" / "workflows" / "field-apk.yml").read_text(encoding="utf-8")

    assert "workflow_dispatch:" in workflow
    assert "push:" in workflow
    assert "resolver_url:" in workflow
    assert "field_resolver_url.txt" in workflow
    assert 'parsed.scheme != "https"' in workflow
    assert "CLIPORA_RESOLVER_URL" in workflow
    assert "flutter build apk --release" in workflow
    assert "actions/upload-artifact@v4" in workflow


def test_field_resolver_url_starts_unconfigured_without_fake_endpoint():
    resolver_file = (ROOT / "mobile" / "field_resolver_url.txt").read_text(encoding="utf-8")

    active_lines = [line for line in resolver_file.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    assert active_lines == []
