# Release checklist - Windows Update Health Remediation

## Pre-release

- [ ] Confirm script version in both PowerShell headers.
- [ ] Run static validation from repository root.
- [ ] Confirm no tenant names, domains, hostnames, usernames, policy names, or secrets are present.
- [ ] Confirm default remediation is `Conservative`.
- [ ] Confirm no runtime download, forced restart, service ACL reset, telemetry mutation, or policy deletion is present.

## Pilot

- [ ] Assign to a small pilot group.
- [ ] Run as System.
- [ ] Run in 64-bit PowerShell.
- [ ] Review Intune detection/remediation output.
- [ ] Spot-check `C:\MK-LogFiles` on at least one successful and one remediated endpoint.
- [ ] Confirm no unexpected reboots.

## Release tracking

Record these values in the Intune remediation package description or change ticket:

| Field | Value |
|---|---|
| Tool | Windows Update Health Remediation |
| Script version | 1.0.0 |
| Repository | `Thugney/eriteach-scripts` |
| Branch/commit | `<fill after merge>` |
| Pilot group | `<pilot group>` |
| Rollout date | `<date>` |
| Rollback owner | `<owner>` |

## Rollback

1. Unassign or pause the Intune remediation package.
2. If `CacheReset` was used on a device, restore timestamped `.bak-*` folders only if needed during manual break-fix.
3. Keep logs for troubleshooting before cleanup.
