@(set ^ "0=%~f0" -des ') & powershell -nop -c iex(out-string -i (gc -lit $env:0)) & exit /b ');.{

" Steam_min : always starts in SmallMode with reduced ram usage when idle - AveYo, 2025.01.16 " 

$QUICK = '-silent -quicklogin -vgui -oldtraymenu -nofriendsui -no-dwrite -vrdisable -forceservice ' + 
         '-cef-force-browser-underlay -cef-delaypageload -cef-force-occlusion -cef-disable-gpu -cef-single-process'

$STEAM = resolve-path (gp "HKCU:\SOFTWARE\Valve\Steam" SteamPath -ea 0).SteamPath

#_# AveYo: enable Small Mode and library performance options
$sharedconfig = $true
dir "$STEAM\userdata\*\7\remote\sharedconfig.vdf" -Recurse |foreach {
  $vdf = $_; $t = new-object System.Text.StringBuilder; (gc $vdf) |foreach {
  if ($_ -match '\s+"SteamDefaultDialog"\s+"') {
    if ($_ -match '#app_games') { $sharedconfig = $false }
    [void]$t.Append("`t`t`t`t`"SteamDefaultDialog`"`t`t`"#app_games`"`n")
  } else { if ($sharedconfig) { [void]$t.Append("$_`n") } }  }
  if ($sharedconfig) { sc $vdf $t.ToString() -nonew -force -ea 0; " $vdf" }
} 

$localconfig = $true
$re = '\s+"(LibraryLowBandwidthMode|LibraryLowPerfMode|LibraryDisableCommunityContent|LibraryDisplayIconInGameList)"\s+"'
dir "$STEAM\userdata\*\config\localconfig.vdf" -Recurse |foreach {
  $vdf = $_; $t = new-object System.Text.StringBuilder; (gc $vdf) |foreach { if ($_ -notmatch $re) {
  if ($_ -match '\s+"SmallMode"\s+"') {
    if ($_ -match '"1"') { $localconfig = $false }
    [void]$t.Append("`t`t`t`t`"SmallMode`"`t`t`"1`"`n$_`n") 
  } elseif ($localconfig -and $_ -match '\s+"LastPlayedTimesSyncTime"\s+"') {
    [void]$t.Append("`t`t`t`t`"SmallMode`"`t`t`"1`"`n$_`n")
  } elseif ($localconfig -and $_ -match '\s+"FavoriteServersLastUpdateTime"\s+"') { 
    [void]$t.Append("`t`"LibraryDisableCommunityContent`"`t`t`"1`"`n`t`"LibraryDisplayIconInGameList`"`t`t`"0`"`n$_`n")
    [void]$t.Append("`t`"LibraryLowBandwidthMode`"`t`t`"1`"`n`t`"LibraryLowPerfMode`"`t`t`"1`"`n$_`n")
  } else { if ($localconfig) { [void]$t.Append("$_`n") } }  }}
  if ($localconfig) { sc $vdf $t.ToString() -nonew -force -ea 0; " $vdf" }
} 

#_# AveYo: was this directly pasted into powershell? then we must save on disk
if (!$env:0 -or $env:0 -ne "$STEAM\steam_min.bat") {
  $0 = @('@(set ^ "0=%~f0" -des '') & powershell -nop -c iex(out-string -i (gc -lit $env:0)) & exit /b '');.{' +  
  ($MyInvocation.MyCommand.Definition) + '};$_press_Enter_if_pasted_in_powershell') -split'\r?\n'
  sc "$STEAM\steam_min.bat" $0 -force
} 

#_# AveYo: refresh Steam_min desktop shortcut and startup run if enabled 
$short = "$([Environment]::GetFolderPath('Desktop'))\Steam_min.lnk"
$s = (new-object -ComObject WScript.Shell).CreateShortcut($short)
if (-not (test-path $short) -or $s.Arguments -notmatch 'steam_min.bat') {
  $s.Description = "$STEAM\steam.exe"; $s.IconLocation = "$STEAM\steam.exe,0" 
  $s.TargetPath = "conhost"; $s.Arguments = "--headless `"$STEAM\steam_min.bat`""; $s.Save()
}
$start = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (gp $start Steam -ea 0) { sp $start Steam "conhost --headless `"$STEAM\steam_min.bat`"" }

#_# AveYo: start Steam with quick launch options
powershell.exe -nop -c "Start-Process \`"$STEAM\steam.exe\`" \`"$QUICK\`""
};$_press_Enter_if_pasted_in_powershell
