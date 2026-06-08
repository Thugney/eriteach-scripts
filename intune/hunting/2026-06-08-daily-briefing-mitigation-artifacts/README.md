# Daily security briefing artifacts - 2026-06-08

Generated from the 2026-06-08 Hermes Daily Microsoft Security & Cloud Change Briefing.

## Purpose

Practical artifacts for the items Robel actually needed from the briefing:

- Defender KEV mitigation checks for CVE-2026-41091 and CVE-2026-45498.
- MDE stale/unhealthy endpoint triage.
- ASR signal review.
- AI agent inventory migration to `AgentsInfo`.
- Purview Endpoint DLP readiness query.
- Intune how-to guide for Defender update health mitigation.
- Intune proactive remediation detection/remediation scripts for Defender engine/platform compliance.

## Recommended order

1. Run `kql/mde-stale-unhealthy-devices.kql` in Defender Advanced Hunting.
2. Run `kql/defender-engine-tvm-inventory.kql` if TVM exposes Defender engine/platform inventory in your tenant.
3. Deploy the Intune remediation pair from `scripts/` to a pilot Windows device group.
4. Use `guides/intune-defender-kev-mitigation-policy.md` to create/update the Defender Antivirus update policy.
5. Review `kql/asr-signal-review.kql`, `kql/ai-agent-inventory-agentsinfo.kql`, and `kql/purview-endpoint-dlp-readiness.kql` as follow-up controls.

## Fixed versions to validate

- Defender Malware Protection Engine: `1.1.26040.8` or newer.
- Defender Antimalware Platform: `4.18.26040.7` or newer.

## Scope

- Windows endpoints only for Defender KEV mitigation.
- No macOS/Linux endpoint recommendations.
- iPad/iOS/Android are not affected by the Defender engine/platform checks.
