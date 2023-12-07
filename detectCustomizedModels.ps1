# Define the root directory
$rootDir = "K:\AOSService\PackagesLocalDirectory"

# Get all directories under the root directory
$directories = Get-ChildItem -Path $rootDir -Directory | Sort-Object -Descending

# Process each directory
foreach ($dir in $directories) {
    # Define the path to the descriptor XML file
    $xmlFilePath=Join-Path -Path $dir.FullName -ChildPath "Descriptor\"
    $descriptors=Get-ChildItem -Path $xmlFilePath -Include "*.xml" -Recurse -ErrorAction SilentlyContinue
  
    foreach ($descriptor in $descriptors) {

        if (($null -ne $descriptor) -and (Test-Path -Path $descriptor.FullName -ErrorAction Ignore)) {
            # Load the XML content
            [xml]$xmlContent = Get-Content -Path $descriptor.FullName

            # Check the value of AxModelInfo.Customization attribute
            if (($xmlContent.AxModelInfo.Customization -eq "Allow") `
                -and ($xmlContent.AxModelInfo.Publisher -ne "Microsoft Corporation") ) {
                Write-Host "$($xmlContent.AxModelInfo.ModelModule) is a customizable model"
            }
        }
    }
}
