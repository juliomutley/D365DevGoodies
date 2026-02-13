# Run as Administrator

# Path to RSReportServer.config
$configPath = "C:\Program Files\Microsoft SQL Server Reporting Services\SSRS\ReportServer\RSReportServer.config"

# Load XML
[xml]$config = Get-Content $configPath

# Check if RdlSandboxing element exists
$rdlNode = $config.SelectSingleNode("//RDLSandboxing")

if (-not $rdlNode) {
    # Create the RDLSandboxing node and add it to the Configuration element
    $rdlNodeNew = $config.CreateElement("RDLSandboxing")

    $rdlNodeNew.InnerXml = @"

   <MaxExpressionLength>5000</MaxExpressionLength>
   <MaxResourceSize>5000</MaxResourceSize>
   <MaxStringResultLength>3000</MaxStringResultLength>
   <MaxArrayResultLength>250</MaxArrayResultLength>

"@
    $config.Configuration.AppendChild($rdlNodeNew) | Out-Null
}
else {
    write-host "RdlSandboxing already enabled."
    exit
}

# Save changes
$config.Save($configPath)
Write-Host "✅ RDL Sandboxing enabled in $configPath"

# Restart SSRS service to apply changes
Restart-Service -Name "SQLServerReportingServices" -Force
Write-Host "🔄 SSRS service restarted."
