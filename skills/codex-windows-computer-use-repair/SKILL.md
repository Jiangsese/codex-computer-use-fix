---
name: codex-windows-computer-use-repair
description: Repair Codex Desktop on Windows when Computer Use or bundled local plugins become unavailable after restart or Store update. Use when Settings says "Computer Use plugin unavailable", plugin icons are broken, bundled plugins disappear, `openai-bundled` is missing from `codex plugin list`, or `.codex\.tmp\bundled-marketplaces\openai-bundled` keeps reverting to a partial cache.
---

# Codex Windows Computer Use Repair

Use this skill on Windows only. The common failure pattern is:

- Codex Desktop starts, but Computer Use says the plugin is unavailable.
- Bundled plugins such as Computer Use, Browser, Chrome, Sites, or LaTeX disappear or show broken icons.
- `codex plugin list` does not show `openai-bundled`, or the temporary bundled marketplace contains only `chrome`.

The stable fix is to stop trusting the temporary bundled marketplace under `.codex\.tmp`. Copy the official bundled plugin marketplace from the installed Codex package into a persistent marketplace under `.codex\marketplaces\openai-bundled`, then point `config.toml` at that persistent copy.

## Quick Repair

Run the bundled repair script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<this skill>\scripts\repair-codex-windows-computer-use.ps1"
```

If the user explicitly wants to refresh files even when the script thinks the state is already OK, add `-Force`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<this skill>\scripts\repair-codex-windows-computer-use.ps1" -Force
```

After the script succeeds, ask the user to fully quit and reopen Codex Desktop. A newly created conversation may be needed before Computer Use tools are injected into that turn.

## What The Script Does

The script performs a narrow local repair:

1. Finds the installed Windows Store package `OpenAI.Codex`.
2. Copies `app\resources\plugins\openai-bundled` from that package to `%USERPROFILE%\.codex\marketplaces\openai-bundled`.
3. Copies bundled plugin versions into `%USERPROFILE%\.codex\plugins\cache\openai-bundled`.
4. Updates `%USERPROFILE%\.codex\config.toml` to use the persistent marketplace.
5. Enables `computer-use@openai-bundled`, `latex@openai-bundled`, `browser@openai-bundled`, `chrome@openai-bundled`, and `sites@openai-bundled`.
6. Sets `features.computer_use = true`.
7. Sets `windows.sandbox = "unelevated"`.
8. Sets the user environment variable `CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE=1`.
9. Writes a backup beside `config.toml` before editing it.

It does not modify `C:\Program Files\WindowsApps` in place, does not install a startup task, and does not require admin rights in normal Codex installs.

## Verification

After repair, verify with the local Codex CLI if available:

```powershell
codex plugin list
```

If `codex` from `WindowsApps` returns `Access is denied`, do not treat that as the plugin failure. Find the local CLI instead:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin" -Recurse -Filter codex.exe |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 -ExpandProperty FullName
```

Then run:

```powershell
& "<local codex.exe>" plugin list
```

Expected result:

- Marketplace `openai-bundled` points at `%USERPROFILE%\.codex\marketplaces\openai-bundled`.
- `computer-use@openai-bundled` is `installed, enabled`.
- `latex@openai-bundled` is `installed, enabled`.
- Browser/Sites/Chrome may depend on current Desktop state and installed browsers, but missing Chrome should not block Computer Use.

Check Desktop logs for Computer Use startup:

```powershell
$logRoot = Join-Path $env:LOCALAPPDATA "Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Codex\Logs"
Get-ChildItem $logRoot -Recurse -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 5 |
  ForEach-Object {
    Select-String -LiteralPath $_.FullName -Pattern "computer-use native pipe startup ready|computer-use native pipe startup failed|missing-helper-path"
  }
```

Good sign:

```text
computer-use native pipe startup ready
```

## Notes

- `.codex\.tmp\bundled-marketplaces\openai-bundled` may still be recreated by Codex and may still contain only `chrome`. That is acceptable after this repair because `config.toml` no longer depends on that temporary directory.
- `EBUSY` warnings about removing `.codex\.tmp\bundled-marketplaces\openai-bundled\plugins\chrome\extension-host` are usually harmless if `openai-bundled` points at the persistent marketplace and Computer Use starts.
- If a current conversation cannot use Computer Use even after the Desktop log says startup is ready, start a new conversation. The native pipe is injected into eligible turns at session startup.
