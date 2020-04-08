Trace-VstsEnteringInvocation $MyInvocation
if ($env:VerbosePreference)
{
    Set-Variable VerbosePreference $env:VerbosePreference -ErrorAction Continue
}
Import-VstsLocStrings "$PSScriptRoot\Task.json"

$ServerInstance = Get-VstsInput -Name ServerInstance
$AppPackagesFolder = Get-VstsInput -Name AppPackagesFolder
$PackagesToInstall = Get-VstsInput -Name PackagesToInstall
$SyncMode = Get-VstsInput -Name SyncMode
$SkipVerification = Get-VstsInput -Name SkipVerification -AsBool
$ForceAppDataUpgrade = Get-VstsInput -Name ForceAppDataUpgrade -AsBool

.\Update-BcPackages.ps1 -ServerInstance $ServerInstance -AppPackagesFolder $AppPackagesFolder -PackagesToInstall $PackagesToInstall -SyncMode $SyncMode -SkipVerification:$SkipVerification -ForceAppDataUpgrade:$ForceAppDataUpgrade







### plan with generic parameter matching
$inputArguments = @{}

$command = Get-Command .\Update-BcPackages.ps1
$command.Parameters.GetEnumerator() | ForEach-Object {
    $paramValue = [System.Management.Automation.ParameterMetadata]$_.Value
    $paramName = $paramValue.Name
    if ($paramValue.SwitchParameter) {
        $inputArguments.$paramName = Get-VstsInput -Name $paramName -AsBool
    }
    else {
        $inputArguments.$paramName = Get-VstsInput -Name $paramName
    }
}
$inputArguments # prints arguments
#.\Update-BcPackages.ps1 @inputArguments