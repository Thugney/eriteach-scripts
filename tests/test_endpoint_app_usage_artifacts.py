from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "intune" / "hunting" / "Export-TenantEndpointAppUsage.ps1"
KQL = REPO_ROOT / "intune" / "hunting" / "tenant-endpoint-app-usage.kql"


def test_script_uses_required_sources_and_excel_export():
    content = SCRIPT.read_text(encoding="utf-8")

    assert "security/runHuntingQuery" in content
    assert "DeviceProcessEvents" in content
    assert "DeviceTvmSoftwareInventory" in content
    assert "deviceManagement/detectedApps" in content
    assert "Export-Excel" in content


def test_script_follows_modum_powershell_baseline():
    content = SCRIPT.read_text(encoding="utf-8")

    assert ".SYNOPSIS" in content
    assert ".DESCRIPTION" in content
    assert "function Write-Log" in content
    assert "'C:\\MK-LogFiles'" in content
    assert "try {" in content
    assert "catch {" in content
    assert "exit 0" in content
    assert "exit 1" in content
    assert not any(character in content for character in "æøåÆØÅ")


def test_kql_standalone_query_contains_expected_aggregation():
    content = KQL.read_text(encoding="utf-8")

    assert "DeviceProcessEvents" in content
    assert "ProcessCreated" in content
    assert "ExecutionCount" in content
    assert "DeviceCount" in content
    assert "UserCount" in content
    assert "ExampleDevices" in content
