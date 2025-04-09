@(set ^ "0=%~f0" -des ') &set 1=%*& powershell -noe -nop -c iex(out-string -i (gc -lit $env:0)) & exit /b ')

pushd $pwd
mkdir "$pwd\runtime" -ea 0
(gps -name dotnet -ea 0) | foreach { if ($_.path -eq "$pwd\runtime\dotnet.exe") {kill -id $_.id -force} }

write-host -fore cyan AveYo: Please wait while installing / refreshing .net portable runtime
$dotnet_install = irm https://builds.dotnet.microsoft.com/dotnet/scripts/v1/dotnet-install.ps1
. ([scriptblock]::Create($dotnet_install)) -Channel STS -InstallDir "$pwd\runtime" -NoPath # -Channel 7.0
write-host

## cleanup
#del "$env:APPDATA\NuGet\NuGet.Config" -force
.\runtime\dotnet nuget locals all --clear
if ((test-path "$pwd\bin\*.json") -and (test-path "$pwd\obj\*.json")) {
  .\runtime\dotnet clean | out-null; rmdir "$pwd\bin","$pwd\obj" -recurse -force -ea 0
}

## 1-of-3: generate cs2demoparser.bat
new-item "$pwd\cs2demoparser.bat" -type file -ea 0 -value @'
@(set ^ "0=%~f0" -des ') &set 1=%*& powershell -noe -nop -c iex(out-string -i (gc -lit $env:0)) & exit /b ')
[Console]::Title = "cs2demoparser"

$demo = "liquid-vs-cloud9-ancient-p2.dem"

