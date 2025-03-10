# Original Script by @batetech shared with permission.
# This script makes the changes described in https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/troubleshoot-windows-update-error-0x80072efe-with-cipher-suite-configuration
# This will also fix issues where PowerShell modules can no longer be installed.
# See also https://github.com/d365collaborative/d365fo.tools/issues/874
# gist at https://gist.github.com/FH-Inway/193a2819c2682e203496ae7d44baecdb

# Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop';
$regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002';
$ciphers = Get-ItemPropertyValue "$regPath" -Name 'Functions';
Write-host "Values before: $ciphers";
$cipherList = $ciphers.Split(',');
$updateReg = $false;
if ($cipherList -inotcontains 'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384') {
    Write-Host "Adding TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384";
    $ciphers += ',TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384';
    $updateReg = $true;
}
if ($cipherList -inotcontains 'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA256') {
    Write-Host "Adding TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA256";
    $ciphers += ',TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA256';
    $updateReg = $true;
}
if ($updateReg) {
    Set-ItemProperty "$regPath" -Name 'Functions' -Value "$ciphers";
    $ciphers = Get-ItemPropertyValue "$regPath" -Name 'Functions';
    write-host "Values after: $ciphers";
    Restart-Computer -Force;
}
else {
    Write-Host 'No updates needed, the required ciphers already exist.';
}