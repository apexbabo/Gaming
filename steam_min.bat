@(set "0=%~f0" '& set 1=%*) & powershell -nop -c .([scriptblock]::Create((out-string -i (gc -lit $env:0)))) & exit /b ');.{

" Steam_min : always starts in SmallMode with reduced ram usage when idle - AveYo, 2025.04.17 " 

$FriendsSignIn = 0
$ShowGameIcons = 0

$do_not_minimize_window_while_waiting = 0
$do_not_set_steam_to_disable_gpuaccel = 0
$do_not_set_steam_to_disable_joystick = 0

##  AveYo: main script section
$stamp = 20250417
$nojoy = ("-nojoy "," ")[$do_not_set_steam_to_disable_joystick -ge 1]
$nogpu = ("-cef-in-process-gpu -cef-disable-gpu-compositing -cef-disable-gpu","")[$do_not_set_steam_to_disable_gpuaccel -ge 1]
$QUICK = "-silent -quicklogin -forceservice -console -vgui -oldtraymenu -vrdisable -nofriendsui -no-dwrite $nojoy" +
         "-cef-force-browser-underlay -cef-delaypageload -cef-force-occlusion -cef-single-process $nogpu"
$STEAM = resolve-path (gp "HKCU:\SOFTWARE\Valve\Steam" -ea 0).SteamPath

##  AveYo: minimize script
if ($do_not_minimize_window_while_waiting -le 0) {
  powershell -win 2 -nop -c ';'
} 

##  AveYo: lean and mean helper functions to process steam vdf files -------------------------------------------------------------
function vdf_parse {
  param([string[]]$vdf, [ref]$line = ([ref]0), [string]$re = '\A\s*("(?<k>[^"]+)"|(?<b>[\{\}]))\s*(?<v>"(?:\\"|[^"])*")?\Z')
  $obj = new-object System.Collections.Specialized.OrderedDictionary # ps 3.0: [ordered]@{}
  while ($line.Value -lt $vdf.count) {
    if ($vdf[$line.Value] -match $re) {
      if ($matches.k) { $key = $matches.k }
      if ($matches.v) { $obj.$key = $matches.v }
      elseif ($matches.b -eq '{') { $line.Value++; $obj.$key = vdf_parse -vdf $vdf -line $line }
      elseif ($matches.b -eq '}') { break }
    }
    $line.Value++
  }
  return $obj
}
function vdf_print {
  param($vdf, [ref]$indent = ([ref]0)); reload_escape_chars
  if ($vdf -isnot [System.Collections.Specialized.OrderedDictionary]) {return}
  foreach ($key in $vdf.Keys) {
    if ($vdf[$key] -is [System.Collections.Specialized.OrderedDictionary]) {
      $tabs = "$_t" * $indent.Value
      write-output "$tabs$_q$key$_q$_n$tabs{$_n"
      $indent.Value++; vdf_print -vdf $vdf[$key] -indent $indent; $indent.Value--
      write-output "$tabs}$_n"
    } else {
      $tabs = "$_t" * $indent.Value
      write-output "$tabs$_q$key$_q$_t$_t$($vdf[$key])$_n"
    }
  }
}
function vdf_mkdir {
  param($vdf, [string]$path = ''); $s = $path.split('\',2); $key = $s[0]; $recurse = $s[1]
  if ($vdf.Keys -notcontains $key) { $vdf.$key = new-object System.Collections.Specialized.OrderedDictionary }
  if ($recurse) { vdf_mkdir $vdf[$key] $recurse }
}
function reload_escape_chars {
  $c = @{_t = 9; _n = 10; _f = 12; _r = 13; _q = 34; _s = 36}
  $c.getenumerator() | foreach { set $_.Name $([char]($_.Value)) -scope 1 -force -ea 0}
}
function sc-nonew {
  param($fn,$txt)
  if ((Get-Command set-content).Parameters['nonewline'] -ne $null) { set-content $fn $txt -nonewline -force }
  else { $_n = [char]10; [IO.File]::WriteAllText($fn, $txt -join "$_n") } # ps2.0
}
reload_escape_chars

##  AveYo: change steam startup location to Library window
dir "$STEAM\userdata\*\7\remote\sharedconfig.vdf" -Recurse |foreach {
  $file = $_; $write = $false; $vdf = vdf_parse -vdf (gc $file -force)
  vdf_mkdir $vdf["SteamDefaultDialog"] 'Software\Valve\Steam'
  $key = $vdf["SteamDefaultDialog"]["Software"]["Valve"]["Steam"]
  if ($key["SteamDefaultDialog"] -ne '"#app_games"') { $key["SteamDefaultDialog"] = '"#app_games"'; $write = $true }
  if ($write) { sc-nonew $file $(vdf_print $vdf); write-output " $file " }
}

##  AveYo: enable Small Mode and library performance options
$opt = @{LibraryDisableCommunityContent=1; LibraryLowBandwidthMode=1; LibraryLowPerfMode=1; LibraryDisplayIconInGameList=0}
if ($ShowGameIcons -eq 1) {$opt.LibraryDisplayIconInGameList = 1}
dir "$STEAM\userdata\*\config\localconfig.vdf" -Recurse |foreach {
  $file = $_; $write = $false; $vdf = vdf_parse -vdf (gc $file -force)
  vdf_mkdir $vdf["UserLocalConfigStore"] 'Software\Valve\Steam'
  $key = $vdf["UserLocalConfigStore"]["Software"]["Valve"]["Steam"]
  if ($key["SmallMode"] -ne '"1"') { $key["SmallMode"] = '"1"'; $write = $true }
  foreach ($o in $opt.Keys) { if ($vdf["UserLocalConfigStore"]["$o"] -ne "$_q$($opt[$o])$_q") {
    $vdf["UserLocalConfigStore"]["$o"] = "$_q$($opt[$o])$_q"; $write = $true
  }}
  if ($FriendsSignIn -eq 0) {
    vdf_mkdir $vdf["UserLocalConfigStore"] 'friends'
    $key = $vdf["UserLocalConfigStore"]["friends"]
    if ($key["SignIntoFriends"] -ne '"0"') { $key["SignIntoFriends"] = '"0"'; $write = $true }
  }
  if ($write) { sc-nonew $file $(vdf_print $vdf); write-output " $file " }
}

##  AveYo: add steam_reset.bat
if (-not (test-path "$STEAM\steam_reset.bat")) { set-content "$STEAM\steam_reset.bat" @'
@reg delete HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v Steam /f
@reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\steamwebhelper.exe" /f
@start "" "%~dp0steam.exe" -silent +quit force 
@timeout /t 5 /nobreak
@pushd "%~dp0userdata" & del /f /s /q localconfig.vdf sharedconfig.vdf
@start "" "%~dp0steam.exe" -silent
'@ -force
}

##  AveYo: if pasted directly into powershell or location does not match, save to steam
$file = "$STEAM\steam_min.bat"
if ($env:0 -ne $file) {
  set-content -force $file $(
    @( '@(set "0=%~f0" ''& set 1=%*) & powershell -nop -' +
    'c .([scriptblock]::Create((out-string -i (gc -lit $env:0)))) & exit /b '');.{' +
    $($MyInvocation.MyCommand.Definition) +
    '} #_press_Enter_if_pasted_in_powershell' ) -split'\r?\n'
  ) ##  lean and mean hybrid ps 2.0 batch header + footer @ AveYo 2025
}

##  AveYo: refresh Steam_min desktop shortcut and startup run if enabled
$short = "$([Environment]::GetFolderPath('Desktop'))\Steam_min.lnk"
$s = (new-object -ComObject WScript.Shell).CreateShortcut($short)
if (-not (test-path $short) -or $s.Arguments -notmatch "$stamp") {
  $s.Description = "$STEAM\steam.exe"; $s.IconLocation = "$STEAM\steam.exe,0"; $s.WindowStyle = 7 # min
  $s.TargetPath = "$STEAM\steam_min.bat"; $s.Arguments = "$stamp"; $s.Save()
}
$start = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (gp $start Steam -ea 0) { sp $start Steam "$STEAM\steam_min.bat" }

##  AveYo: start Steam with quick launch options - now under explorer parent
ni "HKCU:\Software\Classes\.steam_min\shell\open\command" -force >''
sp "HKCU:\Software\Classes\.steam_min\shell\open\command" "(Default)" "$_q$STEAM\steam.exe$_q $QUICK"
$L = "$STEAM\.steam_min"; if (!(test-path $L)) { set-content $L "" } ; start explorer -args "$_q$L$_q"
} #_press_Enter_if_pasted_in_powershell
