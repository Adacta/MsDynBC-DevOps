<#
.SYNOPSIS
Update BC Server Instance to specified packages

.DESCRIPTION
- Finds App package
- Publishes package
- Uninstall and unpublish any older version of same package
- Synchronizes App to database
- Data Upgrades App
- Installs a published App
#>
Param(
    # Specifies the name of a Dynamics Business Central Server instance
    [Parameter(Mandatory = $true)]
    [ArgumentCompleter( {
        Get-NAVServerInstance | % { $_.ServerInstance.Substring($_.ServerInstance.IndexOf("$") + 1) }
    } )]
    [string]
    $ServerInstance
    ,
    # Package folders in sequential order for publish. Unpublish order is reversed.
    [Parameter(Mandatory = $true)]
    [ValidateCount(1, 999999)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $PackagesToInstall = @()
    ,
    # Database Sync Mode (Add, Clean, Development, ForceSync)
    [ValidateSet("Add", "Clean", "Development", "ForceSync")]
    [string]
    $SyncMode = "Add"
    ,
    [switch]
    $ForceAppDataUpgrade
)

$NavAdminTools = "C:\Program Files\*\*\Service\NavAdminTool.ps1"
if(!(Test-Path -Path $NavAdminTools)) { throw "Unable to find: NavAdminTool" }
$NavAdminTools = Resolve-Path $NavAdminTools
&$NavAdminTools -ErrorAction Stop | Out-Null

$apps = @()

$PackagesToInstall | % {
    $appTopDir = $_
    $appDirs = Get-ChildItem -Recurse $appTopDir*
    $appDirs | % {
        $appDir = $_
        $appFiles = Get-ChildItem $appDir\*.app
        if ($appFiles -and $appFiles.Length) {
            $appFiles | % {
                $appFile = $_
                Write-Information "Publishing $appFile" -InformationAction Continue
                $app = Publish-NAVApp -ServerInstance $ServerInstance -Path $appFile.FullName -Scope Tenant -PassThru -WarningAction SilentlyContinue
                Write-Information " ✔ Published $($app.Name) $($app.Version)" -InformationAction Continue

                $apps += $app
            }
        }
        else {
            Write-Warning "0 packages found for $app"
        }
    }
}

$prevVersions = @{}
$allApps = Get-NAVAppInfo -ServerInstance $ServerInstance
[System.Linq.Queryable]::Reverse([System.Linq.Queryable]::AsQueryable($apps)) | % {
    $app = $_
    $newApp = $allApps.Where({$_.Publisher -eq $app.Publisher -and $_.Name -eq $app.Name -and $_.Version -eq $app.Version}, "First")[0]
    $appInfos = $allApps.Where({$_.AppId -eq $newApp.AppId})
    
    $appInfos | % {
        $appToUninstall = $_
        if ($appToUninstall.Version -ne $newApp.Version) {
            $prevVersions[$appToUninstall.Name] = $true
            Write-Information " 🗑 Uninstalling $($appToUninstall.Name) $($appToUninstall.Version)" -InformationAction Continue
            $appToUninstall | Uninstall-NAVApp -Force -WarningAction SilentlyContinue
            if ($SyncMode -eq "Add")
            {
                $appToUninstall | Unpublish-NAVApp -WarningAction SilentlyContinue
            }
        }
    }
}

$apps | % {
    $app = $_
    Write-Information " ✅ Sync $($app.Name) $($app.Version) with mode $SyncMode" -InformationAction Continue
    $app | Sync-NAVApp -ServerInstance $ServerInstance -Force -Mode $SyncMode
    if ($prevVersions[$app.Name] -or $ForceAppDataUpgrade) {
        Write-Information " ✅ Starting data upgrade $($app.Name) $($app.Version)" -InformationAction Continue
        $app | Start-NAVAppDataUpgrade
    }

    Write-Information " ✅ Installing $($app.Name) $($app.Version)" -InformationAction Continue
    $app | Install-NAVApp -ServerInstance $ServerInstance -Force
}
