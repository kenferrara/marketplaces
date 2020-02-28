#Requires -Module Az.Compute

param 
(
    [ValidateSet("eoc","ets","ipam","ncm","npm","nta","OrionLogManager","sam","scm","srm","udt","vman","vnqm","whd","wpm")] [string] [Parameter(Mandatory = $true)] $Product,
    [string] [alias("ResourceGroupLocation")] $Location = "westeurope",
    [string] $DSCSourceFolder = ".\common\DSC"
)

$WorkFolder = ".\$Product\templates"

# Create DSC configuration archive
if (Test-Path $DSCSourceFolder) {
    $DSCSourceFilePaths = @(Get-ChildItem $DSCSourceFolder -File -Filter '*.ps1' | ForEach-Object -Process { $_.FullName })
    foreach ($DSCSourceFilePath in $DSCSourceFilePaths) {
        $DSCArchiveFilePath = $DSCSourceFilePath.Substring(0, $DSCSourceFilePath.Length - 4) + '.zip'
        Publish-AzVMDscConfiguration $DSCSourceFilePath -OutputArchivePath $DSCArchiveFilePath -Force -Verbose
    }
}

#Copy installers
Copy-Item -Path ".\common\installer\*.exe" -Destination "$WorkFolder\installer" -Recurse

#Copy provisioning scripts
Copy-Item -Path ".\common\provisioning\*" -Destination "$WorkFolder" -Recurse

#Deploy
.\Deploy-AzTemplate.ps1 -ArtifactStagingDirectory $WorkFolder -Location $Location

