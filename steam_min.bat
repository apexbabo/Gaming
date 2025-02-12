@(set ^ "0=%~f0" -des ') & powershell -version 2.0 -nop -c iex(out-string -i (gc -lit $env:0)) & exit /b ');.{

" Steam_min : always starts in SmallMode with reduced ram usage when idle - AveYo, 2025.02.12 v2 " 

$QUICK = '-silent -quicklogin -vgui -oldtraymenu -nofriendsui -no-dwrite -vrdisable -forceservice -console ' + 
         '-cef-force-browser-underlay -cef-delaypageload -cef-force-occlusion -cef-disable-gpu -cef-single-process'

$STEAM = resolve-path (gp "HKCU:\SOFTWARE\Valve\Steam" SteamPath -ea 0).SteamPath
pushd "$STEAM\userdata"
$CLOUD = split-path (dir -filter "localconfig.vdf" -Recurse | sort LastWriteTime -Descending | Select -First 1).DirectoryName

function sc-nonew($fn,$txt) {
  if ((Get-Command set-content).Parameters['nonewline'] -ne $null) { set-content $fn $txt -nonewline -force }
  else { [IO.File]::WriteAllText($fn, $txt -join "`n") } # ps2.0
}

#_# AveYo: enable Small Mode and library performance options
$DLG = "`t`t`t`t`"SteamDefaultDialog`"`t`t`"`#app_games`"`n"
dir "$STEAM\userdata\*\7\remote\sharedconfig.vdf" -Recurse |foreach {
  $vdf = $_; $t = new-object System.Text.StringBuilder; $write = $false
  (gc $vdf) |foreach { switch -regex ($_) {
    '\s+"SteamDefaultDialog"\s+"' { if ($_ -notmatch '\#app_games') { $write = !0; [void]$t.Append("$DLG") } } 
    default { [void]$t.Append("$_`n") }  
  }}
  if ($write) { sc-nonew $vdf $t.ToString(); " $vdf" }
}

$SMA = "`t`t`t`t`"SmallMode`"`t`t`"1`"`n"
$LBM = "`t`"LibraryDisableCommunityContent`"`t`t`"1`"`n`t`"LibraryDisplayIconInGameList`"`t`t`"0`"`n" +
         "`t`"LibraryLowBandwidthMode`"`t`t`"1`"`n`t`"LibraryLowPerfMode`"`t`t`"1`"`n"
dir "$STEAM\userdata\*\config\localconfig.vdf" -Recurse |foreach {
  $vdf = $_; $t = new-object System.Text.StringBuilder; $write = $false; $l1 = $true; $l2 = $true
  (gc $vdf) |foreach { switch -regex ($_) {
    '\s+"SmallMode"\s+"1"'             { if ($l1) { $l1 = !1; $write = !1 } } # skip
    '\s+"SmallMode"\s+"0"'             { if ($l1) { $l1 = !1; $write = !0; [void]$t.Append("$SMA") } else { $write = !0 } }
    '\s+"LastPlayedTimesSyncTime"\s+"' { if ($l1) { $l1 = !1; $write = !0; [void]$t.Append("${SMA}$_`n") } } # insert before
    '\s+"PlayerLevel"\s+"'             { if ($l1) { $l1 = !1; $write = !0; [void]$t.Append("${SMA}$_`n") } }
    '\s+"LastInstallFolderIndex"\s+"'        { if ($l2) { $l2 = !1; [void]$t.Append("${LBM}$_`n") } }
    '\s+"FavoriteServersLastUpdateTime"\s+"' { if ($l2) { $l2 = !1; [void]$t.Append("${LBM}$_`n") } }
    '\s+"(LibraryLowBandwidthMode|LibraryLowPerfMode|LibraryDisableCommunityContent|LibraryDisplayIconInGameList)"\s+"' {}
    default { [void]$t.Append("$_`n") } 
  }}
  if ($write) { sc-nonew $vdf $t.ToString(); " $vdf" }
}

#_# AveYo: was this directly pasted into powershell? then we must save on disk
if (!$env:0 -or $env:0 -ne "$STEAM\steam_min.bat") {
  $0 = @('@(set ^ "0=%~f0" -des '') & powershell -nop -c iex(out-string -i (gc -lit $env:0)) & exit /b '');.{' +  
  ($MyInvocation.MyCommand.Definition) + '};$_press_Enter_if_pasted_in_powershell') -split'\r?\n'
  set-content "$STEAM\steam_min.bat" $0 -force
} 

#_# AveYo: refresh Steam_min desktop shortcut and startup run if enabled
$short = "$([Environment]::GetFolderPath('Desktop'))\Steam_min.lnk"
$s = (new-object -ComObject WScript.Shell).CreateShortcut($short)
if (-not (test-path $short) -or $s.Arguments -notmatch 'steam_min') {
  $s.Description = "$STEAM\steam.exe"; $s.IconLocation = "$STEAM\steam.exe,0" 
  $s.TargetPath = "conhost"; $s.Arguments = "--headless `"$STEAM\steam_min.bat`""; $s.Save()
}
$start = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (gp $start Steam -ea 0) { sp $start Steam "conhost --headless `"$STEAM\steam_min.bat`"" }

#_# AveYo: start Steam with quick launch options - now under explorer parent
ni "HKCU:\Software\Classes\.steam_min\shell\open\command" -force >''
sp "HKCU:\Software\Classes\.steam_min\shell\open\command" "(Default)" "`"$STEAM\steam.exe`" $QUICK"
if (!(test-path "$STEAM\.steam_min")) { set-content "$STEAM\.steam_min" "" }
start explorer -args "`"$STEAM\.steam_min`""
};$_press_Enter_if_pasted_in_powershell
