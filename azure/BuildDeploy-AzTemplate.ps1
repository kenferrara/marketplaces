#Requires -Module Az.Compute

param 
(
    [ValidateSet("eoc","ets","ipam","ncm","npm","nta","OrionLogManager","sam","scm","srm","udt","vman","vnqm","whd","wpm")] [string] [Parameter(Mandatory = $true)] $Product,
    [string] [Parameter(Mandatory = $true)] $Password,
    [string] [alias("ResourceGroupLocation")] $Location = "westeurope",
    [string] $DSCSourceFolder = ".\common\DSC",
    [string] $ResourceGroupName
)

$Guid = New-Guid
$WorkFolder = ".\$Product\templates"
$DscFolder = "$WorkFolder\DSC"
$InstallerFolder = "$WorkFolder\installer"

if (-not $ResourceGroupName) {
    $ResourceGroupName = "$Product-marketplaces-test"
}
if (-not (Test-Path $DscFolder)) {
    New-Item $DscFolder -ItemType "Directory"
}
if (-not (Test-Path $InstallerFolder)) {
    New-Item $InstallerFolder -ItemType "Directory"
}

if (Test-Path $DSCSourceFolder) {
    $DSCSourceFilePaths = @(Get-ChildItem $DSCSourceFolder -File -Filter '*.ps1' | ForEach-Object -Process { $_.FullName })
    foreach ($DSCSourceFilePath in $DSCSourceFilePaths) {
        $filename = (Split-Path $DSCSourceFilePath -Leaf).Split(".")[0] + ".zip"
        $DSCArchiveFilePath = "$DscFolder\$filename"
        Write-Host "Creating and copying DSC configurations to $DSCArchiveFilePath ..."
        Publish-AzVMDscConfiguration $DSCSourceFilePath -OutputArchivePath $DSCArchiveFilePath -Force -Verbose
    }
}

Write-Host "Copying installers to $WorkFolder\installer..."
Copy-Item -Path ".\common\installer\*.exe" -Destination $InstallerFolder -Recurse

Write-Host "Copying provisioning scripts to $WorkFolder..."
Copy-Item -Path ".\common\provisioning\*" -Destination $WorkFolder -Recurse

$azuredeploy = Get-Content ".\common\deployment\azuredeploy.parameters.json" -raw | ConvertFrom-Json
$parametersToPrefix = @("subnetName", "virtualNetworkName", "publicIpAddressName", "virtualMachineName")
$passwordsToReplace = @("dbPassword", "appUserPassword", "adminPassword")
$resourceGroupNames = @("publicIpResourceGroupName", "virtualNetworkRG")
$azuredeploy.parameters.PSObject.Properties | ForEach-Object { 
    if ($parametersToPrefix -contains $_.Name) { 
        $value = $_.Value.value
        $_.Value.value = "$Product-$value"
    } 
    if ($passwordsToReplace -contains $_.Name) { 
        $value = $_.Value.value
        $_.Value.value = $Password
    } 
    if ($resourceGroupNames -contains $_.Name) { 
        $value = $_.Value.value
        $_.Value.value = $ResourceGroupName
    } 
}
$azuredeploy.parameters.publicIpDns.value = "$Product-$Guid" 
$azuredeploy.parameters.dbServerName.value = "$Product-db-$Guid"
$azuredeploy | ConvertTo-Json -depth 32 | Set-Content "$WorkFolder\azuredeploy.parameters.json"

#Deploy
.\Deploy-AzTemplate.ps1 -ArtifactStagingDirectory $WorkFolder -Location $Location -ResourceGroupName $ResourceGroupName
