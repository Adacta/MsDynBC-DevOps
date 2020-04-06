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
    # Package folder
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $AppPackagesFolder = ""
    ,
    # Package names in sequential order for publish. Unpublish order is reversed.
    [Parameter(Mandatory = $true)]
    #[ValidateCount(1, 999999)]
    [ValidateNotNullOrEmpty()]
    [string]
    $PackagesToInstall = ""
    ,
    [switch]
    $SkipVerification = $false
    ,
    # Database Sync Mode (Add, Clean, Development, ForceSync)
    [ValidateSet("Add", "Clean", "Development", "ForceSync")]
    [string]
    $SyncMode = "Add"
    ,
    [switch]
    $ForceAppDataUpgrade
)
if("$AppPackagesFolder" -eq '')
{
    Write-Error "AppPackagesFolder parameter not set!"
    return
}
"debug: Test-Path -Path '$AppPackagesFolder'" #dbg ##################################################################################
if(!(Test-Path -Path $AppPackagesFolder -PathType Container))
{
    Write-Error "unable to open AppPackagesFolder: '$AppPackagesFolder'"
    return
}

if(!(Get-Module 'Microsoft.Dynamics.Nav.Management'))
{
    $serviceEntry = (Get-WmiObject win32_service |? { $_.Name -eq "MicrosoftDynamicsNavServer`$$ServerInstance" }).Pathname
    $serviceExePath = $serviceEntry.Substring(0, $serviceEntry.IndexOf("Microsoft.Dynamics.Nav.Server.exe")).TrimStart('"')

    $NavAdminTools = "$serviceExePath\NavAdminTool.ps1"
"debug: Test-Path -Path '$NavAdminTools'" #dbg ##################################################################################
    if(!(Test-Path -Path $NavAdminTools)) { throw "Unable to find: NavAdminTool" }
    $NavAdminTools = Resolve-Path $NavAdminTools
    &$NavAdminTools -ErrorAction Stop | Out-Null
}

$install = $PackagesToInstall.Split(',')
$uninstall = $PackagesToInstall.Split(',')
[array]::Reverse($uninstall)

$prevVersions = @{}

# UN-INSTALL

$uninstall |% {
    $kw = $_
    $appFile = Get-ChildItem -Path "$AppPackagesFolder" -Filter "*.app" -Recurse -File | Where-Object { $_.Directory -match "$kw" } |% { $_.FullName }
"debug: Test-Path -Path '$appFile'" #dbg ##################################################################################
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
    $appFile = Get-ChildItem -Path "$AppPackagesFolder" -Filter "*.app" -Recurse -File | Where-Object { $_.Directory -match "$kw" } |% { $_.FullName }
"debug: Test-Path -Path '$appFile'" #dbg ##################################################################################
    if(Test-Path -Path $appFile -PathType Leaf)
    {
        $appinfo = Get-NAVAppInfo -Path $appFile
        $installedapp = Get-NAVAppInfo -ServerInstance $ServerInstance -Id $appinfo.AppId -Version $appinfo.Version
        if($installedapp -ne $null) { return }
    
        Write-Information "Publishing $appFile" -InformationAction Continue
        $app = Publish-NAVApp -ServerInstance $ServerInstance -Path $appFile -Scope Tenant -Tenant default -PassThru -WarningAction SilentlyContinue -SkipVerification:$SkipVerification
        Write-Information " ✔ Published $($app.Name) $($app.Version)" -InformationAction Continue
    }
}

# UPGRADE & PUBLISH

$install |% `
{
    $kw = $_
    $appFile = Get-ChildItem -Path "$AppPackagesFolder" -Filter "*.app" -Recurse -File | Where-Object { $_.Directory -match "$kw" } |% { $_.FullName }
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
