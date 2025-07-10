@(set "0=%~f0" '& set 1=%*) & powershell -nop -c "type -lit $env:0 | out-string | powershell -nop -c -" & exit /b ');.{

$id = 'CLEAR SHADER CACHE'    ##  AveYo, 10.07.2025
$cl = ''
$ps = {
  [Console]::Title = $args[2]; $cl = $args[1]; pushd -lit $(split-path $args[0])

  ##  AveYo: detect STEAM
  $STEAM = resolve-path (gp "HKCU:\SOFTWARE\Valve\Steam").SteamPath
  if (-not (test-path "$STEAM\steam.exe") -or -not (test-path "$STEAM\steamapps\libraryfolders.vdf")) {
    write-host " Steam not found! " -fore Black -back Yellow; sleep 7; return 1
  }

  ##  AveYo: detect specific APPS
  $apps = @{id = 730; name='cs2';   mod='csgo'; installdir='Counter-Strike Global Offensive'},
          @{id = 570; name='dota2'; mod='dota'; installdir='dota 2 beta'}

  function vdf_parse {
    param([string[]]$vdf, [ref]$line = ([ref]0), [string]$re = '\A\s*("(?<k>[^"]+)"|(?<b>[\{\}]))\s*(?<v>"(?:\\"|[^"])*")?\Z')
    $obj = new-object System.Collections.Specialized.OrderedDictionary # ps 3.0: [ordered]@{}
    while ($line.Value -lt $vdf.count) {
      if ($vdf[$line.Value] -match $re) {
        if ($matches.k) { $key = $matches.k }
        if ($matches.v) { $obj[$key] = $matches.v }
        elseif ($matches.b -eq '{') { $line.Value++; $obj[$key] = vdf_parse -vdf $vdf -line $line }
        elseif ($matches.b -eq '}') { break }
      }
      $line.Value++
    }
    return $obj
  }

  $vdf = vdf_parse (gc "$STEAM\steamapps\libraryfolders.vdf" -force -ea 0)
  if ($vdf.count -eq 0) {$vdf = vdf_parse @('"libraryfolders"','{','}')}
  foreach ($nr in $vdf.Item(0).Keys) { foreach ($app in $apps) {
    if ($vdf.Item(0)[$nr]["apps"] -and $vdf.Item(0)[$nr]["apps"]["$($app.id)"]) {
      $l = resolve-path $vdf.Item(0)[$nr]["path"].Trim('"'); $i = "$l\steamapps\common\$($app.installdir)"
      if (test-path "$i\game\$($app.mod)\steam.inf") {
        $app["gameroot"] = "$i\game"; $app["game"] = "$i\game\$($app.mod)"
        $app["exe"] = "$i\game\bin\win64\$($app.name).exe"; $app["steamapps"] = "$l\steamapps"
      }
    }
  }}

  ## AveYo: close steam and specific apps if already running (gracefully first, then forced)
  $stop = ''; $kill = 'steamwebhelper','steam'; $apps |foreach { $stop += ' +app_stop ' + $_['id']; $kill += $_['name'] }
  if ((gp "HKCU:\Software\Valve\Steam\ActiveProcess" -ea 0).pid -gt 0 -and (gps -name steamwebhelper -ea 0)) {
    start "$STEAM\Steam.exe" -args "-ifrunning -silent $stop -shutdown +quit now" -wait
  }
  while ((gps -name steamwebhelper -ea 0) -or (gps -name steam -ea 0)) {
    kill -name $kill -force -ea 0; del "$STEAM\.crash" -force -ea 0; sleep -m 250
  }

  "`n empty STEAM logs "
  mkdir "$steam\logs\-EMPTY-" -force >''; robocopy "$steam\logs\-EMPTY-/" "$STEAM\logs/" /MIR /R:1 /W:0 /ZB >''

  "`n empty STEAM crash dumps "
  mkdir "$steam\dumps\-EMPTY-" -force >''; robocopy "$steam\dumps\-EMPTY-/" "$STEAM\dumps/" /MIR /R:1 /W:0 /ZB >''

  "`n empty APPS crash dumps "
  $apps |foreach { if ($_.exe) { del "$(split-path $_.exe)\*.mdmp" -force -ea 0 } }

  "`n empty APPS shadercache "
  $apps |foreach { $t = @("$($_.game)\shadercache", "$($_.steamapps)\shadercache\$($_.id)")
    if ($_.steamapps -ne "$steam\steamapps") { $t += "$steam\steamapps\shadercache\$($_.id)" }
    $t |foreach { if (test-path $_) {
      "$_"; mkdir "$_\-EMPTY-" -force >''; robocopy "$_\-EMPTY-/" "$_/" /MIR /R:1 /W:0 /ZB >''
    }}
  }

  "`n empty Compute cache "
  $t = "$([Environment]::GetFolderPath('ApplicationData'))\NVIDIA\ComputeCache"; if (test-path $t) {
    $t; mkdir "$t\-EMPTY-" -force >''; robocopy "$t\-EMPTY-/" "$t/" /MIR /R:1 /W:0 /ZB >''
  }

  "`n empty NV cache "
  $t = "$([Environment]::GetFolderPath('CommonApplicationData'))\NVIDIA Corporation\NV_Cache"; if (test-path $t) {
    $t; mkdir "$t\-EMPTY-" -force >''; robocopy "$t\-EMPTY-/" "$t/" /MIR /R:1 /W:0 /ZB >''
  }

  "`n empty Local shader cache "
  'D3DSCache','NVIDIA\GLCache','NVIDIA\DXCache','NVIDIA\OptixCache','NVIDIA Corporation\NV_Cache',
  'AMD\DX9Cache','AMD\DxCache','AMD\DxcCache','AMD\GLCache','AMD\OglCache','AMD\VkCache','Intel\ShaderCache' |foreach {
    $t = "$([Environment]::GetFolderPath('LocalApplicationData'))\$_"; if (test-path $t) {
      $t; mkdir "$t\-EMPTY-" -force >''; robocopy "$t\-EMPTY-/" "$t/" /MIR /R:1 /W:0 /ZB >''
  }}

  "`n empty LocalLow shader cache "
  'NVIDIA\PerDriverVersion\DXCache','NVIDIA\PerDriverVersion\GLCache','Intel\ShaderCache' |foreach {
    $t = "$(split-path ([Environment]::GetFolderPath('LocalApplicationData')))\LocalLow\$_"; if (test-path $t) {
      $t; mkdir "$t\-EMPTY-" -force >''; robocopy "$t\-EMPTY-/" "$t/" /MIR /R:1 /W:0 /ZB >''
  }}

  "`n empty driver temp "
  "$env:systemdrive\AMD","$env:systemdrive\NVIDIA","$env:systemdrive\Intel" |foreach { if (test-path $_) {
    mkdir "$_\-EMPTY-" -force >''; robocopy "$_\-EMPTY-/" "$_/" /MIR /R:1 /W:0 /ZB >''
  }}

  sleep 3
}
$f0 = ($env:0,"$pwd\.pasted")[!$env:0]; $cl = ($env:1,$cl)[!$env:1]

##  AveYo: elevate
if ([Security.Principal.WindowsIdentity]::GetCurrent().Groups.Value -notcontains 'S-1-5-32-544') {
  write-host " '$id' Requesting ADMIN rights.. " -fore Black -back Yellow; sleep 2
  sp HKCU:\Volatile*\* $id ".{$ps} '$($f0-replace"'","''")' '$($cl-replace"'","''")' '$id'" -force -ea 0
  start powershell -args "-nop -c (gp Registry::HKU\S-1-5-21*\Volatile*\*).'$id' | out-string | powershell -nop -c -" -verb runas
} else {. $ps $f0 $cl $id }

} #_press_Enter_if_pasted_in_powershell
