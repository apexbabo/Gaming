<# ::
@echo off & set "0=%~f0"& set 1=%1& start "@" conhost powershell -nop -c iex(gc -lit $env:0 -raw) & exit /b
#>.{

<#
  Counter-Strike 2 launcher - AveYo, 2025.04.14  Major update
  sets desktop resolution to match the game while in focus, then quickly restores native on alt-tab
  this alleviates most alt-tab and secondary screen issues, crashes on startup and high input lag
  Hint: confirm your game is switching to the proper mode (W I T) via Nvidia Frameview (works on any gpu)
  + only switches res on alt-tab or task manager, ignoring windows on other screens, winkey or winkey + D
  + game starts on screen with mouse pointer on; seamlessly move between displays while game menu is active
  + clear steam verify game integrity after a crash to relaunch quicker; add script shortcuts to steam library
  + unify settings for all users in game\csgo\cfg dir (and helps preserve settings when offline)
  + force specific video settings and cvars at every launch; export game net info to console.log on Desktop
#>

##  override resolution: no -1 max 0 |  if not appearing in res list, create the custom res in gpu driver settings / cru
##  fast custom res for [4:3] = 1080x810  1280x960  1440x1080   [16:10] = 1296x810  1440x900   [16:9] = 1440x810  1632x918
$force_width     = -1
$force_height    = -1
$force_refresh   = -1

##  override settings with the preset below: yes 1 no 0 | prefix with # to keeps lines unchanged (adjust those in-game)
$force_settings  = 1

$video = @{                                                          ##        Shadow of a Potato preset        more jpeg:
  "setting.mat_vsync"                                = "0"           ##  0     enable vsync in gpu driver instead
# "setting.msaa_samples"                             = "0"           ##  2     should enable AA when using FSR           0
# "setting.r_csgo_cmaa_enable"                       = "0"           ##  0     use msaa 2 instead
# "setting.videocfg_shadow_quality"                  = "0"           ##  0     shadows high: 2 | med: 1 | low: 0
  "setting.videocfg_dynamic_shadows"                 = "1"           ##  1     must have for competitive play            0
# "setting.videocfg_texture_detail"                  = "0"           ##  0     texture high: 2 | med: 1 | low: 0
# "setting.r_texturefilteringquality"                = "3"           ##  3     anyso16x: 5 | anyso4x: 3 | trilinear: 1   0
# "setting.shaderquality"                            = "0"           ##  0     smooth shadows fps--
# "setting.videocfg_particle_detail"                 = "0"           ##  0     smooth smokes fps--
# "setting.videocfg_ao_detail"                       = "0"           ##  0     ambient oclussion fps--
# "setting.videocfg_hdr_detail"                      = "3"           ##  -1    HDR quality: -1 | performance 8bit noise: 3
# "setting.videocfg_fsr_detail"                      = "0"           ##  0     FSR quality: 2 | balanced: 3 | minecraft: 4
# "setting.r_low_latency"                            = "2"           ##  1
}
$convars = @{
# "r_fullscreen_gamma"                               = "2.2"         ##  2.2   brightness slider - works on windowed too
# "r_player_visibility_mode"                         = "0"           ##  1     kinda useless
# "r_drawtracers_firstperson"                        = "0"           ##  1     tracers
  "engine_no_focus_sleep"                            = "0"           ##  20    power saving while alt-tab
  "cl_input_enable_raw_keyboard"                     = "0"           ##  0     prevent keyboard issues
  "r_show_build_info"                                = "1"           ##  1     build info is a must when reporting issues
# "trusted_launch"                                   = "1"           ##  1     trusted launch tracking
}
$extra_launch_options = @()
#$extra_launch_options+= '-consolelog'                               ##  uncomment to filter net info to Desktop\console.log
#$extra_launch_options+= '-allow_third_party_software'               ##  uncomment if recording via obs game capture
#$extra_launch_options+= '-noreflex -noantilag'                      ##  uncomment if frametime issues - can be deceiving 

##  override screen or use current -1 | this is 1st number in the screen list; second number is for -sdl_displayindex
$force_screen    = -1

##  override fullscreen mode: exclusive 1 desktop-friendly 0
$force_exclusive = 0

##  override fullscreen optimizations (FSO): enable 1 disable 0
$enable_fso      = 1

##  unify settings for all users in game\csgo\cfg dir: yes 1 no 0
$unify_cfg       = 1

##  non-steam game entry for the script: yes 1 no 0
$add_to_library  = 1

##  whether start the game directly: 1 or wait for manual launch: 0 (if using faceit gamersclub br etc)
$auto_start      = 1

##  override script handling or use default 0
$do_not_restore_res_use_max_available = 0

##  main script section -------------------------------------------------------------------- switch syntax highlight to powershell
$APPID       =  730
$APPNAME     = "cs2"
$INSTALLDIR  = "Counter-Strike Global Offensive"
$MOD         = "csgo"
$GAMEBIN     = "bin\win64"
$WINDOWTITLE = "Counter-Strike 2"
$RUNNING     = "\\Software\\Valve\\Steam\\Apps\\$APPID/Running"
$CFG_KEYS    = "${APPNAME}_user_keys_0_slot0.vcfg"
$CFG_USER    = "${APPNAME}_user_convars_0_slot0.vcfg"
$CFG_MACHINE = "${APPNAME}_machine_convars.vcfg"
$CFG_VIDEO   = "${APPNAME}_video.txt"
$CFG_ENV     = "USRLOCALCSGO"
$scriptname  = "CS2_Launcher"
$scriptdate  =  20250414

##  whether start the game directly or wait for manual launch (if using faceit gamersclub br etc)
if ($env:1 -match '-auto') { $auto_start = 1 } elseif ($env:1 -match '-manual') { $auto_start = 0 } 

##  detect STEAM
$STEAM = resolve-path (gp "HKCU:\SOFTWARE\Valve\Steam").SteamPath
if (-not (test-path "$STEAM\steam.exe") -or -not (test-path "$STEAM\steamapps\libraryfolders.vdf")) {
  write-host " Steam not found! " -fore Black -back Yellow; timeout -1; exit 0
}

