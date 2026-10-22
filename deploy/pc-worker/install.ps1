# Installs the Chatterbox worker on this PC. Run over SSH by scripts/pc-worker-setup.sh.
param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$home_ = Join-Path $env:USERPROFILE '.chatterbox'
$task = 'Chatterbox Ollama'
if ($Remove) {
  Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force $home_ -ErrorAction SilentlyContinue
  'removed'
  return
}
New-Item -ItemType Directory -Force $home_, 'D:\Chatterbox\workspaces', 'D:\Chatterbox\attachments' | Out-Null
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$vbs = Join-Path $home_ 'ollama-serve.vbs'
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$vbs`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
# Ollama only starts in the logged-in desktop session, which the task runs in.
if (-not (Get-Process ollama -ErrorAction SilentlyContinue)) {
  Start-ScheduledTask -TaskName $task
  foreach ($i in 1..40) { try { Invoke-RestMethod http://127.0.0.1:11434/api/version -TimeoutSec 1 | Out-Null; break } catch { Start-Sleep -Milliseconds 500 } }
}
'installed'
