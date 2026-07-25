# Upstream audit - mertozsoy/WindowsUpdateRemedationTool

Source reviewed: `https://github.com/mertozsoy/WindowsUpdateRemedationTool`

Files reviewed:

- `README.md`
- `Invoke-WindowsUpdateRemediation.ps1`

## What upstream does

The upstream project is a Windows Forms PowerShell GUI that lets an administrator run 10 selectable Windows Update repair steps:

1. clear Windows Update policy registry entries
2. stop BITS, Windows Update, and Cryptographic Services
3. delete BITS QMGR queue files
4. delete `SoftwareDistribution` and `Catroot2`
5. reset BITS/WUA service security descriptors using `sc.exe sdset`
6. re-register update-related DLLs using `regsvr32.exe`
7. reset Winsock
8. restart services
9. trigger an update scan with `USOClient.exe StartInteractiveScan`
10. download and run SetupDiag

## What it solves

It is useful for hands-on break-fix when a single Windows device has a broken Windows Update client, stuck update cache, corrupt BITS queue, or needs SetupDiag output after a failed feature update.

## Enterprise safety assessment

Not recommended as-is for broad automated org rollout.

Reasons:

- It is interactive GUI/admin tooling, not an Intune detection/remediation pair.
- It deletes policy registry keys that may be owned by Intune, Windows Update for Business, Group Policy, or security baselines.
- It changes telemetry-related values without proving policy intent.
- It resets service ACLs, which is too low-level for routine fleet automation.
- It re-registers many DLLs and resets Winsock, which can be disruptive and hard to attribute.
- It deletes update cache folders instead of renaming them for rollback.
- It downloads `SetupDiag.exe` at runtime.
- It does not separate detection from remediation.
- It has no dry-run mode or enterprise rollout gates.

## Rebuild decision

The rebuilt Eriteach version keeps only the safe enterprise pattern:

- read-only detection
- conservative service and BITS queue repair
- optional cache reset by explicit parameter
- logs under `C:\MK-LogFiles`
- no policy deletion
- no telemetry mutation
- no service ACL reset
- no DLL registration
- no runtime executable download
- no forced restart