##  AveYo: lean and mean helper functions to process steam vdf files -------------------------------------------------------------
function vdf_parse {
  param([string[]]$vdf, [ref]$line=([ref]0), [string]$r='\A\s*("(?<k>[^"]+)"|(?<b>[\{\}]))\s*(?<v>"(?:\\"|[^"])*")?\Z') #
  $obj = new-object System.Collections.Specialized.OrderedDictionary # ps 3.0: [ordered]@{}
  while ($line.Value -lt $vdf.count) {
    if ($vdf[$line.Value] -match $r) {
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
  param($vdf, [ref]$indent=([ref]0))
  if ($vdf -isnot [System.Collections.Specialized.OrderedDictionary]) {return}
  foreach ($key in $vdf.Keys) {
    if ($vdf[$key] -is [System.Collections.Specialized.OrderedDictionary]) {
      $t = "`t" * $indent.Value
      write-output "$t`"$key`"`n$t{`n"
      $indent.Value++; vdf_print -vdf $vdf[$key] -indent $indent; $indent.Value--
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

##  detect active user from registry / loginusers.vdf / latest localconfig.vdf ---------------------------------------------------
$USRID = (gp "HKCU:\Software\Valve\Steam\ActiveProcess" -ea 0).ActiveUser
if ($USRID -lt 1) {
  $file = "$STEAM\config\loginusers.vdf"; $vdf = vdf_parse (gc $file -force)
  foreach ($id64 in $vdf["users"].Keys) { if ($vdf["users"][$id64]["MostRecent"] -eq '"1"') {
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

##  detect APP folder
$file = "$STEAM\steamapps\libraryfolders.vdf"; $vdf = vdf_parse (gc $file -force)
foreach ($nr in $vdf["libraryfolders"].Keys) {
  if ($vdf["libraryfolders"][$nr]["apps"] -and $vdf["libraryfolders"][$nr]["apps"]["$APPID"]) {
    $l = resolve-path $vdf["libraryfolders"][$nr]["path"].Trim('"'); $i = "$l\steamapps\common\$INSTALLDIR"
    if (test-path "$i\game\$MOD\steam.inf") { $STEAMAPPS = "$l\steamapps"; $GAMEROOT = "$i\game"; $GAME = "$i\game\$MOD" }
  }
}

##  was this pasted directly into powershell? then save on disk ------------------------------------------------------------------
if (!$env:0 -or $env:0 -ne "$GAMEROOT\$scriptname.bat" -or $scriptdate -gt 20250414) {
  $f0 = @("<# ::`n"+'@echo off & set "0=%~f0"& set 1=%1& start "@" conhost powershell -nop -c iex(gc -lit $env:0 -raw) & exit /b'+
        "`n#>.{"+($MyInvocation.MyCommand.Definition)+"};`$_press_Enter_if_pasted_in_powershell") -split'\r?\n'
  set-content "$GAMEROOT\$scriptname.bat" $f0 -force
}

##  close previous instances
$c = 'HKCU:\Console\@'; ni $c -ea 0 >''; sp $c ScreenColors 0x0b -type dword -ea 0; sp $c QuickEdit 0 -type dword -ea 0
ps | where {$_.MainWindowTitle -eq "$scriptname"} | kill -force -ea 0; [Console]::Title = "$scriptname"

##  clear verify integrity flags after a crash for quicker relaunch --------------------------------------------------------------
$appmanifest="$STEAMAPPS\appmanifest_$APPID.acf"
if (test-path $appmanifest) {
  $vdf = vdf_parse (gc $appmanifest -force); $write = $false
  if ($vdf["AppState"]["StateFlags"] -ne '"4"') { $vdf["AppState"]["StateFlags"]='"4"'; $write = $true }
  if ($vdf["AppState"]["FullValidateAfterNextUpdate"]) { $vdf["AppState"]["FullValidateAfterNextUpdate"]='"0"'; $write = $true }
  if ($write) {
    if ((gp "HKCU:\Software\Valve\Steam\ActiveProcess" -ea 0).ActiveUser -gt 0) {
      start "$STEAM\Steam.exe" -args "+app_stop $APPID +app_mark_validation $APPID 0 -shutdown" -wait; sleep 5
      kill -name "$APPNAME","steam","steamwebhelper" -force -ea 0; del "$STEAM\.crash" -force -ea 0
    }
    sc-nonew $appmanifest (vdf_print $vdf)
  }
}

##  unify settings for all users in game\csgo\cfg dir via roaming profile environment variable -----------------------------------
$ENV_M = [Environment]::GetEnvironmentVariable($CFG_ENV,2)
if ($ENV_M) {
  write-host " $CFG_ENV env is defined at machine level. unable to override cfg location" -fore Yellow
  $CFG_KEYS,$CFG_USER,$CFG_MACHINE,$CFG_VIDEO |foreach {
    if (-not (test-path "$ENV_M\cfg\$_")) { robocopy "$USRCLOUD\$APPID\local\cfg/" "$ENV_M\cfg/" $_ /XO >'' }
  }
  $USRLOCAL = "$ENV_M"
  0,1 |foreach { [Environment]::SetEnvironmentVariable($CFG_ENV,"",$_) }
}
$ENV_U = [Environment]::GetEnvironmentVariable($CFG_ENV,1)
if ($ENV_U -and $ENV_U -ne "$GAME" -and ((gp "HKCU:\Software\Valve\Steam\ActiveProcess" -ea 0).ActiveUser -gt 0)) {
  write-host " closing Steam to refresh $CFG_ENV env " -fore Yellow
  start "$STEAM\Steam.exe" -args '-shutdown' -wait; sleep 5
}
if ($ENV_U) {
  $CFG_KEYS,$CFG_USER,$CFG_MACHINE,$CFG_VIDEO |foreach {
    if (test-path "$ENV_U\cfg\$_") { robocopy "$ENV_U\cfg/" "$GAME\cfg/" $_ /XO >'' }
    if (-not (test-path "$GAME\cfg\$_")) { robocopy "$USRCLOUD\$APPID\local\cfg/" "$GAME\cfg/" $_ /XO >'' }
  }
  $USRLOCAL = "$GAME"
}
if (!$ENV_M) { 0,1 |foreach { [Environment]::SetEnvironmentVariable($CFG_ENV,("","$GAME")[$unify_cfg -eq 1],$_) } }
$CFG_VIDEO_FILE = "$USRLOCAL\cfg\$CFG_VIDEO"

##  decide which sets of video options override to use: cfg -> launch options -> script ------------------------------------------
$exclusive = 0; $screen = 0; $width = 0; $height = 0; $refresh = 0; $numer = -1; $denom = -1

##  parse video txt file
$file = "$CFG_VIDEO_FILE"; if (test-path $file) {
  $vdf = vdf_parse (gc $file -force); $cfg = $vdf["video.cfg"]
  if ($cfg["setting.fullscreen"] -match '"([^"]*)"')              { $exclusive = [int]$matches[1] }
  if ($cfg["setting.monitor_index"] -match '"([^"]*)"')           { $screen    = [int]$matches[1] }
  if ($cfg["setting.defaultres"] -match '"([^"]*)"')              { $width     = [int]$matches[1] }
  if ($cfg["setting.defaultresheight"] -match '"([^"]*)"')        { $height    = [int]$matches[1] }
  if ($cfg["setting.refreshrate_numerator"] -match '"([^"]*)"')   { $numer     = [int]$matches[1] }
  if ($cfg["setting.refreshrate_denominator"] -match '"([^"]*)"') { $denom     = [int]$matches[1] }
  ##  compute numerator / denominator = refresh for video txt file
  if ($numer -gt 0 -and $denom -gt 0) { $refresh = [decimal]$numer / $denom }
}

##  parse game launch options
$file = "$USRCLOUD\config\localconfig.vdf"; $vdf = vdf_parse (gc $file -force)
vdf_mkdir $vdf "UserLocalConfigStore\Software\Valve\Steam\Apps\$APPID"
$lo = $($vdf["UserLocalConfigStore"]["Software"]["Valve"]["Steam"]["Apps"]["$APPID"]["LaunchOptions"]).Trim('"')
if ($lo -ne '') {
  if ($lo -match '-fullscreen\s?')            { $exclusive = 1 }
  if ($lo -match '-sdl_displayindex\s+(\d+)') { $screen    = [int]$matches[1] }
  if ($lo -match '-w(idth)?\s+(\d+)')         { $width     = [int]$matches[2] }
  if ($lo -match '-h(eight)?\s+(\d+)')        { $height    = [int]$matches[2] }
  if ($lo -match '-r(efresh)?\s+([\d.]+)')    { $refresh   = [decimal]$matches[2] }
}

##  script overrides
if ($force_exclusive -ge 0) { $exclusive = $force_exclusive }
if ($force_screen -ge 0)    { $screen    = $force_screen }
if ($force_width -ge 0)     { $width     = $force_width }
if ($force_height -ge 0)    { $height    = $force_height }
if ($force_refresh -ge 0)   { $refresh   = $force_refresh }
if ($refresh -gt 0) {
  $hz = ([string]$refresh).Split('.'); $denom = 1000
  if ($hz.length -eq 2) { $numer = [int]($hz[0] + $hz[1].PadRight(3,'0')) } else { $numer = [int]($hz[0] + "000") }
}

##  SetRes lib dynamically sets game res to desktop, to alleviate input lag, alt-tab and secondary screens issues ----------------
##  Init  (screen) returns array of sdl monitor index, windows screen index, is primary, number of displays
##  Focus (verbose=1, window_title, video_cfg, running_reg, def_nr, def_width, def_height, def_refresh)
##  Change(verbose=0:none 1:def, screen, width, height, refresh=0:def, test=0:change 1:test)
##  List  (verbose=0:none 1:filter 2:all, screen, minw=1024, maxw=16384, maxh=16384)
##  returns array of: sdl_idx, screen, current_width, current_height, current_refresh, max_width, max_height, max_refresh
##  C# typefinition at the end of the script gets pre-compiled once here rather than let powershell do it slowly every launch
$library1 = "SetRes"; $version1 = "2025.4.14.0"; $about1 = "match game and desktop res"; $path1 = "$GAMEROOT\$library1.dll"
if ((gi $path1 -force -ea 0).VersionInfo.FileVersion -ne $version1) { del $path1 -force -ea 0 } ; if (-not (test-path $path1)) {
  mkdir "$GAMEROOT" -ea 0 >'' 2>''; pushd $GAMEROOT; " one-time initialization of $library1 library..."
  set-content "$GAMEROOT\$library1.cs" $(($MyInvocation.MyCommand.Definition -split '<#[:]LIBRARY1[:].*')[1])
  $clr = $PSVersionTable.PSVersion.Major; if ($clr -gt 4) { $clr = 4 }; $framework = "$env:SystemRoot\Microsoft.NET\Framework"
  $csc = (dir $framework -filter "csc.exe" -Recurse |where {$_.PSPath -like "*v${clr}.*"}).FullName
  start $csc -args "/out:$library1.dll /target:library /platform:anycpu /optimize /nologo $library1.cs" -nonew -wait; popd
}
try {Import-Module $path1} catch {del $path1 -force -ea 0; " ERROR importing $library1, run script again! "; timeout -1; return}

##  should call Init() first
$display = [AveYo.SetRes]::Init($screen)
$sdl_idx = $display[0];  $screen = $display[1];  $primary = $display[2] -gt 0;  $multimon = $display[3] -gt 1

##  restore previous resolution if game was not gracefully closed last time ------------------------------------------------------
if ($env:SetResBack) {
  $restore = $env:SetResBack -split ','
  if ((gp "HKCU:\Software\Valve\Steam\Apps\$APPID" -ea 0).Running -lt 1) {
    $c = [AveYo.SetRes]::Change(0, $restore[1], $restore[2], $restore[3], $restore[4])
    0,1 |foreach { [Environment]::SetEnvironmentVariable("SetResBack","",$_) }
  }
}

##  SetRes automatically picks a usable mode if the change is invalid so result might differ from the request --------------------
$oldres  = [AveYo.SetRes]::List(1, $screen)
if ($width   -le 0) { $width  = $oldres[2] }
if ($height  -le 0) { $height = $oldres[3] }
if ($refresh -le 0) { $max_refresh = [AveYo.SetRes]::List(0, $screen, $width, $width, $height); $refresh = $max_refresh[7] }
$newres  = [AveYo.SetRes]::Change(1, $screen, $width, $height, $refresh, 1)
$width   = $newres[5]; $restore_width   = $newres[2]
$height  = $newres[6]; $restore_height  = $newres[3]
$refresh = $newres[7]; $restore_refresh = $newres[4]
if ($do_not_restore_res_use_max_available -ge 1) {
  $restore_width = $oldres[5]; $restore_height = $oldres[6]; $restore_refresh = $oldres[7]
}
$sameres = $width -eq $restore_width -and $height -eq $restore_height -and $refresh -eq $restore_refresh
$ratio   = $width / $height
if ($ratio -le 4/3) {$ar = 0} elseif ($ratio -le 16/10) {$ar = 2} elseif ($ratio -le 16/8.9) {$ar = 1} else {$ar = 3}
$mode = "$width x ".PadLeft(7) + "$height ".Padleft(5) + "${refresh}Hz".PadLeft(5)
$rend = ('Desktop-friendly','Exclusive')[$exclusive -gt 0]; if ($enable_fso -gt 0) { $rend += ' + FSO' }
$video_full = ('-coop_fullscreen','-fullscreen')[$exclusive -ge 1]
$video_mode = "$video_full -width $width -height $height -refresh $refresh -sdl_displayindex $sdl_idx "

##  many thanks to /u/wazernet for testing and suggestions in 2024
write-host " $screen $mode $rend mode requested" -fore Yellow
write-host " $video_mode" -fore Green
write-host " $CFG_VIDEO_FILE" -fore Gray
write-host " $GAME\cfg\autoexec.cfg" -fore Gray

##  update video overrides in case the initial mode was invalid and SetRes applied a fallback ------------------------------------
if ($force_settings -le 0) { $video = @{} }
$video["setting.fullscreen"]                   = (0,1)[$exclusive -eq 1]
$video["setting.coop_fullscreen"]              = (0,1)[$exclusive -ne 1]
$video["setting.nowindowborder"]               = 1
$video["setting.fullscreen_min_on_focus_loss"] = 0
$video["setting.high_dpi"]                     = 1
$video["setting.defaultres"]                   = $width
$video["setting.defaultresheight"]             = $height
$video["setting.refreshrate_numerator"]        = $refresh
$video["setting.refreshrate_denominator"]      = 1
$video["setting.monitor_index"]                = $sdl_idx
$video["setting.aspectratiomode"]              = $ar

##  update cfg files with the overrides
$file = "$CFG_VIDEO_FILE"
if (-not (test-path $file)) { sc-nonew $file "`"video.cfg`"`n{`n`t`"Version`"`t`t`"13`"`n}`n" }
$vdf = vdf_parse (gc $file -force); $cfg = $vdf["video.cfg"]
foreach ($k in $video.Keys) { $cfg[$k] = "`"$($video.$k)`"" }
sc-nonew $file (vdf_print $vdf)

$file = "$GAME\cfg\launcher.cfg"; $cfg = new-object System.Text.StringBuilder
foreach ($k in $convars.Keys) { [void]$cfg.AppendLine("`"$k`" `"$($convars.$k)`"") }
set-content $file $cfg.ToString() -force -ea 0

$file = "$GAME\cfg\autoexec.cfg"; $add = "execifexists launcher // $APPNAME_Launcher convars"
if (-not (test-path $file)) { [io.file]::writealltext($file, $add) }
else { $cfg = [io.file]::readalltext($file); if ($cfg -notmatch $add) { [io.file]::writealltext($file, "$add`r`n" + $cfg) } }

##  apply video launch options if different - must shutdown steam for it
$file = "$USRCLOUD\config\localconfig.vdf"; $vdf = vdf_parse (gc $file -force); $write = $false
vdf_mkdir $vdf "UserLocalConfigStore\Software\Valve\Steam\Apps\$APPID"
$lo = ($vdf["UserLocalConfigStore"]["Software"]["Valve"]["Steam"]["Apps"]["$APPID"]["LaunchOptions"]).Trim('"')
if ($lo -ne '') {
  $__c = '-coop_fullscreen\s?';            if ($lo -match $__c) { $lo = $lo -replace $__c }
  $__f = '-fullscreen\s?';                 if ($lo -match $__f) { $lo_f = 1; $lo = $lo -replace $__f }
  $__s = '-sdl_displayindex\s+?(\d+)?\s?'; if ($lo -match $__s) { $lo_s = $matches[1]; $lo = $lo -replace $__s }
  $__w = '-w(idth)?\s+?(\d+)?\s?';         if ($lo -match $__w) { $lo_w = $matches[2]; $lo = $lo -replace $__w }
  $__h = '-h(eight)?\s+?(\d+)?\s?';        if ($lo -match $__h) { $lo_h = $matches[2]; $lo = $lo -replace $__h }
  $__r = '-r(efresh)?\s+?([\d.]+)?\s?';    if ($lo -match $__r) { $lo_r = $matches[2]; $lo = $lo -replace $__r }
  if (($lo_f -and $exclusive -ne 1) -or ($lo_s -and $lo_s -ne $sdl_idx) -or
      ($lo_w -and $lo_w -ne $width) -or ($lo_h -and $lo_h -ne $height) -or ($lo_r -and $lo_r -ne $refresh)) { $write = $true } 
}
$lo = ("$video_mode $extra_launch_options " + $lo) -replace '\s+',' '
$vdf["UserLocalConfigStore"]["Software"]["Valve"]["Steam"]["Apps"]["$APPID"]["LaunchOptions"] = "`"$lo`""
if ($write) {
  if ((gp "HKCU:\Software\Valve\Steam\ActiveProcess" -ea 0).ActiveUser -gt 0) {
    start "$STEAM\Steam.exe" -args "+app_stop $APPID +app_mark_validation $APPID 0 -shutdown" -wait; sleep 5
    kill -name "$APPNAME","steam","steamwebhelper" -force -ea 0; del "$STEAM\.crash" -force -ea 0
  }
  sc-nonew $file (vdf_print $vdf)
}

##  add scriptname entries to Steam library --------------------------------------------------------------------------------------
$file = "$USRCLOUD\config\shortcuts.vdf"; $bvdf = [io.file]::readalltext($file); $next = ($bvdf -split "AppName").count - 1
$icon = "$GAMEROOT\bin\win64\$APPNAME.exe"; $conhost = "$env:systemroot\sysnative\conhost.exe"
$0 = [char]0; $1 = [char]1; $2 = [char]2; $8 = [char]8
foreach ($start in "-auto","-manual") {
  $geid = [Text.Encoding]::GetEncoding(28591).GetString([BitConverter]::GetBytes([AveYo.SetRes]::GenAppId("$scriptname $start")))
  $text = ($0 + "$next++$0") + ($2 + "appid$0" + "$geid") + ($1 + "AppName$0" + "$scriptname $start$0") +
   ($1 + "Exe$0" + "$conhost$0") + ($1 + "StartDir$0" + $0) + ($1 + "icon$0" + "$icon$0") + ($1 + "ShortcutPath$0" + $0) +
   ($1 + "LaunchOptions$0" + "`"$GAMEROOT\$scriptname.bat`" $start$0") + ($2 + "IsHidden$0" + "$0$0$0$0") + 
   ($2 + "AllowDesktopConfig$0" + "$0$0$0$0") + ($2 + "AllowOverlay$0" + "$0$0$0$0") + ($2 + "OpenVR$0" + "$0$0$0$0") +
   ($2 + "Devkit$0" + "$0$0$0$0") + ($1 + "DevkitGameID$0" + $0) + ($2 + "DevkitOverrideAppID$0" + "$0$0$0$0") +
   ($2 + "LastPlayTime$0" + "$0$0$0$0") + ($1 + "FlatpakAppID$0" + $0) + ($0 + "tags$0") + ($1 + "0$0" + "AveYo$0") + "$8$8$8$8"
  if ($add_to_library -gt 0 -and $bvdf -notmatch "$scriptname -") {
    if ((gp "HKCU:\Software\Valve\Steam\ActiveProcess" -ea 0).ActiveUser -gt 0) {
      start "$STEAM\Steam.exe" -args "+app_stop $APPID -shutdown" -wait; sleep 5
      kill -name "$APPNAME","steam","steamwebhelper" -force -ea 0; del "$STEAM\.crash" -force -ea 0
    }
    $link = ([io.file]::readallbytes($file) | select -skiplast 2) + [Text.Encoding]::GetEncoding(28591).GetBytes($text)
    [io.file]::writeallbytes($file, $link)
  }
}

##  toggle fullscreen optimizations for game launcher - FSO as a concept is an abomination ---------------------------------------
$progr = "$GAMEROOT\$GAMEBIN\$APPNAME.exe"
$flags = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$found = (gi $flags -ea 0).Property -contains $progr
$valid = $found -and (gp $flags)."$progr" -like '*DISABLEDXMAXIMIZEDWINDOWEDMODE*'
if ($enable_fso -eq 0 -and (!$found -or !$valid)) {
  write-host " disabling $APPNAME os fullscreen (un)optimizations"
  if ($GAME) { ni $flags -ea 0; sp $flags $progr '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE' -force -ea 0 }
}
if ($enable_fso -eq 1 -and $valid) {rp $flags $progr -force -ea 0}

##  backup current mode ----------------------------------------------------------------------------------------------------------
[Environment]::SetEnvironmentVariable("SetResBack", "$sdl_idx,$screen,$restore_width,$restore_height,$restore_refresh", 1)

##  prepare steam quick options
$quick = '-silent -quicklogin -vgui -oldtraymenu -nofriendsui -no-dwrite -vrdisable -forceservice -console ' + 
         '-cef-force-browser-underlay -cef-delaypageload -cef-force-occlusion ' +
         '-cef-single-process -cef-in-process-gpu -cef-disable-gpu-compositing -cef-disable-gpu' 
$steam_options = "$quick -applaunch $APPID"

##  here you can insert anything to run before starting the game like start "some\program" -args "etc";

##  start game (and steam if not already running) or wait for manual / external launcher
if ($auto_start -ge 1) {
  write-host "`n waiting Steam to start $WINDOWTITLE ..." -fore Yellow
  ni "HKCU:\Software\Classes\.steam_$APPNAME\shell\open\command" -force >''
  sp "HKCU:\Software\Classes\.steam_$APPNAME\shell\open\command" "(Default)" "`"$STEAM\steam.exe`" $steam_options"
  if (!(test-path "$STEAM\.steam_$APPNAME")) { set-content "$STEAM\.steam_$APPNAME" "" }
  start explorer -args "`"$STEAM\.steam_$APPNAME`""
} else {
  write-host "`n waiting manual / external launcher of $WINDOWTITLE ..." -fore Yellow
}

##  minimize script window
sleep 3; powershell -win 2 -nop -c ';' 

##  while the game has focus, adjust desktop resolution to match it, then restore it on alt-tab ----------------------------------
[AveYo.SetRes]::Focus(0, $WINDOWTITLE, $CFG_VIDEO_FILE, $RUNNING, $screen, $restore_width, $restore_height, $restore_refresh)

##  here you can insert anything to run after game is closed like start "some\program" -args "etc";

## log net quality at Desktop\APPNAME_console.log
if ($extra_launch_options -match '-consolelog' -and (test-path "$GAME\console.log")) {  
  copy "$GAME\console.log" "$([Environment]::GetFolderPath('Desktop'))\${APPNAME}_console.log" -force -ea 0
  $chn = '\[STARTUP\]|\[Client\]|\[SteamNetSockets\]|\[NetSteamConn\]|\[Networking\]|\[BuildSparseShadowTree\]'
  $flt = 'GameTypes|ResponseS|SteamRemoteStor|Steam config|CEntity|CPlayer|ClientPut|OptionsMenu|\* Panel|convar|Event System' + 
   '|Disconnect|ExecuteQueuedOperations|IGameSystem|CGameRules|CLoopMode|prop_physics|GameClient|Certificate expires' +
   '|CloseSteamNetConnection|Disassociating NetChan|Removing Steam Net|NetChan Setting Timeout|CSparseShadow' +
   '|Created poll|pipe\] connected|Closing ''| entity|compatability|on panel| connected[\r\n]'
  $log = out-string -i (gc -lit "$([Environment]::GetFolderPath('Desktop'))\${APPNAME}_console.log")
  $log = $log -replace "(?s)(\d\d\/\d\d \d\d\:\d\d:\d\d\s\[[a-zA-Z ]+\])","`f`$1"
  $log = $log -split "`f" -replace '(\d\d\/\d\d \d\d\:\d\d:\d\d\s)([^\[])','$2'
  $log | foreach {
    if ($_ -match $chn -and $_ -notmatch $flt) {$_ -replace "[\r\n]+","`r`n"}
  } | set-content -nonew -lit "$([Environment]::GetFolderPath('Desktop'))\${APPNAME}_console.log" -force
  write-host -fore green " AveYo: ${APPNAME}_console.log filtered on the Desktop "
}

##  done, script closes
[Environment]::Exit(0)

<#:LIBRARY1: start <# -----------------------------------------------------------------------------} switch syntax highlight to C#
/// SetRes by AveYo - loosely based on code by Rick Strahl; WinEvent by OpenByteDev
using System; using System.Collections.Generic; using System.Text; using System.Text.RegularExpressions; using System.Linq;
using System.IO; using System.Threading; using System.ComponentModel; using System.Diagnostics; using System.Management;
using System.Runtime.InteropServices; using System.Reflection;
[assembly:AssemblyVersion("2025.4.14.0")] [assembly: AssemblyTitle("AveYo")]
namespace AveYo {
  public static class SetRes
  {
    public static void Focus(int verbose, string title, string cfg, string reg, 
                             int def_scr, int def_width, int def_height, decimal def_refresh)
    {
      /// AveYo: cfg points to a game video.txt file for parsing the in-game res
      string pattern = @"(?sn)defaultres""\s+""(?<w>\d+)"".*defaultresheight""\s+""(?<h>\d+)"".*" +
                       @"refreshrate_numerator""\s+""(?<n>\d+)"".*refreshrate_denominator""\s+""(?<d>\d+)""";
      string cfg_txt = File.ReadAllText(cfg), cfg_dir = Path.GetDirectoryName(cfg), cfg_ext = Path.GetExtension(cfg);
      var m = Regex.Match(cfg_txt, pattern);
      int cfg_w = 0, cfg_h = 0, cfg_n = 0, cfg_d = 0; decimal cfg_r = 0;
      Int32.TryParse(m.Groups["w"].Value, out cfg_w); Int32.TryParse(m.Groups["h"].Value, out cfg_h);
      Int32.TryParse(m.Groups["n"].Value, out cfg_n); Int32.TryParse(m.Groups["d"].Value, out cfg_d);
      if (cfg_n > 0 && cfg_d > 0) { cfg_r = cfg_n / cfg_d; } else { cfg_r = 0; }

      /// AveYo: reg points to path\to\Steam\Apps\appid/val reg for parsing the running status
      string reg_key = reg.Split('/')[0], reg_val = reg.Split('/')[1];
      string wmi_query = "SELECT * FROM RegistryValueChangeEvent WHERE Hive = 'HKEY_USERS' AND KeyPath = '" +
        System.Security.Principal.WindowsIdentity.GetCurrent().Owner.ToString() + reg_key + @"' AND ValueName='" + reg_val + @"'";
      string reg_query = "HKEY_CURRENT_USER" + reg_key.Replace("\\\\", "\\");

      var _bookmon = new WinEventBook(Const.EVENT_SYSTEM_FOREGROUND, Const.EVENT_SYSTEM_FOREGROUND);
      var _filemon = new FileSystemWatcher() { Path = cfg_dir, NotifyFilter = NotifyFilters.LastWrite, Filter = '*' + cfg_ext };
      var _regimon = new ManagementEventWatcher(new WqlEventQuery(wmi_query));
      var _cancelt = new CancellationTokenSource();
      var _dispose = true;
      var _readcfg = false;
      var _started = false;
      var _running = (int)Microsoft.Win32.Registry.GetValue(reg_query, reg_val, 0);
      var _lastevt = 0;

      if (_running > 0) {
        _started = true;
      }

      /// AveYo: window focus watcher
      _bookmon.EventReceived += (s, e) => {
        if (_started)
        {
          StringBuilder lpTitle = new StringBuilder(GetWindowTextLength(e.WindowHandle) + 1);
          GetWindowTextA(e.WindowHandle, lpTitle, lpTitle.Capacity);
          string lpT = lpTitle.ToString();
          //Console.WriteLine(" {0} +{1}", lpT, _lastevt);
          
          if (lpT == title) {
            if (_readcfg) {
              cfg_txt = File.ReadAllText(cfg);
              var rm = Regex.Match(cfg_txt, pattern);
              Int32.TryParse(rm.Groups["w"].Value, out cfg_w); Int32.TryParse(rm.Groups["h"].Value, out cfg_h);
              Int32.TryParse(rm.Groups["n"].Value, out cfg_n); Int32.TryParse(rm.Groups["d"].Value, out cfg_d);
              if (cfg_n > 0 && cfg_d > 0) { cfg_r = cfg_n / cfg_d; } else { cfg_r = 0; }
              _readcfg = false;
            }
            _lastevt = 1; Change(verbose, def_scr, cfg_w, cfg_h, def_refresh, 0);
          }
          else if (lpT == "Task Manager") { _lastevt = 0; Change(verbose, def_scr, def_width, def_height, def_refresh, 0); }
          else if (lpT == "Task Switching") { if (_lastevt > 0) _lastevt++; }
          else {
            if (_lastevt >= 2 && lpT != "" && lpT != "Search" && lpT != "Program Manager") {
              var devices = GetAllDisplayDevices();
              var monitor = devices.FirstOrDefault(d => d.IsCurrent);
              if (def_scr > 0 && def_scr <= devices.Count) monitor = devices.FirstOrDefault(d => d.MonitorIndex == def_scr);
              RECT cR = new RECT(), mR = monitor.Bounds;
              GetWindowRect(e.WindowHandle, out cR);            
              bool intersect = (cR.left+16)<mR.right && (cR.right-16)>mR.left && (cR.top+16)<mR.bottom && (cR.bottom-16)>mR.top;
              if (verbose > 0)
                Console.WriteLine("{0}\t{1},{2},{3},{4}\t{5},{6},{7},{8}\t{9}", 
                  lpT, cR.left,cR.right,cR.top,cR.bottom,  mR.left,mR.right,mR.top,mR.bottom,  intersect);
              if (intersect) { _lastevt = 0; Change(verbose, def_scr, def_width, def_height, def_refresh, 0); }
            }
          }
        }
      };

      /// AveYo: video.txt cfg file watcher
      _filemon.Changed += (s, e) => { 
         _readcfg = true;
      };

      /// AveYo: steam\appid Running registry watcher
      _regimon.EventArrived += (s, e) => { 
        _running = (int)Microsoft.Win32.Registry.GetValue(reg_query, reg_val, 0);
        if (!_started && _running == 1)
          _started = true;
        if (_started && _running == 0) {
          _started = false;
          _cancelt.Cancel();
        }
      };
      
      /// AveYo: console close watcher
      _consoleCtrlHandler += s =>
      {
        if (_dispose) {
          Console.WriteLine(" script closed");
          _bookmon.TryUnbook();
          _filemon.EnableRaisingEvents = false;
          _regimon.Stop();
          Change(verbose, def_scr, def_width, def_height, def_refresh, 0);
          _bookmon.Dispose();
          _filemon.Dispose();
          _regimon.Dispose();            
        }
        return false;   
      };
     
      _bookmon.BookGlobal();
      _filemon.EnableRaisingEvents = true;
      _regimon.Start();
      SetConsoleCtrlHandler(_consoleCtrlHandler, true);

      /// AveYo: wait loop
      while (!_cancelt.IsCancellationRequested) { if (_cancelt.Token.WaitHandle.WaitOne()) { break; } }
      
      /// AveYo: cleanup
      Console.WriteLine("{0} closed ", title);
      _bookmon.TryUnbook();
      _filemon.EnableRaisingEvents = false;
      _regimon.Stop();
      Change(verbose, def_scr, def_width, def_height, def_refresh, 0);
      _bookmon.Dispose();
      _filemon.Dispose();
      _regimon.Dispose();
    }

    public static int[] Init(int Screen = -1)
    {
      SetProcessDPIAware(); /// AveYo: calculate using real screen values, not windows dpi scaling ones
      var devices = GetAllDisplayDevices();
      var monitor = devices.FirstOrDefault(d => d.IsCurrent);
      if (Screen > 0 && Screen <= devices.Count) monitor = devices.FirstOrDefault(d => d.MonitorIndex == Screen);
      RECT cR = new RECT(), mR = monitor.Bounds;
      GetWindowRect(consolehWnd, out cR);
      /// AveYo: move console window to Screen index or currently active
      int cW = cR.right - cR.left, cH = cR.bottom - cR.top;
      int cL = mR.left + (mR.right - mR.left - cW)/2, cT = mR.top + (mR.bottom - mR.top - cH)/2;
      MoveWindow(consolehWnd, cL, cT, cW, cH, true);
      return new int[] { monitor.SDLIndex, monitor.MonitorIndex, monitor.IsPrimary ? 1 : 0, devices.Count };
    }

    public static int[] List(int Verbose = 1, int Screen = -1, int MinWidth = 1024, int MaxWidth = 16384, int MaxHeight = 16384)
    {
      var devices = GetAllDisplayDevices();
      var monitor = devices.FirstOrDefault(d => d.IsCurrent);
      if (Screen > 0 && Screen <= devices.Count) monitor = devices.FirstOrDefault(d => d.MonitorIndex == Screen);

      if (Verbose != 0) foreach (var display in devices) Console.WriteLine(display.ToString());

      var displayModes = GetAllDisplaySettings(monitor.DriverName);
      var current      = GetCurrentDisplaySetting(monitor.DriverName);
      IList<DisplaySettings> filtered = displayModes;

      /// AveYo: MaxWidth & MaxHeight are used to aggregate the list further by Refresh rate
      if (Verbose == 1)
      {
        filtered = displayModes
          .Where(d => d.Width >= MinWidth && d.Width <= MaxWidth && d.Height <= MaxHeight && d.Orientation == current.Orientation)
          .OrderByDescending(d => d.Width).ThenByDescending(d => d.Refresh)
          .GroupBy(d => new {d.Width, d.Height}).Select(g => g.First()).ToList();
      }
      else if (Verbose == 2 || Verbose == 0 && MaxWidth != 16384)
      {
        filtered = displayModes
          .Where(d => d.Width >= MinWidth && d.Width <= MaxWidth && d.Height <= MaxHeight)
          .OrderByDescending(d => d.Width).ThenByDescending(d => d.Refresh).ToList();
      }

      if (filtered.Count == 0)
        filtered.Add(current);

      var max = filtered.Aggregate((top, atm) => {
          return atm.Width > top.Width || atm.Height > top.Height ? atm :
            atm.Width == top.Width && atm.Height == top.Height && atm.Refresh > top.Refresh ? atm : top;
      });

      foreach (var set in filtered)
      {
        if (set.Equals(current))
        {
          if (Verbose != 0) Console.WriteLine(set.ToString(true) + " [current]");
        }
        else
        {
          if (Verbose != 0) Console.WriteLine(set.ToString(true));
        }
      }
      if (Verbose != 0) Console.WriteLine();
      return new int[] { monitor.SDLIndex, monitor.MonitorIndex,
        (int)current.Width, (int)current.Height, (int)current.Refresh, (int)max.Width, (int)max.Height, (int)max.Refresh };
    }

    public static int[] Change(int Verbose = 1, int Screen = -1, int Width = 0, int Height = 0, decimal Refresh = 0, int Test = 0)
    {
      var devices = GetAllDisplayDevices();
      var monitor = devices.FirstOrDefault(d => d.IsCurrent);
      if (Screen > 0 && Screen <= devices.Count) monitor = devices.FirstOrDefault(d => d.MonitorIndex == Screen);

      var deviceName = monitor.DriverName;
      var current    = GetCurrentDisplaySetting(deviceName);
      //var position = new POINTL(); position.x = monitor.Bounds.left; position.y = monitor.Bounds.top;

      if (Width == 0 || Height == 0)
      {
        if (Verbose != 0) Console.WriteLine(" Width and Height parameters required.\n");
        return new int[] { monitor.SDLIndex, monitor.MonitorIndex,
          (int)current.Width, (int)current.Height, (int)current.Refresh, 0, 0, 0, 1 };
      }

      /// AveYo: Refresh fallback from fractional ex: 59.976 - to nearest integer ex: 60 - to highest supported
      uint Orientation = 0, FixedOutput = (uint)(Test < 0 ? 1 : 0); /// for testing
      var displayModes = GetAllDisplaySettings(deviceName);
      var filtered = displayModes
        .Where(d => d.Width == Width && d.Height == Height && d.Orientation == current.Orientation)
        .OrderByDescending(d => d.Width).ThenByDescending(d => d.Refresh).ToList();

      var ref1 = filtered.FirstOrDefault(d => d.Refresh == (uint)Decimal.Truncate(Refresh));
      var ref2 = filtered.FirstOrDefault(d => d.Refresh == (uint)Decimal.Truncate(Refresh + 1));
      var set = Refresh == 0 ? filtered.FirstOrDefault() : ref1 != null ? ref1 : ref2 != null ? ref2 : filtered.FirstOrDefault();
      if (set == null)
      {
        /// AveYo: Resolution fallback to current
        if (Verbose != 0) Console.WriteLine(" No matching display mode!\n");
        set = current;
        return new int[] { monitor.SDLIndex, monitor.MonitorIndex,
          (int)set.Width, (int)set.Height, (int)set.Refresh, (int)set.Width, (int)set.Height, (int)set.Refresh, 2 };
      }

      try
      {
        DEVMODE mode = GetDeviceMode(deviceName);
        //mode.dmPosition           = position;
        mode.dmPelsWidth          = set.Width;
        mode.dmPelsHeight         = set.Height;
        mode.dmDisplayFrequency   = set.Refresh;
        mode.dmDisplayOrientation = Orientation > 0 ? Orientation : set.Orientation;
        mode.dmDisplayFixedOutput = FixedOutput > 0 ? FixedOutput : set.FixedOutput;
        mode.dmFields             = DmFlags.DM_PELSWIDTH | DmFlags.DM_PELSHEIGHT; //DmFlags.DM_POSITION
        if (Refresh > 0)     mode.dmFields |= DmFlags.DM_DISPLAYFREQUENCY;
        if (Orientation > 0) mode.dmFields |= DmFlags.DM_DISPLAYORIENTATION;
        //if (FixedOutput > 0) mode.dmFields |= DmFlags.DM_DISPLAYFIXEDOUTPUT;
        //if (FixedOutput > 0) mode.dmDisplayFixedOutput = Const.DMDFO_DEFAULT; // DMDFO_STRETCH DMDFO_CENTER DMDFO_DEFAULT

        /// AveYo: test and apply the target res even if it's the same as the current one
        CdsFlags flags = CdsFlags.CDS_TEST | CdsFlags.CDS_NORESET | CdsFlags.CDS_UPDATEREGISTRY; //CdsFlags.CDS_NORESET
        if (FixedOutput > 0) flags |= CdsFlags.CDS_FULLSCREEN;

        int result = ChangeDisplaySettingsEx(deviceName, ref mode, IntPtr.Zero, flags, IntPtr.Zero);
        if (Test > 0)
          return new int[] { monitor.SDLIndex, monitor.MonitorIndex,
            (int)current.Width, (int)current.Height, (int)current.Refresh, (int)set.Width, (int)set.Height, (int)set.Refresh, 0 };
        if (result != Const.SUCCESS)
          throw new InvalidOperationException(string.Format("{0} : {1} = N/A", set.ToString(true), monitor.DisplayName));
        
        flags &= ~CdsFlags.CDS_TEST; flags &= ~CdsFlags.CDS_NORESET; flags |= CdsFlags.CDS_RESET;
        result = ChangeDisplaySettingsEx(deviceName, ref mode, IntPtr.Zero, flags, IntPtr.Zero);
        if (result != Const.SUCCESS)
          throw new InvalidOperationException(string.Format("{0} : {1} = FAIL", set.ToString(true), monitor.DisplayName));

        //ChangeDisplaySettingsEx(IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
        if (Verbose != 0) Console.WriteLine(string.Format("{0} : {1} = OK", set.ToString(true), monitor.DisplayName));
        return new int[] { monitor.SDLIndex, monitor.MonitorIndex,
          (int)current.Width, (int)current.Height, (int)current.Refresh, (int)set.Width, (int)set.Height, (int)set.Refresh, 0 };
      }
      catch(Exception ex)
      {
        if (Verbose != 0) Console.WriteLine(ex.Message);
        return new int[] { monitor.SDLIndex, monitor.MonitorIndex,
          (int)current.Width, (int)current.Height, (int)current.Refresh, 0, 0, 0, 3 };
      }
    }

    public static uint GenAppId(string name)
    {
      return Vpk_Crc32.Compute(Encoding.UTF8.GetBytes(name)) | 0x80000000;
    }

    private static List<DisplayDevice> GetAllDisplayDevices()
    {
      var list = new List<DisplayDevice>();
      uint idx = 0;
      uint size = 256;
      var device = new DISPLAY_DEVICE();
      device.Initialize();

      /// AveYo: detect current monitor via cursor pointer and save Bounds rect for all
      var currentCursorP = new POINTL();
      GetCursorPos(out currentCursorP);
      var currentMonitor = MonitorFromPoint(currentCursorP, Const.MONITOR_DEFAULTTONEAREST);
      var currentMonInfo = new MONITORINFOEX();
      currentMonInfo.Initialize();
      var currentDevice = GetMonitorInfo(currentMonitor, ref currentMonInfo) ? currentMonInfo.szDevice : "";

      var monitors = new List<DisplayInfo>();
      EnumDisplayMonitors( IntPtr.Zero, IntPtr.Zero,
        delegate (IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor,  IntPtr dwData)
        {
          var mi = new MONITORINFOEX();
          mi.Initialize();
          var success = GetMonitorInfo(hMonitor, ref mi);
          if (success)
          {
            var di = new DisplayInfo();
            di.Index      = monitors.Count + 1;
            di.SDLIndex   = monitors.Count + 1;
            di.DeviceName = mi.szDevice;
            di.Width      = mi.rcMonitor.right - mi.rcMonitor.left;
            di.Height     = mi.rcMonitor.bottom - mi.rcMonitor.top;
            di.Bounds     = mi.rcMonitor;
            di.WorkArea   = mi.rcWork;
            di.IsPrimary  = (mi.dwFlags > 0);
            di.IsCurrent  = (mi.szDevice == currentDevice);
            monitors.Add(di);
          }
          return true;
        }, IntPtr.Zero
      );

      /// AveYo: calculate equivalent for sdl_displayindex to use as game launch option
      var primary = monitors.FirstOrDefault(d => d.IsPrimary == true);
      primary.SDLIndex = 0;
      if (primary.Index == 1) {
        for (var i = 1; i < monitors.Count; i++) { monitors[i].SDLIndex = i; }
      }
      else if (primary.Index <= monitors.Count - 1) {
        for (var i = primary.Index; i <= monitors.Count - 1; i++) { monitors[i].SDLIndex = i; }
      }
      //foreach (var mon in monitors) Console.WriteLine(mon.ToString());

      while (EnumDisplayDevices(null, idx, ref device, size) )
      {
        if (device.StateFlags.HasFlag(EdsFlags.EDS_ATTACHEDTODESKTOP))
        {
          var isPrimary  = device.StateFlags.HasFlag(EdsFlags.EDS_PRIMARYDEVICE);
          var isCurrent  = currentDevice != "" ? (device.DeviceName == currentDevice) : isPrimary;
          var monitor = monitors.FirstOrDefault(d => d.DeviceName == device.DeviceName);
          var deviceName = device.DeviceName; var deviceString = device.DeviceString;

          EnumDisplayDevices(device.DeviceName, 0, ref device, 0);
          var dev = new DisplayDevice()
          {
            Index        = list.Count + 1,
            MonitorIndex = monitor.Index > 0 ? monitor.Index : list.Count + 1,
            SDLIndex     = monitor.Index > 0 ? monitor.SDLIndex : list.Count + 1,
            Id           = device.DeviceID,
            DriverName   = deviceName,
            DisplayName  = device.DeviceString,
            AdapterName  = deviceString,
            Bounds       = monitor.Bounds,
            IsPrimary    = isPrimary,
            IsCurrent    = isCurrent
          };
          list.Add(dev);
        }
        idx++;
        device = new DISPLAY_DEVICE();
        device.Initialize();
      }
      return list;
    }

    private static List<DisplaySettings> GetAllDisplaySettings(string deviceName = null)
    {
      var list = new List<DisplaySettings>();
      DEVMODE mode = new DEVMODE();
      mode.Initialize();
      int idx = 0;

      while (EnumDisplaySettings(StringExtensions.ToLPTStr(deviceName), idx, ref mode))
        list.Add(CreateDisplaySettingsObject(idx++, mode));
      return list;
    }

    private static DisplaySettings GetCurrentSettings(string deviceName = null)
    {
      return CreateDisplaySettingsObject(-1, GetDeviceMode(deviceName));
    }

    private static DisplaySettings GetCurrentDisplaySetting(string deviceName = null)
    {
      var mode = GetDeviceMode(deviceName);
      return CreateDisplaySettingsObject(0, mode);
    }

    private static DisplaySettings CreateDisplaySettingsObject(int idx, DEVMODE mode)
    {
      return new DisplaySettings()
      {
        Index       = idx,
        Width       = mode.dmPelsWidth,
        Height      = mode.dmPelsHeight,
        Refresh     = mode.dmDisplayFrequency,
        Orientation = mode.dmDisplayOrientation,
        FixedOutput = mode.dmDisplayFixedOutput
      };
    }

    private static DEVMODE GetDeviceMode(string deviceName = null)
    {
      var mode = new DEVMODE();
      mode.Initialize();

      if (EnumDisplaySettings(StringExtensions.ToLPTStr(deviceName), Const.ENUM_CURRENT, ref mode))
        return mode;
      else
        throw new InvalidOperationException(":(");
    }

    private static IntPtr consolehWnd = GetConsoleWindow();

    private static ConsoleCtrlHandlerDelegate _consoleCtrlHandler;

    private delegate bool ConsoleCtrlHandlerDelegate(int sig);

    private delegate bool EnumDisplayMonitorsDelegate(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);

    [DllImport("kernel32", ExactSpelling = true)] private static extern IntPtr
    GetConsoleWindow();

    [DllImport("kernel32")] private static extern bool
    SetConsoleCtrlHandler(ConsoleCtrlHandlerDelegate handler, bool add);

    [DllImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    GetCursorPos(out POINTL lpPoint);

    [DllImport("user32", SetLastError = true)] private static extern IntPtr
    MonitorFromPoint(POINTL pt, int dwFlags);

    [DllImport("user32", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    GetMonitorInfo(IntPtr hMonitor, [In, Out] ref MONITORINFOEX lpmi);

    [DllImport("user32", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    EnumDisplayMonitors(IntPtr hdc, IntPtr lpRect, EnumDisplayMonitorsDelegate lpfnEnum, IntPtr dwData);

    [DllImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32", SetLastError=true, BestFitMapping=false, ThrowOnUnmappableChar=true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    EnumDisplaySettings(byte[] lpszDeviceName, [param: MarshalAs(UnmanagedType.U4)] int iModeNum, [In,Out] ref DEVMODE lpDevMode);

    [DllImport("user32")] private static extern int
    ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, CdsFlags dwflags, IntPtr lParam);

    [DllImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool
    SetProcessDPIAware();

    [DllImport("user32", CharSet = CharSet.Ansi)] private static extern int
    GetWindowTextLength([In] IntPtr hWnd);

    [DllImport("user32", CharSet = CharSet.Ansi)] private static extern int
    GetWindowTextA([In] IntPtr hWnd, [In, Out] StringBuilder lpString, [In] int nMaxCount);

    //[DllImport("user32")] public static extern int
    //SystemParametersInfo(int uiAction, int uiParam, int[] pvParam, int fWinIni);

    //[DllImport("user32")] public static extern int
    //SystemParametersInfo(int uiAction, int uiParam, IntPtr pvParam, int fWinIni);
  }

  internal class WinEventBook : IDisposable
  {
    private const uint AllThreads = 0;
    private const uint AllProcesses = 0;

    public uint EventMin { get; private set; }
    public uint EventMax { get; private set; }

    public bool Booked { get { return RawBookHandle != IntPtr.Zero; } }

    public bool SkipOwnThread {
      get { return (_bookFlags & BookFlags.SKIPOWNTHREAD) == BookFlags.SKIPOWNTHREAD; }
      set
      {
        if (Booked) { throw new InvalidOperationException("SkipOwnThread cannot be changed while booked."); }
        _bookFlags = value ? _bookFlags | BookFlags.SKIPOWNTHREAD : _bookFlags & ~BookFlags.SKIPOWNTHREAD;
      }
    }

    public bool SkipOwnProcess {
      get { return (_bookFlags & BookFlags.SKIPOWNPROCESS) == BookFlags.SKIPOWNPROCESS; }
      set
      {
        if (Booked) { throw new InvalidOperationException("SkipOwnProcess cannot be changed while booked."); }
        _bookFlags = value ? _bookFlags | BookFlags.SKIPOWNPROCESS : _bookFlags & ~BookFlags.SKIPOWNPROCESS;
      }
    }

    private BookFlags _bookFlags = BookFlags.OUTOFCONTEXT | BookFlags.SKIPOWNPROCESS | BookFlags.SKIPOWNTHREAD;
    public event EventHandler<WinEventBookArgs> EventReceived;
    public IntPtr RawBookHandle { get; private set; }
    private WinEventProc eventHandler;

    public WinEventBook() : this(Const.EVENT_MIN, Const.EVENT_MAX) { }
    public WinEventBook(uint @event) : this(@event, @event) { }
    public WinEventBook(uint eventMin, uint eventMax) { EventMin = eventMin; EventMax = eventMax; RawBookHandle = IntPtr.Zero; }

    public void BookGlobal()
    {
      BookInternal(processId: AllProcesses, threadId: AllThreads, throwIfAlreadyBooked: true, throwOnFailure: true);
    }
    public bool TryBookGlobal()
    {
      return BookInternal(processId: AllProcesses, threadId: AllThreads, throwIfAlreadyBooked: false, throwOnFailure: false);
    }
    internal bool BookInternal(uint processId = AllProcesses, uint threadId = AllThreads, bool throwIfAlreadyBooked = true,
                              bool throwOnFailure = true)
    {
      if (Booked) {
        if (throwIfAlreadyBooked) { throw new InvalidOperationException("Event booked already."); }
        return true;
      }
      eventHandler = new WinEventProc(OnWinEventProc);
      RawBookHandle = SetWinEventBook(eventMin: EventMin, eventMax: EventMax, hmodWinEventProc: IntPtr.Zero,
                                   lpfnWinEventProc: eventHandler, idProcess: processId, idThread: threadId, dwFlags: _bookFlags);
      if (RawBookHandle != IntPtr.Zero) {
        return true;
      } else {
        eventHandler = null;
        if (throwOnFailure) { throw new Win32Exception(); }
        return false;
      }
    }

    public bool Unbook() { return UnbookInternal(throwIfNotBooked: true, throwOnFailure: true); }
    public bool TryUnbook() { return UnbookInternal(throwIfNotBooked: false, throwOnFailure: false); }
    internal bool UnbookInternal(bool throwIfNotBooked = true, bool throwOnFailure = true)
    {
      if (!Booked) {
        if (throwIfNotBooked) { throw new InvalidOperationException("Event not booked."); }
        return true;
      }
      // we need to unbook before freeing our callback in case an event sneaks in at the right time.
      var result = UnbookWinEvent(RawBookHandle);

      eventHandler = null;
      RawBookHandle = IntPtr.Zero;

      if (!result && throwOnFailure) { throw new Win32Exception(); }

      return result;
    }

    protected virtual void OnWinEventProc(IntPtr hWinEventBook, uint eventType, IntPtr hwnd, uint idObject, int idChild,
                                          uint dwEventThread, uint dwmsEventTime)
    {
      if (hWinEventBook != RawBookHandle || RawBookHandle == IntPtr.Zero)
        return;

      if (EventReceived != null)
        EventReceived.Invoke(this, new WinEventBookArgs(
          hWinEventBook, eventType, hwnd, idObject, idChild, dwEventThread, dwmsEventTime)
        );
    }

    #region IDisposable
    private bool _disposed;
    protected virtual void Dispose(bool disposing)
    {
      if (!_disposed) { UnbookInternal(throwIfNotBooked: false, throwOnFailure: false); _disposed = true; }
    }
    ~WinEventBook() { Dispose(disposing: false); }
    public void Dispose() { Dispose(disposing: true); GC.SuppressFinalize(this); }
    #endregion

    [Flags]
    internal enum BookFlags : uint { OUTOFCONTEXT = 0x0000, SKIPOWNTHREAD = 0x0001, SKIPOWNPROCESS = 0x0002, INCONTEXT = 0x0004 }

    internal delegate void WinEventProc(IntPtr hWinEventBook, uint eventType, IntPtr hwnd, uint idObject,
                                      int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32",CharSet = CharSet.Auto, SetLastError = true, EntryPoint="SetWinEvent\x48ook")] public static extern IntPtr
    SetWinEventBook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc, WinEventProc lpfnWinEventProc, uint idProcess,
                    uint idThread, BookFlags dwFlags); /// AveYo: rename the H word

    [DllImport("user32", CharSet = CharSet.Auto, SetLastError = true, EntryPoint="Un\x68ookWinEvent")] public static extern bool
    UnbookWinEvent(IntPtr hWinEventBook); /// AveYo: rename the H word
  }

  internal sealed class WinEventBookArgs : EventArgs
  {
    private const int CHILDID_SELF = 0;
    public IntPtr BookHandle { get; private set; }
    public uint EventType { get; private set; }
    public IntPtr WindowHandle { get; private set; }
    public uint ObjectId { get; private set; }
    public int ChildId { get; private set; }
    public uint EventThreadId { get; private set; }
    public uint EventTime { get; private set; }
    public DateTime EventDate { get { return DateTime.Now.AddMilliseconds(EventTime - Environment.TickCount); } }
    public bool IsChildEvent { get { return !IsOwnEvent; } }
    public bool IsOwnEvent { get { return ChildId == CHILDID_SELF; } }
    public WinEventBookArgs(IntPtr bookHandle, uint eventType, IntPtr windowHandle, uint objectId,
      int childId, uint eventThreadId, uint eventTime)
    {
      BookHandle = bookHandle; EventType = eventType; WindowHandle = windowHandle;
      ObjectId = objectId; ChildId = childId; EventThreadId = eventThreadId; EventTime = eventTime;
    }
  }

  internal class ReentrancySafeEventProcessor<T>
  {
    private const int Processing = 1;
    private const int Idle = 0;
    private int _processing = Idle;
    private readonly Queue<T> _eventQueue = new Queue<T>();
    private readonly Action<T> _eventProcessor;
    public ReentrancySafeEventProcessor(Action<T> eventProcessor) { _eventProcessor = eventProcessor; }

    public void EnqueueAndProcess(T eventData)
    {
      _eventQueue.Enqueue(eventData);
      if (Interlocked.Exchange(ref _processing, Processing) == Processing) { return; }
      ProcessQueue();
    }

    private void ProcessQueue()
    {
      try {
        T data;
        while (_eventQueue.TryDequeue(out data)) { _eventProcessor(data); }
      } finally {
        _processing = Idle;
        if (!_eventQueue.IsEmpty() && Interlocked.Exchange(ref _processing, Processing) == Processing) { ProcessQueue(); }
      }
    }

    public void FlushQueue() { _eventQueue.Clear(); }
  }

  internal static class QueueExtensions
  {
    public static bool TryDequeue<T>(this Queue<T> queue, out T result)
    {
      if (queue.Count == 0) { result = default(T); return false; } else { result = queue.Dequeue(); return true; }
    }
    public static bool IsEmpty<T>(this Queue<T> queue) { return queue.Count == 0; }
  }

  internal static class StringExtensions
  {
    public static byte[] ToLPTStr(string str)
    {
      return (str == null) ? null : Array.ConvertAll((str + '\0').ToCharArray(), Convert.ToByte);
    }
  }

  internal class DisplayInfo
  {
    public int    Index      { get; set; }
    public int    SDLIndex   { get; set; }
    public string DeviceName { get; set; }
    public int    Height     { get; set; }
    public int    Width      { get; set; }
    public RECT   Bounds     { get; set; }
    public RECT   WorkArea   { get; set; }
    public bool   IsPrimary  { get; set; }
    public bool   IsCurrent  { get; set; }

    public override string ToString()
    {
      return string.Format("{0} {1} {2} {3} {4} ({5},{6},{7},{8}){9}{10}", Index, SDLIndex, DeviceName, Height, Width,
        Bounds.left, Bounds.top, Bounds.right, Bounds.bottom, IsPrimary ? " [primary]" : "", IsCurrent ? " [current]" : "");
    }
  }

  internal class DisplayDevice
  {
    public int    Index        { get; set; }
    public int    MonitorIndex { get; set; }
    public int    SDLIndex     { get; set; }
    public string Id           { get; set; }
    public string DriverName   { get; set; }
    public string DisplayName  { get; set; }
    public string AdapterName  { get; set; }
    public RECT   Bounds       { get; set; }
    public bool   IsPrimary    { get; set; }
    public bool   IsCurrent    { get; set; }

    public override string ToString()
    {
      return ToString(false);
    }
    public string ToString(bool Detail)
    {
      if (Detail)
      {
        var sb = new System.Text.StringBuilder(9);
        sb.AppendFormat(" Index:        {0}\n", Index);
        sb.AppendFormat(" MonitorIndex: {0}\n", MonitorIndex);
        sb.AppendFormat(" SDLIndex:     {0}\n", SDLIndex);
        sb.AppendFormat(" Id:           {0}\n", Id);
        sb.AppendFormat(" DriverName:   {0}\n", DriverName);
        sb.AppendFormat(" DisplayName:  {0}\n", DisplayName);
        sb.AppendFormat(" AdapterName:  {0}\n", AdapterName);
        sb.AppendFormat(" Resolution:   {0} x {1}\n", Bounds.right - Bounds.left, Bounds.bottom - Bounds.top);
        sb.AppendFormat(" Bounds:       {0},{1},{2},{3}\n", Bounds.left, Bounds.top, Bounds.right, Bounds.bottom);
        sb.AppendFormat(" IsPrimary:    {0}\n", IsPrimary);
        sb.AppendFormat(" IsCurrent:    {0}\n", IsCurrent);
        return sb.ToString();
      }
      return string.Format(" {0} {1} {2} - {3}{4}{5}", MonitorIndex, SDLIndex, AdapterName, DisplayName,
        IsPrimary ? " [primary]" : "", IsCurrent ? " [current]" : "");
    }
  }

  internal class DisplaySettings
  {
    public int  Index       { get; set; }
    public uint Width       { get; set; }
    public uint Height      { get; set; }
    public uint Refresh     { get; set; }
    public uint Orientation { get; set; }
    public uint FixedOutput { get; set; }

    public override string ToString()
    {
      return ToString(false);
    }
    public string ToString(bool Detail)
    {
      var culture = System.Globalization.CultureInfo.CurrentCulture;
      if (!Detail)
        return string.Format(culture, "   {0,4} x {1,4}", Width, Height);

      var degrees = Orientation == Const.DMDO_90  ? " 90\u00b0" : Orientation == Const.DMDO_180 ? " 180\u00b0" :
        Orientation == Const.DMDO_270 ? " 270\u00b0" : "";
      var scaling = FixedOutput == Const.DMDFO_CENTER ? " C" : FixedOutput == Const.DMDFO_STRETCH ? " F" : "";
      return string.Format(culture, "   {0,4} x {1,4} {2,3}Hz {3}{4}", Width, Height, Refresh, degrees, scaling);
    }

    public override bool Equals(object d)
    {
      var disp = d as DisplaySettings;
      return (disp.Width == Width && disp.Height == Height && disp.Refresh == Refresh && disp.Orientation == Orientation);
    }

    public override int GetHashCode()
    {
      return (string.Format("W{0}H{1}R{2}O{3}", Width, Height, Refresh, Orientation)).GetHashCode();
    }
  }

  internal static class Vpk_Crc32
  {
    /// CRC polynomial 0xEDB88320.
    private static readonly uint[] Table =
    {
       0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3, 0x0EDB8832, 0x79DCB8A4,
       0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91, 0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE,
       0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7, 0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9,
       0xFA0F3D63, 0x8D080DF5, 0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
       0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59, 0x26D930AC, 0x51DE003A,
       0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F, 0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924,
       0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D, 0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F,
       0x9FBFE4A5, 0xE8B8D433, 0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
       0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457, 0x65B0D9C6, 0x12B7E950,
       0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65, 0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2,
       0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB, 0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5,
       0xAA0A4C5F, 0xDD0D7CC9, 0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
       0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD, 0xEDB88320, 0x9ABFB3B6,
       0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683, 0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8,
       0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1, 0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB,
       0x196C3671, 0x6E6B06E7, 0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
       0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B, 0xD80D2BDA, 0xAF0A1B4C,
       0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79, 0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236,
       0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F, 0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31,
       0x2CD99E8B, 0x5BDEAE1D, 0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
       0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21, 0x86D3D2D4, 0xF1D4E242,
       0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777, 0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C,
       0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45, 0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7,
       0x4969474D, 0x3E6E77DB, 0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
       0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF, 0xB3667A2E, 0xC4614AB8,
       0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D
    };

    public static uint Compute(byte[] buffer)
    {
      return ~buffer.Aggregate(0xFFFFFFFF, (current, t) => (current >> 8) ^ Table[t ^ (current & 0xff)]);
    }
  }

  internal static class Const
  {
    public const short CCDEVICENAME = 32,  CCFORMNAME  = 32;

    public const int SUCCESS       = 0,  ENUM_CURRENT  = -1,  MONITOR_DEFAULTTONEAREST = 0x00000002;
    public const int DMDFO_DEFAULT = 0,  DMDFO_STRETCH =  1,  DMDFO_CENTER = 2;
    public const int DMDO_DEFAULT  = 0,  DMDO_90       =  1,  DMDO_180     = 2,  DMDO_270 = 3;

    public const uint EVENT_MIN = 0x00000001,  EVENT_MAX = 0x7FFFFFFF,  EVENT_SYSTEM_FOREGROUND = 0x0003;
  }

  [Flags()]
  internal enum EdsFlags : int
  {
    EDS_ATTACHEDTODESKTOP = 0x00000001,  EDS_MULTIDRIVER   = 0x00000002,  EDS_PRIMARYDEVICE = 0x00000004,
    EDS_MIRRORINGDRIVER   = 0x00000008,  EDS_VGACOMPATIBLE = 0x00000010,  EDS_REMOVABLE     = 0x00000020,
    EDS_MODESPRUNED       = 0x08000000,  EDS_REMOTE        = 0x04000000,  EDS_DISCONNECT    = 0x02000000
  }

  [Flags()]
  internal enum CdsFlags : uint
  {
    CDS_NONE            = 0x00000000,  CDS_UPDATEREGISTRY      = 0x00000001,  CDS_TEST                 = 0x00000002,
    CDS_FULLSCREEN      = 0x00000004,  CDS_GLOBAL              = 0x00000008,  CDS_SET_PRIMARY          = 0x00000010,
    CDS_VIDEOPARAMETERS = 0x00000020,  CDS_ENABLE_UNSAFE_MODES = 0x00000100,  CDS_DISABLE_UNSAFE_MODES = 0x00000200,
    CDS_RESET           = 0x40000000,  CDS_RESET_EX            = 0x20000000,  CDS_NORESET              = 0x10000000
  }

  [Flags()]
  internal enum DmFlags : int
  {
    DM_ORIENTATION   = 0x00000001,  DM_PAPERSIZE          = 0x00000002,  DM_PAPERLENGTH        = 0x00000004,
    DM_PAPERWIDTH    = 0x00000008,  DM_SCALE              = 0x00000010,  DM_POSITION           = 0x00000020,
    DM_NUP           = 0x00000040,  DM_DISPLAYORIENTATION = 0x00000080,  DM_COPIES             = 0x00000100,
    DM_DEFAULTSOURCE = 0x00000200,  DM_PRINTQUALITY       = 0x00000400,  DM_COLOR              = 0x00000800,
    DM_DUPLEX        = 0x00001000,  DM_YRESOLUTION        = 0x00002000,  DM_TTOPTION           = 0x00004000,
    DM_COLLATE       = 0x00008000,  DM_FORMNAME           = 0x00010000,  DM_LOGPIXELS          = 0x00020000,
    DM_BITSPERPEL    = 0x00040000,  DM_PELSWIDTH          = 0x00080000,  DM_PELSHEIGHT         = 0x00100000,
    DM_DISPLAYFLAGS  = 0x00200000,  DM_DISPLAYFREQUENCY   = 0x00400000,  DM_ICMMETHOD          = 0x00800000,
    DM_ICMINTENT     = 0x01000000,  DM_MEDIATYPE          = 0x02000000,  DM_DITHERTYPE         = 0x04000000,
    DM_PANNINGWIDTH  = 0x08000000,  DM_PANNINGHEIGHT      = 0x10000000,  DM_DISPLAYFIXEDOUTPUT = 0x20000000
  }

  [StructLayout(LayoutKind.Sequential)]
  internal struct POINTL { public int x; public int y; }

  [StructLayout(LayoutKind.Sequential)]
  internal struct RECT { public int left; public int top; public int right; public int bottom; }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
  internal struct DISPLAY_DEVICE
  {
    [MarshalAs(UnmanagedType.U4)]                       public int      cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)]  public string   DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string   DeviceString;
    [MarshalAs(UnmanagedType.U4)]                       public EdsFlags StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string   DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string   DeviceKey;
    public void Initialize()
    {
      this.DeviceName   = new string(new char[32]);
      this.DeviceString = new string(new char[128]);
      this.DeviceID     = new string(new char[128]);
      this.DeviceKey    = new string(new char[128]);
      this.cb           = Marshal.SizeOf(this);
    }
  }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
  internal struct DEVMODE
  {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=Const.CCDEVICENAME)]
                                  public string  dmDeviceName;
    [MarshalAs(UnmanagedType.U2)] public ushort  dmSpecVersion;
    [MarshalAs(UnmanagedType.U2)] public ushort  dmDriverVersion;
    [MarshalAs(UnmanagedType.U2)] public ushort  dmSize;
    [MarshalAs(UnmanagedType.U2)] public ushort  dmDriverExtra;
    [MarshalAs(UnmanagedType.U4)] public DmFlags dmFields;
                                  public POINTL  dmPosition;
    [MarshalAs(UnmanagedType.U4)] public uint    dmDisplayOrientation;
    [MarshalAs(UnmanagedType.U4)] public uint    dmDisplayFixedOutput;
    [MarshalAs(UnmanagedType.I2)] public short   dmColor;
    [MarshalAs(UnmanagedType.I2)] public short   dmDuplex;
    [MarshalAs(UnmanagedType.I2)] public short   dmYResolution;
    [MarshalAs(UnmanagedType.I2)] public short   dmTTOption;
    [MarshalAs(UnmanagedType.I2)] public short   dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=Const.CCFORMNAME)]
                                  public string  dmFormName;
    [MarshalAs(UnmanagedType.U2)] public ushort  dmLogPixels;
    [MarshalAs(UnmanagedType.U4)] public uint    dmBitsPerPel;
    [MarshalAs(UnmanagedType.U4)] public uint    dmPelsWidth;
    [MarshalAs(UnmanagedType.U4)] public uint    dmPelsHeight;
    [MarshalAs(UnmanagedType.U4)] public uint    dmDisplayFlags;
    [MarshalAs(UnmanagedType.U4)] public uint    dmDisplayFrequency;
    [MarshalAs(UnmanagedType.U4)] public uint    dmICMMethod;
    [MarshalAs(UnmanagedType.U4)] public uint    dmICMIntent;
    [MarshalAs(UnmanagedType.U4)] public uint    dmMediaType;
    [MarshalAs(UnmanagedType.U4)] public uint    dmDitherType;
    [MarshalAs(UnmanagedType.U4)] public uint    dmReserved1;
    [MarshalAs(UnmanagedType.U4)] public uint    dmReserved2;
    [MarshalAs(UnmanagedType.U4)] public uint    dmPanningWidth;
    [MarshalAs(UnmanagedType.U4)] public uint    dmPanningHeight;
    public void Initialize()
    {
      this.dmDeviceName = new string(new char[Const.CCDEVICENAME]);
      this.dmFormName   = new string(new char[Const.CCFORMNAME]);
      this.dmSize       = (ushort)Marshal.SizeOf(this);
    }
  }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto, Pack = 4)]
  internal struct MONITORINFOEX
  {
    public uint cbSize;
    public RECT rcMonitor;
    public RECT rcWork;
    public int dwFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
    public void Initialize()
    {
      this.rcMonitor = new RECT();
      this.rcWork    = new RECT();
      this.szDevice  = new string(new char[32]);
      this.cbSize    = (uint)Marshal.SizeOf(this);
    }
  }
}
<#:LIBRARY1: end -------------------------------------------------------------------------------------------------------------- #>
};$_press_Enter_if_pasted_in_powershell
