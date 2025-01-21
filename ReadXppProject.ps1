param (
    [Parameter(Mandatory=$true, HelpMessage="Xpp project file path and name")]
    [string]$ProjectFile
)
[xml]$XppProjectContents = Get-Content -Path $ProjectFile

# Create an XmlNamespaceManager to handle the default namespace
$namespaceManager = New-Object System.Xml.XmlNamespaceManager($XppProjectContents.NameTable)
$namespaceManager.AddNamespace("ns", "http://schemas.microsoft.com/developer/msbuild/2003")

# Select nodes of interest using the namespace prefix
$nodes = $XppProjectContents.SelectNodes("//ns:Project/ns:ItemGroup/ns:Content/@Include", $namespaceManager)

foreach ($node in $nodes) {

    # Current file path
    $currentFilePath = $node.'#text'
    
    # Destination file path
    $destinationFilePath = Join-Path -Path $destinationDirectory -ChildPath (Split-Path -Leaf $currentFilePath)

    # Move the file
    Move-Item -Path $currentFilePath -Destination $destinationFilePath

    # Update the XML node with the new path
    $node.'#text' = $destinationFilePath
}

#| Where-Object $_.Content -cne "" 
