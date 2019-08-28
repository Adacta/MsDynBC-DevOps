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

$install = $PackagesToInstall.Split(',')
$uninstall = $PackagesToInstall.Split(',')
[array]::Reverse($uninstall)

$prevVersions = @{}

# UN-INSTALL

$uninstall |% {
    $kw = $_
    $appFile = Get-ChildItem -Path "$ContainerWorkFolder" -Recurse -File | Where-Object { $_.Directory -match "$kw" } |% { $_.FullName }
    if(Test-Path -Path $appFile -PathType Leaf)
    {
        $appinfo = Get-NAVAppInfo -Path $appFile
        $installedapps = Get-NAVAppInfo -ServerInstance $ServerInstance -Id $appinfo.AppId

        $installedapps |% `
        {
            $appToUninstall = $_

            if ($appToUninstall.Version -ne $appinfo.Version -or $ForceAppDataUpgrade)
            {
                $prevVersions[$appToUninstall.Name] = $true

                Write-Information " 🗑 Uninstalling $($appToUninstall.Name) $($appToUninstall.Version)" -InformationAction Continue
                $appToUninstall | Uninstall-NAVApp -Force -WarningAction SilentlyContinue
                $appToUninstall | Unpublish-NAVApp -WarningAction SilentlyContinue
            }
        }
    }
}

# INSTALL

$install |% `
{
    $kw = $_
    $appFile = Get-ChildItem -Path "$ContainerWorkFolder" -Recurse -File | Where-Object { $_.Directory -match "$kw" } |% { $_.FullName }
    if(Test-Path -Path $appFile -PathType Leaf)
    {
        $appinfo = Get-NAVAppInfo -Path $appFile
        $installedapp = Get-NAVAppInfo -ServerInstance $ServerInstance -Id $appinfo.AppId -Version $appinfo.Version
        if($installedapp -ne $null) { return }
    
        Write-Information "Publishing $appFile" -InformationAction Continue
        $app = Publish-NAVApp -ServerInstance $ServerInstance -Path $appFile -Scope Tenant -Tenant default -PassThru -WarningAction SilentlyContinue
        Write-Information " ✔ Published $($app.Name) $($app.Version)" -InformationAction Continue
    }
}

# UPGRADE & PUBLISH

$install |% `
{
    $kw = $_
    $appFile = Get-ChildItem -Path "$ContainerWorkFolder" -Recurse -File | Where-Object { $_.Directory -match "$kw" } |% { $_.FullName }
    $appinfo = Get-NAVAppInfo -Path $appFile
    $app = Get-NAVAppInfo -ServerInstance $ServerInstance -Id $appinfo.AppId

    Write-Information " ✅ Sync $($app.Name) $($app.Version) with mode $SyncMode" -InformationAction Continue
    $app | Sync-NAVApp -ServerInstance $ServerInstance -Force -Mode $SyncMode

    if ($prevVersions[$app.Name] -or $ForceAppDataUpgrade) {
        Write-Information " ✅ Starting data upgrade $($app.Name) $($app.Version)" -InformationAction Continue
        $app | Start-NAVAppDataUpgrade -Tenant default
    }

    Write-Information " ✅ Installing $($app.Name) $($app.Version)" -InformationAction Continue
    $app | Install-NAVApp -ServerInstance $ServerInstance -Tenant default -Force
}
