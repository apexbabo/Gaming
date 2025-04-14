<# ::
@echo off & set "0=%~f0" & powershell -nop -c iex(out-string -i (gc -lit $env:0)) & exit /b
#>.{

" Steam_min : always starts in SmallMode with reduced ram usage when idle - AveYo, 2025.04.14 " 

$FriendsSignIn = 0
$ShowGameIcons = 0
$use_opt_nojoy = 1

$stamp = 20250414
$NOJOY = ('','-nojoy ')[$use_opt_nojoy -eq 1] 
$QUICK = '-silent -quicklogin -vgui -oldtraymenu -nofriendsui -no-dwrite ' + $NOJOY + 
         '-vrdisable -forceservice -console -cef-force-browser-underlay -cef-delaypageload -cef-force-occlusion ' +
         '-cef-single-process -cef-in-process-gpu -cef-disable-gpu-compositing -cef-disable-gpu' 
$STEAM = resolve-path (gp "HKCU:\SOFTWARE\Valve\Steam" -ea 0).SteamPath

##  AveYo: minimize script
powershell -win 2 -nop -c ';' 

##  AveYo: lean and mean helper functions to process steam vdf files
function vdf_read {
  param([string[]]$vdf, [ref]$line=([ref]0), [string]$r='\A\s*("(?<k>[^"]+)"|(?<b>[\{\}]))\s*(?<v>"(?:\\"|[^"])*")?\Z') #
  $obj = new-object System.Collections.Specialized.OrderedDictionary # ps 3.0: [ordered]@{}
  while ($line.Value -lt $vdf.count) {
    if ($vdf[$line.Value] -match $r) {
      if ($matches.k) { $key = $matches.k }
      if ($matches.v) { $obj.$key = $matches.v }
      elseif ($matches.b -eq '{') { $line.Value++; $obj.$key = vdf_read -vdf $vdf -line $line }
      elseif ($matches.b -eq '}') { break }
    } 
    $line.Value++
  }
  return $obj
}
function vdf_write {
  param($vdf, [ref]$indent=([ref]0))
  if ($vdf -isnot [System.Collections.Specialized.OrderedDictionary]) {return}
  foreach ($key in $vdf.Keys) {
    if ($vdf[$key] -is [System.Collections.Specialized.OrderedDictionary]) {
      $t = "`t" * $indent.Value
      write-output "$t`"$key`"`n$t{`n"
      $indent.Value++; vdf_write -vdf $vdf[$key] -indent $indent; $indent.Value--
      write-output "$t}`n"
    } else {
      $t = "`t" * $indent.Value
      write-output "$t`"$key`"`t`t$($vdf[$key])`n"
    }
  }
}
function vdf_mkdir {
  param($vdf, [string]$path=''); $s = $path.split('\',2); $key = $s[0]; $recurse = $s[1]
  if ($vdf.Keys -notcontains $key) { $vdf.$key = new-object System.Collections.Specialized.OrderedDictionary }
  if ($recurse) { vdf_mkdir $vdf[$key] $recurse }
}
function sc-nonew($fn,$txt) {
  if ((Get-Command set-content).Parameters['nonewline'] -ne $null) { set-content $fn $txt -nonewline -force }
  else { [IO.File]::WriteAllText($fn, $txt -join "`n") } # ps2.0
}

##  AveYo: change steam startup location to Library window
dir "$STEAM\userdata\*\7\remote\sharedconfig.vdf" -Recurse |foreach {
  $file = $_; $write = $false; $vdf = vdf_read -vdf (gc $file -force)
  vdf_mkdir $vdf["SteamDefaultDialog"] 'Software\Valve\Steam'
  $key = $vdf["SteamDefaultDialog"]["Software"]["Valve"]["Steam"]
  if ($key["SteamDefaultDialog"] -ne '"#app_games"') { $key["SteamDefaultDialog"] = '"#app_games"'; $write = $true }
  if ($write) { sc-nonew $file $(vdf_write $vdf); write-output " $file " }
}

##  AveYo: enable Small Mode and library performance options
$opt = @{LibraryDisableCommunityContent=1; LibraryLowBandwidthMode=1; LibraryLowPerfMode=1; LibraryDisplayIconInGameList=0}
if ($ShowGameIcons -eq 1) {$opt.LibraryDisplayIconInGameList = 1}
dir "$STEAM\userdata\*\config\localconfig.vdf" -Recurse |foreach {
  $file = $_; $write = $false; $vdf = vdf_read -vdf (gc $file -force)
  vdf_mkdir $vdf["UserLocalConfigStore"] 'Software\Valve\Steam'
  $key = $vdf["UserLocalConfigStore"]["Software"]["Valve"]["Steam"]
  if ($key["SmallMode"] -ne '"1"') { $key["SmallMode"] = '"1"'; $write = $true }
  foreach ($o in $opt.Keys) { if ($vdf["UserLocalConfigStore"]["$o"] -ne "`"$($opt[$o])`"") {
    $vdf["UserLocalConfigStore"]["$o"] = "`"$($opt[$o])`""; $write = $true
  }}
  if ($FriendsSignIn -eq 0) {
    vdf_mkdir $vdf["UserLocalConfigStore"] 'friends'
    $key = $vdf["UserLocalConfigStore"]["friends"]
    if ($key["SignIntoFriends"] -ne '"0"') { $key["SignIntoFriends"] = '"0"'; $write = $true }
  }
  if ($write) { sc-nonew $file $(vdf_write $vdf); write-output " $file " }
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

##  AveYo: was this directly pasted into powershell? then we must save on disk
if (!$env:0 -or $env:0 -ne "$STEAM\steam_min.bat" -or $stamp -lt 20250414) {
  $f0 = @("<# ::`n"+'@echo off & set "0=%~f0" & powershell -nop -c iex(out-string -i (gc -lit $env:0)) & exit /b'+
          "`n#>.{"+($MyInvocation.MyCommand.Definition)+'};$_press_Enter_if_pasted_in_powershell') -split'\r?\n'
  set-content "$STEAM\steam_min.bat" $f0 -force
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
sp "HKCU:\Software\Classes\.steam_min\shell\open\command" "(Default)" "`"$STEAM\steam.exe`" $QUICK"
if (!(test-path "$STEAM\.steam_min")) { set-content "$STEAM\.steam_min" "" }
start explorer -args "`"$STEAM\.steam_min`""
};$_press_Enter_if_pasted_in_powershell
