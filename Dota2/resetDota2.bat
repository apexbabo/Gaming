@(set "0=%~f0"^)#) & powershell -nop -c iex([io.file]::ReadAllText($env:0)) & exit /b
#:: SAVE as .bat OR .ps1 / ENTER in powershell

$host.ui.RawUI.WindowTitle = "reset_Dota2" #:: 2024 v5 modernization: using powershell; keep hero grids
write-host
write-host "    INSTRUCTIONS:                                                                                   "
write-host " 1. Make sure you launch Dota 2 at least once with the account having troubles,                     "
write-host "    else this script will use the last logged on account                                            "
write-host " 2. Run this script - you might need to right-click it and Run as Administrator                     "
write-host " 3. After launching Dota 2, chose 'Local Save' at the Cloud Sync Conflict prompt then 'Play Anyway' "
write-host " 4. Adjust your settings, then restart Dota 2. Did it stick? Repeat procedure with Cloud On and Off "
write-host

$APPID      = 570
$APPNAME    = "dota2"
$INSTALLDIR = "dota 2 beta"
$MOD        = "dota"
$GAMEBIN    = "bin\win64"

#:: find steam and app
$STEAM = resolve-path (gp "HKCU:\SOFTWARE\Valve\Steam" SteamPath).SteamPath; $GAME = ''
gc "$STEAM\steamapps\libraryfolders.vdf" |foreach  {$_ -split '"',5} |where {$_ -like '*:\\*'} |foreach {
  $l = resolve-path $_; $i = "$l\steamapps\common\$INSTALLDIR"; if (test-path "$i\game\$MOD\steam.inf") {
  $STEAMAPPS = "$l\steamapps"; $GAMEROOT = "$i\game"; $GAME = "$i\game\$MOD"
}}

#:: detect per-user data path
pushd "$STEAM\userdata"
$CLOUD = split-path (dir -filter "localconfig.vdf" -Recurse | sort LastWriteTime -Descending | Select -First 1).DirectoryName
$USRLOCAL = "$USRCLOUD\$APPID\local"
popd

" STEAM = $STEAM`n GAME  = $GAME`n CLOUD = $CLOUD"
"`n $APPNAME will start automatically after a while ..."
timeout /t 10

function sc-nonew($fn,$txt) {
  if ((Get-Command set-content).Parameters['nonewline'] -ne $null) { set-content $fn $txt -nonewline -force }
  else { [IO.File]::WriteAllText($fn, $txt -join "`n") } # ps2.0
}

#:: force close steam & dota2
if (ps -name $APPNAME -ea 0) {"$APPNAME was running..."; kill -name $APPNAME -force}
if (ps -name 'steam' -ea 0) {"Steam was running..."; start "$steam\Steam.exe" -args '-shutdown' -wait; sleep 5 }
'steamwebhelper','steam' |% {kill -name $_ -force -ea 0} ; sleep 3; del "$STEAM\.crash" -force -ea 0

#:: clear verify integrity flags after a crash or generate empty manifest if missing
$appmanifest="$STEAMAPPS\appmanifest_$APPID.acf"
if (test-path $appmanifest) {
  $ACF = out-string -i (gc $appmanifest)
  if ($ACF -match '"FullValidateAfterNextUpdate"\s+"1"' -or $ACF -notmatch '"StateFlags"\s+"4"') {
    write-host " update or verify integrity flags detected, will clear them and restart Steam...`n" -fore Yellow
    'dota2','cs2','steamwebhelper','steam' |foreach {kill -name $_ -force -ea 0} ; sleep 3; del "$STEAM\.crash" -force -ea 0
    $ACF = $ACF -replace '("FullValidateAfterNextUpdate"\s+)("\d+")',"`$1`"0`"" -replace '("StateFlags"\s+)("\d+")',"`$1`"4`""
    if ($GAME) { sc-nonew $appmanifest $ACF }
  }
} else {
  write-host " $appmanifest missing or wrong lib path detected! continuing with a default manifest...`n" -fore Yellow
  $blank = "`"AppState`"`n{`n`"AppID`" `"$APPID`"`n`"Universe`" `"1`"`n`"installdir`" `"$INSTALLDIR`"`n`"StateFlags`" `"4`"`n}`n"
  if ($GAME) { sc-nonew $appmanifest $blank }
}

#:: clear cfg settings keeping autoexec.cfg
$cfg = ''; if (test-path "$GAME\cfg\autoexec.cfg") { $cfg = out-string -i (gc "$GAME\cfg\autoexec.cfg") }
rmdir -recurse "$GAME\cfg" -force -ea 0; mkdir "$GAME\cfg" -force -ea 0 >''
if ($cfg -ne '') { sc-nonew "$GAME\cfg\autoexec.cfg" $cfg }
$vcfg = "`"config`"`n{`n`t`"bindings`"`n`t{`n`t`t`t`"\`"`t`t`"toggleconsole`"`n`t}`n}`n"
sc-nonew "$GAME\cfg\user_keys_default.vcfg" $vcfg
rmdir -recurse "$GAME\core" -force -ea 0; del "$GAMEROOT\core\cfg\*.json","$GAMEROOT\core\cfg\*.bin" -force -ea 0

#:: clear cloud settings keeping hero grids, hero builds, control groups, hotkeys
takeown /f "$CLOUD" /r /d y >'' 2>''; icacls "$CLOUD" /reset /t /q >'' 2>''; attrib -r "$CLOUD" /s /d >'' 2>''
del "$CLOUD\$APPID\remotecache.vdf" -force -ea 0
pushd "$CLOUD\$APPID"
dir -recurse -file -exclude '*.png','*.jpg','dotakeys_personal.lst','control_groups.txt','herobuilds.cfg',
  'hero_grid_config.json'<#,'voice_ban.dt'#> |% { process { sc-nonew $_ '' } }

#:: clear shader and inventory cache
rmdir -recurse "$GAME\shadercache" -force -ea 0; mkdir "$GAME\shadercache" -force -ea 0 >''
rmdir -recurse "$STEAMAPPS\shadercache\$APPID" -force -ea 0
del "$GAME\cache_$(split-path $CLOUD -leaf)*.soc" -force -ea 0

#:: launch game
$quick = '-silent -quicklogin -vgui -oldtraymenu -nofriendsui -no-dwrite -vrdisable -forceservice -console ' + 
         '-cef-force-browser-underlay -cef-delaypageload -cef-force-occlusion -cef-disable-gpu -cef-single-process'
powershell.exe -nop -c "Start-Process \`"$STEAM\steam.exe\`" \`"$quick -applaunch $APPID \`""
