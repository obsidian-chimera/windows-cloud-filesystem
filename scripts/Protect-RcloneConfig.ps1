[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = "$env:APPDATA\rclone\rclone.conf",
    [string]$UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required to harden rclone configuration ACLs.'
    }
}

Assert-Administrator

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "rclone configuration file was not found: $ConfigPath"
}

$configDirectory = Split-Path -Parent $ConfigPath
$account = New-Object System.Security.Principal.NTAccount($UserName)
$system = New-Object System.Security.Principal.NTAccount('NT AUTHORITY\SYSTEM')

try {
    $null = $account.Translate([System.Security.Principal.SecurityIdentifier])
}
catch {
    throw "Could not resolve Windows account '$UserName'. $($_.Exception.Message)"
}

$allow = [System.Security.AccessControl.AccessControlType]::Allow
$fullControl = [System.Security.AccessControl.FileSystemRights]::FullControl
$inheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
$propagation = [System.Security.AccessControl.PropagationFlags]::None

if ($PSCmdlet.ShouldProcess($configDirectory, "Restrict directory ACL to SYSTEM and $UserName")) {
    $directoryAcl = New-Object System.Security.AccessControl.DirectorySecurity
    $directoryAcl.SetOwner($account)
    $directoryAcl.SetAccessRuleProtection($true, $false)
    $directoryAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($account, $fullControl, $inheritance, $propagation, $allow)))
    $directoryAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($system, $fullControl, $inheritance, $propagation, $allow)))
    Set-Acl -LiteralPath $configDirectory -AclObject $directoryAcl
}

if ($PSCmdlet.ShouldProcess($ConfigPath, "Restrict file ACL to SYSTEM and $UserName")) {
    $fileAcl = New-Object System.Security.AccessControl.FileSecurity
    $fileAcl.SetOwner($account)
    $fileAcl.SetAccessRuleProtection($true, $false)
    $fileAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($account, $fullControl, $allow)))
    $fileAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($system, $fullControl, $allow)))
    Set-Acl -LiteralPath $ConfigPath -AclObject $fileAcl
}

Write-Host "Protected rclone configuration ACLs without reading configuration contents."
Write-Host "Directory: $configDirectory"
Write-Host "File:      $ConfigPath"
Write-Host "Allowed:   NT AUTHORITY\SYSTEM; $UserName"
