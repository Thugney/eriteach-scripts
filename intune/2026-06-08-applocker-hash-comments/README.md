# Clean AppLocker XML hash comments

Purpose: normalize rough AppLocker XML snippets where lines beginning with `#` are notes, labels, or source metadata rather than policy XML.

## Interpretation

`ignore the text with #` is treated as: ignore any full line where the first non-whitespace character is `#`.

Examples ignored:

```text
#msi
#./Vendor/SomeInstaller.msi
    # copied from vendor allow-list
```

Examples preserved:

```xml
<!-- XML comments remain valid XML and are preserved -->
<FilePublisherRule Id="..." Name="..." Description="..." UserOrGroupSid="S-1-1-0" Action="Allow" />
```

## Usage

```powershell
.\Clean-AppLockerXmlHashComments.ps1 `
  -InputPath .\rough-applocker.xml `
  -OutputPath .\clean-applocker.xml `
  -ValidateXml
```

For text already held in memory:

```powershell
.\Clean-AppLockerXmlHashComments.ps1 `
  -LiteralText $RawSnippet `
  -OutputPath .\clean-applocker.xml `
  -ValidateXml
```

## Validation

- Hash-prefixed lines are removed before XML parsing.
- Remaining lines are preserved exactly apart from normalized CRLF line endings.
- Optional `-ValidateXml` fails the run if the cleaned result is not well-formed XML.
- Logs are written to `C:\MK-LogFiles\Clean-AppLockerXmlHashComments.log`.

## Ambiguity documented

The original rough snippet was not available in this Kanban task context. I therefore implemented the parser behavior instead of producing a cleaned instance of the unknown snippet. If inline trailing `#` comments should also be stripped, that is a separate rule and intentionally not enabled here because `#` can be meaningful inside XML attribute values or paths.
