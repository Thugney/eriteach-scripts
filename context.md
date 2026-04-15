# eriteach-scripts-temp - Script Repo Context

## What this project is

Actual PowerShell script repository that supports the blog and Eriteach technical content.
The repo currently holds deployment and Intune-related scripts and is the real code home
behind the wrapper `eriteach-blog\eriteach-scripts-temp\`.

---

## Actual folder structure

```text
J:\workspace-full\projects\eriteach-side-hustle\eriteach-blog\eriteach-scripts-temp\
|-- context.md
|-- README.md
|-- LICENSE
|-- deployment\
|-- intune\
+-- work\
```

---

## Routing table

| Task | Load | Skip |
|------|------|------|
| Intune scripts or remediations | this file + `intune\` | deployment unless needed |
| Deployment/imaging scripts | this file + `deployment\` | Intune unless needed |
| Repository usage or script inventory | this file + `README.md` | unrelated folders |
| Editorial/blog workflow rules | switch to `..\CONTEXT.md` or `..\..\CONTEXT.md` | script code unless needed |

---

## Tech stack

- PowerShell script repository
- Intune remediations and Win32 support scripts
- Deployment and imaging scripts

---

## Rules

- Treat this folder as the canonical script repo, not the wrapper folder above it
- Keep script purpose and usage aligned with the README inventory
- Use the wrapper blog context for editorial routing, not for script implementation
