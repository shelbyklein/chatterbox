# chatterbox-desktop: lets agents on this PC see and drive the logged-in desktop.
# They run over SSH in session 0, which has no desktop, so each command hands one action to
# the desktop session through a one-off scheduled task (the user's own, interactive), waits
# for it, and cleans up. Needs the user logged in; a locked screen blocks clicks and typing.
#
#   chatterbox-desktop screenshot [FILE]        PNG of the screen (default: .\screenshots\)
#   chatterbox-desktop windows                  visible windows: title, position, size
#   chatterbox-desktop open TARGET              open a file or app on the desktop (as a double-click would)
#   chatterbox-desktop focus TITLE              bring the first window whose title has TITLE to the front
#   chatterbox-desktop click X Y [right|double] click at screen pixels (as in the screenshot)
#   chatterbox-desktop type TEXT [--in TITLE]   type text (into TITLE's window, which must come to the front)
#   chatterbox-desktop key KEYS [--in TITLE]    keys such as ctrl+s, alt+f4, enter, shift+tab, f5
#   chatterbox-desktop jsx FILE                 run an ExtendScript file in Photoshop (prefer Slippy's tools)
# Arguments are read raw ($args), so PowerShell never takes "--in" for one of its own.
$Request = if ($args.Count -eq 2 -and $args[0] -eq '-Request') { $args[1] } else { $null }
$Action = if (-not $Request -and $args.Count) { [string]$args[0] } else { $null }
$Rest = [string[]]@(if (-not $Request -and $args.Count -gt 1) { $args[1..($args.Count - 1)] })
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($Request) {
  # In the desktop session: do the action, write the outcome next to the request.
  $req = Get-Content $Request -Raw | ConvertFrom-Json
  $out = [ordered]@{ ok = $true; text = '' }
  try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public static class CbDesk {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
}
"@
    [CbDesk]::SetProcessDPIAware() | Out-Null
    $windows = {
      $list = New-Object System.Collections.ArrayList
      [CbDesk]::EnumWindows({ param($h, $l)
        if ([CbDesk]::IsWindowVisible($h)) { $sb = New-Object System.Text.StringBuilder 512; [CbDesk]::GetWindowText($h, $sb, 512) | Out-Null
          if ($sb.Length -gt 0) { $r = New-Object CbDesk+RECT; [CbDesk]::GetWindowRect($h, [ref]$r) | Out-Null; [void]$list.Add([pscustomobject]@{ h = $h; title = $sb.ToString(); x = $r.L; y = $r.T; w = $r.R - $r.L; hgt = $r.B - $r.T }) } }
        $true }, [IntPtr]::Zero) | Out-Null
      $list
    }
    $titleOf = { param($h) $sb = New-Object System.Text.StringBuilder 512; [CbDesk]::GetWindowText($h, $sb, 512) | Out-Null; $sb.ToString() }
    # Brings TITLE's window to the front, waiting up to 5 s for it to appear.
    $focus = { param($title)
      $w = $null
      foreach ($i in 1..25) { $w = & $windows | Where-Object { $_.title -like "*$title*" } | Select-Object -First 1; if ($w) { break }; Start-Sleep -Milliseconds 200 }
      if (-not $w) { throw "No window titled like '$title'." }
      if ([CbDesk]::IsIconic($w.h)) { [CbDesk]::ShowWindow($w.h, 9) | Out-Null }
      [System.Windows.Forms.SendKeys]::SendWait('{F15}')   # Windows lets the foreground change after a key press.
      [CbDesk]::SetForegroundWindow($w.h) | Out-Null
      Start-Sleep -Milliseconds 150
      if ([CbDesk]::GetForegroundWindow() -ne $w.h) { throw "Couldn't bring '$($w.title)' to the front." }
      $w.title
    }
    # Input only goes where it was aimed: with --in, that window must be in front.
    if ($req.window -and $req.action -in 'type', 'key', 'click') { & $focus $req.window | Out-Null }
    # Named before the input goes in (closing a window brings another to the front).
    $target = " into '" + (& $titleOf ([CbDesk]::GetForegroundWindow())) + "'"
    $into = { $target }
    switch ($req.action) {
      'screenshot' {
        $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
        New-Item -ItemType Directory -Force (Split-Path -Parent $req.file) | Out-Null
        $bmp.Save($req.file, [System.Drawing.Imaging.ImageFormat]::Png)
        $out.text = "$($req.file) ($($b.Width)x$($b.Height))"
      }
      'windows' { $out.text = (& $windows | ForEach-Object { "$($_.title)  [$($_.x),$($_.y) $($_.w)x$($_.hgt)]" }) -join "`n" }
      'focus' { $out.text = "focused: " + (& $focus $req.text) }
      'click' {
        [CbDesk]::SetCursorPos([int]$req.x, [int]$req.y) | Out-Null
        Start-Sleep -Milliseconds 60
        $down, $up = if ($req.button -eq 'right') { 0x0008, 0x0010 } else { 0x0002, 0x0004 }
        foreach ($i in 1..$(if ($req.button -eq 'double') { 2 } else { 1 })) { [CbDesk]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero); [CbDesk]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80 }
        $out.text = "clicked $($req.x),$($req.y)$(if ($req.button) { " ($($req.button))" })" + (& $into)
      }
      'type' {
        # Literal text: SendKeys' special characters go in braces.
        $escaped = -join ($req.text.ToCharArray() | ForEach-Object { if ('+^%~(){}[]'.Contains($_)) { "{$_}" } elseif ($_ -eq "`n") { '{ENTER}' } else { $_ } })
        [System.Windows.Forms.SendKeys]::SendWait($escaped)
        $out.text = "typed $($req.text.Length) characters" + (& $into)
      }
      'key' {
        # ctrl+s, alt+f4, shift+tab, enter, f5 → SendKeys (^s, %{F4}, +{TAB}, {ENTER}, {F5}).
        $names = @{ enter = 'ENTER'; return = 'ENTER'; tab = 'TAB'; esc = 'ESC'; escape = 'ESC'; space = ' '; backspace = 'BACKSPACE'
                    delete = 'DELETE'; del = 'DELETE'; insert = 'INSERT'; home = 'HOME'; end = 'END'; pageup = 'PGUP'; pgup = 'PGUP'
                    pagedown = 'PGDN'; pgdn = 'PGDN'; up = 'UP'; down = 'DOWN'; left = 'LEFT'; right = 'RIGHT' }
        $mods = @{ ctrl = '^'; control = '^'; alt = '%'; shift = '+' }
        $keys = -join ($req.text -split '\s+' | Where-Object { $_ } | ForEach-Object {
          $parts = $_.ToLower() -split '\+'; $key = $parts[-1]
          $prefix = -join ($parts[0..($parts.Count - 2)] | Where-Object { $parts.Count -gt 1 } | ForEach-Object { if (-not $mods[$_]) { throw "Unknown modifier '$_'." }; $mods[$_] })
          $k = if ($names[$key]) { if ($names[$key] -eq ' ') { ' ' } else { '{' + $names[$key] + '}' } } elseif ($key -match '^f([1-9]|1[0-6])$') { '{' + $key.ToUpper() + '}' }
               elseif ($key.Length -eq 1) { if ('+^%~(){}[]'.Contains($key)) { '{' + $key + '}' } else { $key } } else { throw "Unknown key '$key'." }
          $prefix + $k })
        [System.Windows.Forms.SendKeys]::SendWait($keys)
        $out.text = "sent $($req.text)" + (& $into)
      }
      'open' { Start-Process -FilePath $req.text; $out.text = "opened $($req.text)" }
      'jsx' {
        $ps = try { New-Object -ComObject Photoshop.Application } catch { New-Object -ComObject Photoshop.Application.BETA }
        $out.text = [string]$ps.DoJavaScriptFile($req.file)
      }
      default { throw "Unknown action '$($req.action)'." }
    }
  } catch { $out.ok = $false; $out.text = $_.Exception.Message }
  $out | ConvertTo-Json -Compress | Set-Content -Path ($Request + '.done') -Encoding UTF8
  return
}