if ($env:1 -and (gi $env:1 -ea 0).Extension -eq '.dem') { $demo = $env:1 }
pushd -lit (split-path $env:0)
.\runtime\dotnet run --project cs2demoparser.csproj --interactive -- "`"${demo}`""
#_Press_Enter_if_pasted_in_powershell
'@

## 2-of-3: generate cs2demoparser.csproj
new-item "$pwd\cs2demoparser.csproj" -type file -ea 0 -value @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <Product>cs2demoparser</Product>
    <Description>Counter Strike 2 demo parser</Description>
    <Company>AveYo</Company>
    <Copyright>AveYo</Copyright>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
    <OutputType>Exe</OutputType><OutputPath>bin\</OutputPath>
    <AppendRuntimeIdentifierToOutputPath>false</AppendRuntimeIdentifierToOutputPath>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <TargetFramework>net9.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <WarningsNotAsErrors>$(WarningsNotAsErrors);CS1591</WarningsNotAsErrors>
    <WarningLevel>4</WarningLevel>
    <ErrorReport>prompt</ErrorReport>
  </PropertyGroup>
  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Release|AnyCPU' ">
    <PlatformTarget>x64</PlatformTarget><DebugType>pdbonly</DebugType>
    <DefineConstants>TRACE</DefineConstants>
    <Optimize>true</Optimize>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="cs2demoparser.cs" />
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="DemoFile" Version="0.29.1" />
    <PackageReference Include="DemoFile.Game.Cs" Version="0.29.1" />
    <PackageReference Include="Spectre.Console" Version="0.47.0" />
  </ItemGroup>
</Project>
'@

## 3-of-3: generate cs2demoparser.cs
new-item "$pwd\cs2demoparser.cs" -type file -ea 0 -value @'
using System.Diagnostics; using System.Text; using DemoFile; using DemoFile.Game.Cs;

internal class Program
{
  static async Task Main(string[] args)
  {
    var path = args.SingleOrDefault() ?? throw new Exception("Expected a single arg: <path to .dem>");
    var sw = Stopwatch.StartNew();
    var demobytes = File.ReadAllBytes(path);
    var results = await DemoFileReader<CsDemoParser>.ReadAllParallelAsync(demobytes, SetupSection, default);
    
    // AveYo: quick and dirty 2nd read 16 ticks before PlayerDeath
    DemoTick lookB = new DemoTick(16);
    var demoB = new CsDemoParser();
    var readB = DemoFileReader.Create(demoB, new MemoryStream(demobytes));
    await readB.StartReadingAsync(default(CancellationToken));

    string VsShot(string? victim = "", string? attacker = "") {
      var sb = new StringBuilder();
      foreach (var player in demoB.Players) {
        if ((victim != "" && player.PlayerName == victim) || (attacker != "" && player.PlayerName == attacker)) {
          var pawn = player.PlayerPawn;
          var vs = player.PlayerName == victim ? "v" : "a";
          var team = player.Team.ToString()[0] + ""; if (team == "C") team = "CT";
          var alive = (pawn?.IsAlive == true) ? "alive" : "dead ";
          sb.Append($"{demoB.CurrentGameTime,-16} {vs} {player.PlayerName} {team} {alive} at {pawn?.LastPlaceName} ");
          sb.Append($"pos [{pawn?.Origin.X},{pawn?.Origin.Y},{pawn?.Origin.Z}] pitch {pawn?.Rotation.Pitch} ");
          sb.AppendLine($"yaw {pawn?.Rotation.Yaw} eyes {pawn?.EyeAngles.Pitch} {pawn?.EyeAngles.Yaw}");
          if (pawn?.IsAlive == true) {
            sb.Append($"\t\t   VelocityMod {pawn?.VelocityModifier} AccuracyPenalty {pawn?.ActiveWeapon?.AccuracyPenalty} ");
            sb.Append($"AimPunch Angle [{pawn?.AimPunchAngle.Pitch},{pawn?.AimPunchAngle.Yaw},{pawn?.AimPunchAngle.Roll}] ");
            sb.AppendLine($"Vel [{pawn?.AimPunchAngleVel.Pitch},{pawn?.AimPunchAngleVel.Yaw},{pawn?.AimPunchAngleVel.Roll}]");
            sb.AppendLine($"\t\t   {pawn?.InputButtons}  ShotsFired {pawn?.ShotsFired}");
          }
        }
      }
      return sb.ToString();
    }

    foreach (var result in results) {
      var dshotB = new DemoShot();
      foreach (var (tick, items) in result._items) {
        foreach (var item in items) {
          if (item[0] == '\f') {
            var versus = item.Split('\f',3);
            await readB.SeekToTickAsync(tick - lookB, default(CancellationToken));
            while (demoB.CurrentDemoTick < tick) {
              if (!await readB.MoveNextAsync(default(CancellationToken))) { break; }
              dshotB.Add(demoB.CurrentDemoTick, $"{VsShot(versus[1],versus[2])}");
            }
          }
        }
      }
      result.MergeFrom(dshotB);
      Console.Write(result.ToString());
    }
    
    Console.WriteLine($"Finished in {sw.Elapsed.TotalSeconds:N3} seconds");
  }

  private static DemoShot SetupSection(CsDemoParser demo)
  {
    var dshot = new DemoShot();

    demo.Source1GameEvents.PlayerHurt += e => {
      var sb = new StringBuilder();
      string ta = e.Attacker?.Team.Teamname[0] + "", tv = e.Player?.Team.Teamname[0] + "";
      if (ta == "C") ta = "CT"; if (tv == "C") tv = "CT";
      sb.Append($"{demo.CurrentGameTime} H {e.Attacker?.PlayerName} {ta} with {e.Weapon} ");
      sb.Append($"{e.DmgHealth}/{e.Health}hp {e.DmgArmor}/{e.Armor}am dmg to {(HitGroup)e.Hitgroup} "); 
      sb.Append(e.Attacker?.PlayerName != e.Player?.PlayerName ? $"of {e.Player?.PlayerName} {tv}" : $"of SELF");
      sb.AppendLine("");
      dshot.Add(demo.CurrentDemoTick, sb.ToString());
    };

    demo.Source1GameEvents.PlayerDeath += e => {
      var sb = new StringBuilder();
      string ta = e.Attacker?.Team.Teamname[0] + "", tv = e.Player?.Team.Teamname[0] + "";
      if (ta == "C") ta = "CT"; if (tv == "C") tv = "CT";
      sb.Append($"{demo.CurrentGameTime} K {e.Attacker?.PlayerName} {ta} with {e.Weapon} ");
      if (e.Headshot) { sb.Append("HS "); }
      sb.AppendLine($"killed {e.Player?.PlayerName} {tv}");
      // AveYo: prepare to read 16 ticks before the death
      dshot.Add(demo.CurrentDemoTick, $"\f{e.Player?.PlayerName}\f{e.Attacker?.PlayerName}");
      dshot.Add(demo.CurrentDemoTick, sb.ToString());
    };

    demo.Source1GameEvents.RoundEnd += e => {
      var sb = new StringBuilder();
      var roundEndReason = (CSRoundEndReason) e.Reason;
      var winningTeam = (CSTeamNumber) e.Winner switch {
        CSTeamNumber.Terrorist => demo.TeamTerrorist,
        CSTeamNumber.CounterTerrorist => demo.TeamCounterTerrorist,
        _ => null
      };
      sb.Append($"{demo.CurrentGameTime,-16} Round end: {roundEndReason} , ");
      sb.Append($"Winner: ({winningTeam?.Teamname}) {winningTeam?.ClanTeamname} , ");
      sb.Append($"{demo.GameRules.RoundsPlayedThisPhase} rounds played in {demo.GameRules.CSGamePhase} , ");
      sb.Append($"Scores: {demo.TeamTerrorist.ClanTeamname} {demo.TeamTerrorist.Score} - ");
      sb.Append($"{demo.TeamCounterTerrorist.Score} {demo.TeamCounterTerrorist.ClanTeamname}");
      sb.AppendLine("\n");
      dshot.Add(demo.CurrentDemoTick, sb.ToString());
    };
    
    return dshot;
  }

  internal enum HitGroup : int
  {
    invalid = -1, generic = 0, head = 1, chest = 2, stomach = 3, leftarm = 4, rightarm = 5, leftleg = 6, rightleg = 7, 
    neck = 8, unused = 9, gear = 10, special = 11
  }
}

public class DemoShot
{
  public readonly Dictionary<DemoTick, List<string>> _items = new();

  public int Count => _items.Count;

  public void Add(DemoTick tick, string details) {
    if (!_items.TryGetValue(tick, out var tickItems)) {
      _items[tick] = new List<string> {details};
    }
    else if (!tickItems.Contains(details)) {
      tickItems.Add(details);
    }
  }

  public void MergeFrom(DemoShot other) {
    foreach (var (tick, items) in other._items) {
      foreach (var item in items) {
        Add(tick, item);
      }
    }
  }

  public override string ToString() {
    var sb = new StringBuilder();
    foreach (var (tick, items) in _items.OrderBy(kvp => kvp.Key)) {
      foreach (var item in items) {
        if (item[0] != '\f') sb.Append($"{item}");
      }
    }
    return sb.ToString();
  }
}

'@
write-host
write-host -fore cyan AveYo: Edit cs2demoparser.cs - refer to github.com/saul/demofile-net/tree/main/examples  
write-host -fore cyan AveYo: Then cs2demoparser.bat some-match.dem

#_Press_Enter_if_pasted_in_powershell
