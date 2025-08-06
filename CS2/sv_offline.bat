@(set "0=%~f0" '& set 1=%*) & powershell -nop -c "type -raw -lit $env:0 | powershell -nop -c -" & exit /b ');.{

" CS2 Offline Server @ SEMU "

$SERVER_IP   = "127.0.0.1"
$LAUNCH_OPT  = "-dedicated +ip $SERVER_IP -port 27015 -snallownoauth -allow_no_lobby_connect +game_alias casual +map de_mirage " +
               "-steam -insecure -allow_third_party_software -nojoy -console -consolelog server"

$APPID       =  730
$APPNAME     = "cs2"
$INSTALLDIR  = "Counter-Strike Global Offensive"
$MOD         = "csgo"
$GAMEBIN     = "bin\win64"
$WINDOWTITLE = "Counter-Strike 2"
$CFG_KEYS    = "${APPNAME}_user_keys_0_slot0.vcfg"
$CFG_USER    = "${APPNAME}_user_convars_0_slot0.vcfg"
$CFG_MACHINE = "${APPNAME}_machine_convars.vcfg"
$CFG_VIDEO   = "${APPNAME}_video.txt"
$CFG_ENV     = "USRLOCALCSGO"
$title       = "CS2-EMU"
write-host

##  detect STEAM
$STEAM = resolve-path (gp "HKCU:\SOFTWARE\Valve\Steam").SteamPath
if (-not (test-path "$STEAM\steam.exe") -or -not (test-path "$STEAM\steamapps\libraryfolders.vdf")) {
  if (test-path "$env:appdata\SEMU\SteamPath") { $STEAM = resolve-path (gc -raw "$env:appdata\SEMU\SteamPath") }
  else { write-host " Steam not found! " -fore Black -back Yellow; sleep 7; return 1 }
}
mkdir "$env:appdata\SEMU" -ea 0 >''; set-content "$env:appdata\SEMU\SteamPath" $STEAM -nonew -force -ea 0

## AveYo: close steam if already running - gracefully first, then forced
function steam_close {
  param([string]$opt, [string]$reason, [bool]$y = $false)
  if ((gp "HKCU:\Software\Valve\Steam\ActiveProcess" -ea 0).pid -gt 0) {
    if ($reason) { write-host " closing Steam to $reason " }
    start "$STEAM\Steam.exe" -args "-ifrunning -silent $opt +app_stop $APPID -shutdown +quit now" -wait
    sp "HKCU:\Software\Valve\Steam\ActiveProcess" pid 0 -ea 0; $y = $true
  }
  while (gps -name steam -ea 0) {kill -name 'steamwebhelper','steam' -force -ea 0; del "$STEAM\.crash" -force -ea 0; $y = $true}
  return $y
}

##  AveYo: lean and mean helper functions to process steam vdf files
function vdf_parse {
  param([string[]]$vdf, [ref]$line = ([ref]0), [string]$re = '\A\s*("(?<k>[^"]+)"|(?<b>[\{\}]))\s*(?<v>"(?:\\"|[^"])*")?\Z')
  $obj = [ordered]@{}
  while ($line.Value -lt $vdf.count) {
    if ($vdf[$line.Value] -match $re) {
      if ($matches.k) { $key = $matches.k }
      if ($matches.v) { $obj[$key] = $matches.v }
      elseif ($matches.b -eq '{') { $line.Value++; $obj[$key] = vdf_parse -vdf $vdf -line $line -re $re}
      elseif ($matches.b -eq '}') { break }
    }
    $line.Value++
  }
  return $obj
}
function vdf_print {
  param($vdf, [ref]$indent = ([ref]0), $nested = ([ordered]@{}).gettype())
  if ($vdf -isnot $nested) {return}
  foreach ($key in $vdf.Keys) {
    if ($vdf[$key] -is $nested) {
      $tabs = "${\t}" * $indent.Value
      write-output "$tabs""$key""${\n}$tabs{${\n}"
      $indent.Value++; vdf_print -vdf $vdf[$key] -indent $indent -nested $nested; $indent.Value--
      write-output "$tabs}${\n}"
    } else {
      $tabs = "${\t}" * $indent.Value
      write-output "$tabs""$key""${\t}${\t}$($vdf[$key])${\n}"
    }
  }
}
function vdf_mkdir {
  param($vdf, [string]$path = ''); $s = $path.split('\',2); $key = $s[0]; $recurse = $s[1]
  if ($key -and $vdf.Keys -notcontains $key) { $vdf[$key] = [ordered]@{} }
  if ($recurse) { vdf_mkdir $vdf[$key] $recurse }
}
@{'\t'=9; '\n'=10; '\f'=12; '\r'=13; '\"'=34; '\$'=36}.getenumerator() | foreach {set $_.Name $([char]($_.Value)) -force}

function DOWNLOAD ($u, $f, $p = (get-location).Path) {
  $h = $u-replace 'https?:','http:'; $s = $u-replace 'https?:','https:'; if (!$f){$f = $u.Split('/')[-1]}; $file = join-path $p $f
  try {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]3072} catch {}
  $null = Import-Module BitsTransfer -ea 0; $wc = new-object Net.WebClient; $wc.Headers.Add('user-agent','ipad')
  foreach ($url in $h, $s) {
    if (([IO.FileInfo]$file).Length -gt 0) {return}; try {Invoke-WebRequest $url -OutFile $file} catch {}
    if (([IO.FileInfo]$file).Length -gt 0) {return}; try {Start-BitsTransfer $url $file -ea 1} catch {}
    if (([IO.FileInfo]$file).Length -gt 0) {return}; try {$wc.DownloadFile($url, $file)} catch {} ; $j = (Get-Date).Ticks
    if (([IO.FileInfo]$file).Length -gt 0) {return}; try {$null = bitsadmin /transfer $j /priority foreground $url $file} catch {}
  };if (([IO.FileInfo]$file).Length -gt 0) {return}; write-host -fore 0x7 "$f download failed"
}

function UNZIP ($file, $target = (get-location).Path) {
  if (-not (test-path $file)) {return 1} ; $f = resolve-path -lit $file; mkdir $target -ea 0 >''; $t = resolve-path -lit $target
  if (get-command Expand-Archivez -ea 0) {Expand-Archive "$f" "$t" -force -ea 0}
  else {$s=new-object -com shell.application; foreach($i in $s.NameSpace("$f").items()) {$s.Namespace("$t").copyhere($i,0x14)}}
}

if ((gp HKCU:\Software\Valve\Steam\ActiveProcess).SteamClientDll64 -notlike "*$env:appdata\SEMU*") {
  steam_close -reason "run under steam emulator"
} else {
  sp HKCU:\Software\Valve\Steam\ActiveProcess SteamClientDll64 "$STEAM\steamclient64.dll" -ea 0
  sp HKCU:\Software\Valve\Steam\ActiveProcess SteamClientDll "$STEAM\steamclient.dll" -ea 0
  sp HKCU:\Software\Valve\Steam\ActiveProcess SteamClientDll "$STEAM\steamclient.dll" -ea 0
  sp HKCU:\Software\Valve\Steam SteamExe "$STEAM\steam.exe" -ea 0
  sp HKCU:\Software\Valve\Steam SteamPath "$STEAM" -ea 0
}

## -------------------------------------------------------------------------------------------------------------------------------
##  detect active user from loginusers.vdf / latest localconfig.vdf
$file = "$STEAM\config\loginusers.vdf"
$USRID = 0
if ($USRID -lt 1) {
  $vdf = vdf_parse (gc $file -force -ea 0); if ($vdf.count -eq 0) {$vdf = vdf_parse @('"users"','{','}')}
  foreach ($id64 in $vdf[0].Keys) { if ($vdf[0][$id64]["MostRecent"] -eq '"1"') {
      $id3 = ([long]$id64) - 76561197960265728; $USRID = ($id3--,$id3)[($id3 % 2) -eq 0]
  } }
}
if ($USRID -lt 1) {
  pushd "$STEAM\userdata"
  $lconf = (dir -filter "localconfig.vdf" -Recurse | sort LastWriteTime -Descending | Select -First 1).DirectoryName
  $USRID = split-path (split-path $lconf) -leaf
  popd
}
$USRCLOUD = "$STEAM\userdata\$USRID"
$USRLOCAL = "$STEAM\userdata\$USRID\$APPID\local"
mkdir "$USRLOCAL\cfg" -ea 0 >''

##  detect APP folder
$file = "$STEAM\steamapps\libraryfolders.vdf"
$vdf = vdf_parse (gc $file -force -ea 0); if ($vdf.count -eq 0) {$vdf = vdf_parse @('"libraryfolders"','{','}')}
foreach ($nr in $vdf[0].Keys) {
  if ($vdf[0][$nr]["apps"] -and $vdf[0][$nr]["apps"]["$APPID"]) {
    $l = resolve-path $vdf[0][$nr]["path"].Trim('"'); $i = "$l\steamapps\common\$INSTALLDIR"
    if (test-path "$i\game\$MOD\steam.inf") { $STEAMAPPS = "$l\steamapps"; $GAMEROOT = "$i\game"; $GAME = "$i\game\$MOD" }
  }
}

$file = "$GAME\cfg\autoexec.cfg"; $add = "connect $SERVER_IP // CS2-EMU"
if (-not (test-path $file)) { set-content $file $add -force -ea 0 }
else { $txt = gc -lit $file | out-string; if ($txt -notmatch $add) { add-content $file $add -force -ea 0 } }

## -------------------------------------------------------------------------------------------------------------------------------
##  Valve broke offline play completely. Have to use a 3rd party emulator workaround
$emu = "$env:appdata\SEMU"
$env:CD  = split-path $env:0
$emu_url = "https://github.com/AveYo/Gaming/archive/1d0786fd115da47a2d0d96c613c0a509601f7d59.zip"
$emu_zip = "1d0786fd115da47a2d0d96c613c0a509601f7d59.zip"
$emu_cab = "semu.cab"
$emu_set = !1
'steamclient.dll','steamclient64.dll','steam.exe' | foreach {if (!(test-path "$emu\$_")) { $emu_set = !0 } }
mkdir "$emu" -ea 0 >''
pushd -lit $env:CD
if ($emu_set -and !(test-path $emu_cab)) {
  write-host -fore cyan -back black " One-time downloading 12.5MB SEMU from $emu_url "
  if (!(test-path $emu_zip)) { DOWNLOAD $emu_url $emu_zip }
  if (!(test-path $emu_zip)) { "ERROR! Manually download $emu_url and place next to this script" }
  if (test-path $emu_zip) {
    mkdir zip >''; UNZIP $emu_zip zip
    move "zip\Gaming-1d0786fd115da47a2d0d96c613c0a509601f7d59\CS2\semu.cab" "$env:CD\semu.cab" -ea 0
    rmdir zip -force -recurse -ea 0; del $emu_zip -force -ea 0
  }
  if (test-path $emu_cab) { expand -R $emu_cab -F:* "$emu" }
}

##  Import settings from steam cloud folder to emulator
robocopy "$USRLOCAL\cfg/" "$emu\$APPID\local\cfg/" *.* /J /NFL /NDL /NP /NJS /R:1 /W:0 /SJ /SL >'' # /E
(gc "$USRLOCAL\cfg\$CFG_USER") -join "`n" -match "`"name`"\s+`"([^`"]+)`"" >''
$emu_name = 'Gaben'; if ($matches) { $emu_name = $matches[1] }
$emu_id64 = 76561197960265728  + [int64](split-path $USRCLOUD -leaf)

mkdir "$emu\settings" -ea 0 >''
set-content "$emu\settings\account_name.txt" "$emu_name" -force -ea 0
set-content "$emu\settings\language.txt" "english" -force -ea 0
set-content "$emu\settings\listen_port.txt" "47584" -force -ea 0
set-content "$emu\settings\user_steam_id.txt" "$emu_id64" -force -ea 0
mkdir "$emu\steam_settings" -ea 0 >''
del "$emu\steam_settings\*.*" -force -ea 0 >''

#set-content "$emu\steam_settings\gc_token.txt" "yes" -force -ea 0
#set-content "$emu\steam_settings\offline.txt" "yes" -force -ea 0
#set-content "$emu\steam_settings\disable_overlay.txt" "yes" -force -ea 0

## -------------------------------------------------------------------------------------------------------------------------------
set-content "$emu\steam_settings\configs.main.ini" @"
[main::general]
# 1=generate newer version of auth ticket, used by some modern apps
# default=0
new_app_ticket=1
# 1=generate/embed Game Coordinator token inside the new auth ticket
# default=0
gc_token=1

[main::connectivity]
# 1=prevent hooking OS networking APIs and allow any external requests
# only used by the experimental builds on **Windows**
# default=0
disable_lan_only=0
# 1=disable all steam networking interface functionality
# this won't prevent games/apps from making external requests
# networking related functionality like lobbies or those that launch a server in the background will not work
# default=0
disable_networking=0
# change the UDP/TCP port the emulator listens on, you should probably not change this because everyone needs to use the same port
# default=47584
listen_port=47584
# 1=pretend steam is running in offline mode, mainly affects the function `ISteamUser::BLoggedOn()`
# Some games that connect to online servers might only work if the steam emu behaves like steam is in offline mode
# default=0
offline=0
# 1=prevent sharing stats and achievements with any game server, this also disables the interface ISteamGameServerStats
# default=0
disable_sharing_stats_with_gameserver=0
# 1=do not send server details to the server browser, only works for game servers
# default=0
disable_source_query=0
# 1=enable sharing leaderboards scores with people playing the same game on the same network
# not ideal and synchronization isn't perfect
# default=0
share_leaderboards_over_network=0
# 1=prevent lobby creation in the steam matchmaking interface
# default=0
disable_lobby_creation=0
# 1=attempt to download external HTTP(S) requests made via Steam_HTTP::SendHTTPRequest() inside "steam_settings/http/"
# make sure to:
# * set disable_lan_only=1
# * set disable_networking=0
# this will **not** work if the app is using native/OS web APIs
# default=0
download_steamhttp_requests=0
"@  -force -ea 0

## -------------------------------------------------------------------------------------------------------------------------------
set-content "$emu\steam_settings\configs.user.ini" @"
[user::general]
# user account name
account_name=$emu_name
# the language reported to the app/game, https://partner.steamgames.com/doc/store/localization/languages
language=english
# Steam64 format
account_steamid=$emu_id64
# report a country IP if the game queries it
ip_country=RO

[user::saves]
# name of the base folder used to store save data, leading and trailing whitespaces are trimmed
saves_folder_name=SEMU
"@  -force -ea 0

## -------------------------------------------------------------------------------------------------------------------------------
set-content "$emu\ColdClientLoader.ini" @"
# modified version of ColdClientLoader originally by Rat431
[SteamClient]
# path to game exe, absolute or relative to the loader
Exe=$GAMEROOT\$GAMEBIN\$APPNAME.exe
# empty means the folder of the exe
ExeRunDir=
# any additional args to pass, ex: -dx11, also any args passed to the loader will be passed to the app
ExeCommandLine=$LAUNCH_OPT
# IMPORTANT, unless [Persistence] Mode=2
AppId=$APPID

# path to the steamclient dlls, both must be set,
# absolute paths or relative to the loader
SteamClientDll=steamclient.dll
SteamClient64Dll=steamclient64.dll

[Injection]
# force inject steamclient dll instead of waiting for the app to load it
ForceInjectSteamClient=0

# force inject GameOverlayRenderer dll instead of waiting for the app to load it
ForceInjectGameOverlayRenderer=0

# path to a folder containing some dlls to inject into the app upon start, absolute path or relative to this loader
# this folder will be traversed recursively
# additionally, inside this folder you can create a file called `load_order.txt` and
# specify line by line the order of the dlls that have to be injected
# each line should be the relative path of the target dll, relative to the injection folder
# If this file is created then the loader will only inject the .dll files mentioned inside it
# example:
#DllsToInjectFolder=extra_dlls
DllsToInjectFolder=

# don't display an error message when a dll injection fails
IgnoreInjectionError=1
# don't display an error message if the architecture of the loader is different from the app
# this will result in a silent failure if a dll injection didn't succeed
# both the loader and the app must have the same arch for the injection to work
IgnoreLoaderArchDifference=0

[Persistence]
# 0 = turned off
# 1 = loader will spawn the exe and keep hanging in the background until you press "OK"
# 2 = loader will NOT spawn exe, it will just setup the required environemnt and keep hanging in the background
#     you have to run the Exe manually, and finally press "OK" when you've finished playing
#     you have to rename the loader to "steam.exe"
#     it is advised to run the loader as admin in this mode
Mode=0

[Debug]
# don't call `ResumeThread()` on the main thread after spawning the .exe
ResumeByDebugger=0
"@ -force

## -------------------------------------------------------------------------------------------------------------------------------
" GAME = $GAMEROOT\$GAMEBIN\$APPNAME.exe "
" OPT  = $LAUNCH_OPT "
" CFG  = $USRLOCAL "

##  start emulator
start "$emu\steam.exe"

} @args #_press_Enter_if_pasted_in_powershell
