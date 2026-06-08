function Invoke-ClaudeFast { claude --dangerously-disable-win-sandbox --dangerously-skip-permissions @args }
Set-Alias -Name claude-fast -Value Invoke-ClaudeFast

# Android SDK tools
$env:PATH += ";$env:LOCALAPPDATA\Android\Sdk\platform-tools;$env:LOCALAPPDATA\Android\Sdk\emulator"

# Match WSL/bash readline: emacs-style command-line editing so PowerShell and
# WSL terminals behave the same (Ctrl+A/E/B/F/P/N/K/U/W/Y/D/T/R, Alt+B/F/D).
# Uses PSReadLine's emacs defaults (Tab=Complete, audible bell) to line up with
# bash rather than diverging.
Set-PSReadLineOption -EditMode Emacs
# Emacs mode leaves Ctrl+C unbound (it just beeps at the prompt). Restore the
# Windows-mode behavior so Ctrl+C cancels the current line like bash does
# (copies instead if text is selected). Interrupting running programs is handled
# by the console regardless.
Set-PSReadLineKeyHandler -Chord 'Ctrl+c' -Function CopyOrCancelLine