# Over SSH: hand the action to the desktop session and wait for it.
if (-not $Action) { Get-Content $MyInvocation.MyCommand.Path | Select-Object -Skip 4 -First 10 | ForEach-Object { $_.TrimStart('# ') }; exit 2 }
$req = [ordered]@{ action = $Action.ToLower() }
switch ($req.action) {
  'screenshot' { $req.file = if ($Rest) { [IO.Path]::GetFullPath($Rest[0]) } else { Join-Path (Get-Location) ("screenshots\screen-" + (Get-Date -Format 'HHmmss') + ".png") } }
  { $true } {
    # --in TITLE, anywhere after the action, aims typing, keys and clicks at that window.
    $i = [array]::IndexOf([string[]]$Rest, '--in')
    if ($i -ge 0) { if ($i + 1 -ge $Rest.Count) { throw '--in needs a window title' }; $req.window = $Rest[$i + 1]; $Rest = @($Rest | Select-Object -First $i) + @($Rest | Select-Object -Skip ($i + 2)) }
  }
  'click' { if ($Rest.Count -lt 2) { throw 'click X Y [right|double] [--in TITLE]' }; $req.x = [int]$Rest[0]; $req.y = [int]$Rest[1]; if ($Rest.Count -gt 2) { $req.button = $Rest[2].ToLower() } }
  { $_ -in 'type', 'key', 'focus', 'open' } { $req.text = ($Rest -join ' ') }
  'jsx' { $req.file = [IO.Path]::GetFullPath($Rest[0]) }
}
$dir = Join-Path $env:TEMP 'chatterbox-desktop'; New-Item -ItemType Directory -Force $dir | Out-Null
$id = [guid]::NewGuid().ToString('N').Substring(0, 12)
$file = Join-Path $dir "$id.json"
$req | ConvertTo-Json -Compress | Set-Content -Path $file -Encoding UTF8
$task = "Chatterbox Desktop $id"
$vbs = Join-Path $here 'desktop-run.vbs'
schtasks /Create /TN $task /TR "wscript.exe `"$vbs`" `"$($MyInvocation.MyCommand.Path)`" `"$file`"" /SC ONCE /ST 23:59 /IT /F 2>&1 | Out-Null
schtasks /Run /TN $task 2>&1 | Out-Null
$deadline = (Get-Date).AddSeconds($(if ($req.action -eq 'jsx') { 300 } else { 30 }))
while (-not (Test-Path "$file.done") -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 150 }
schtasks /Delete /TN $task /F 2>&1 | Out-Null
if (-not (Test-Path "$file.done")) { Remove-Item $file -ErrorAction SilentlyContinue; [Console]::Error.WriteLine('chatterbox-desktop: no answer from the desktop session. Is the PC logged in?'); exit 1 }
$res = Get-Content "$file.done" -Raw | ConvertFrom-Json
Remove-Item $file, "$file.done" -ErrorAction SilentlyContinue
if ($res.ok) { $res.text } else { [Console]::Error.WriteLine("chatterbox-desktop: $($res.text)"); exit 1 }
