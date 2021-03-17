################################################################################################
################################################################################################
################################################################################################

# NOTE: there are apprently THREE versions of this file!
# LOCATION1: https://dev.azure.com/AD-NAV/ADL.BC.DEV/_git/DevOps?path=%2Fdevops%2FUpdate-BcPackages.ps1
# LOCATION2: https://dev.azure.com/AD-NAV/ADL.BC.DEV/_git/MsDynBC-DevOps?path=%2FUpdate-BcPackages.ps1
# LOCATION3: https://github.com/Adacta/MsDynBC-DevOps/blob/master/Update-BcPackages.ps1

# NOTE: everyone should start using this version ( Devops / LOCATION1 )

################################################################################################
################################################################################################
################################################################################################

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

Write-Warning "#####################################################################"
Write-Warning "#####################################################################"
Write-Warning "#####################################################################"
Write-Warning ""
Write-Warning "PLEASE MIGRATE TO Update-BcPackages on DEVOPS repository"
Write-Warning ""
Write-Warning "#####################################################################"
Write-Warning "#####################################################################"
Write-Warning "#####################################################################"

if("$AppPackagesFolder" -eq '')
{
    Write-Error "AppPackagesFolder parameter not set!"
    return
}

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

    if(!(Test-Path -Path $NavAdminTools)) { throw "Unable to find: NavAdminTool" }
    $NavAdminTools = Resolve-Path $NavAdminTools
    &$NavAdminTools -ErrorAction Stop | Out-Null
}

"DesiredPackagesToInstall: $PackagesToInstall"

$install = @()

$packages = $PackagesToInstall.Split(',')
foreach($package in $packages)
{
    $appFile = Get-ChildItem -Path "$AppPackagesFolder" -Filter "*.app" -Recurse -File | Where-Object { $_.Directory -match "$package" } |% { $_.FullName }

    if("$appFile" -eq '')
    {
        Write-Warning "Unable to find app file for: $package"
        continue
    }
    $install += $package
}

("ActualPackagesToInstall: {0}" -f ($install -join ','))

$uninstall = $install.Clone()
[array]::Reverse($uninstall)

$prevVersions = @{}

# UN-INSTALL

$uninstall |% {
    $kw = $_
    $appFile = Get-ChildItem -Path "$AppPackagesFolder" -Filter "*.app" -Recurse -File | Where-Object { $_.Directory -match "$kw" } |% { $_.FullName }

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
                $appToUninstall | Uninstall-NAVApp -Force -WarningAction SilentlyContinue -Tenant default
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
