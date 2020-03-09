#Requires -Module Az.Compute

param 
(
    [ValidateSet("eoc", "ets", "ipam", "ncm", "npm", "nta", "OrionLogManager", "sam", "scm", "srm", "udt", "vman", "vnqm", "whd", "wpm")] [string] [Parameter(Mandatory = $true)] $Product,
    [string] [Parameter(Mandatory = $true)] $Password,
    [string] [alias("ResourceGroupLocation")] $Location = "westeurope",
    [string] $ParametersFile = ".\common\deployment\azuredeploy.parameters.json",
    [string] $DSCSourceFolder = ".\common\DSC",
    [string] $ResourceGroupName,
    [string] $VNetResourceGroupName,
    [string] $PublicIpResourceGroupName,
    [string] $PublicIpAddressName,
    [string] $PublicIpDns,
    [switch] $SkipParametersUpdate,
    [switch] $SkipDeploy,
    [switch] $BuildPackage
)

if (-not (Test-Path ".\Deploy-AzTemplate.ps1")) {
    Invoke-WebRequest "https://github.com/Azure/azure-quickstart-templates/raw/master/Deploy-AzTemplate.ps1" -UseBasicParsing -OutFile "Deploy-AzTemplate.ps1"
}
if (-not (Test-Path ".\SideLoad-AzCreateUIDefinition.ps1")) {
    Invoke-WebRequest "https://github.com/Azure/azure-quickstart-templates/raw/master/SideLoad-AzCreateUIDefinition.ps1" -UseBasicParsing -OutFile "SideLoad-AzCreateUIDefinition.ps1"
}

$Guid = New-Guid
$WorkFolder = ".\$Product\templates"
$DscFolder = "$WorkFolder\DSC"
$InstallerFolder = "$WorkFolder\installer"
$SilentConfigFolder = "$WorkFolder\config"
$SilentConfigFile = "$SilentConfigFolder\standard.xml"

if (-not $ResourceGroupName) {
    $ResourceGroupName = "rg-test-$Product"
}

if (-not (Test-Path $DscFolder)) {
    New-Item $DscFolder -ItemType "Directory"
}
if (-not (Test-Path $InstallerFolder)) {
    New-Item $InstallerFolder -ItemType "Directory"
}
if (-not (Test-Path $SilentConfigFolder)) {
    New-Item $SilentConfigFolder -ItemType "Directory"
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

if (-not (Test-Path $SilentConfigFile)) {
    Write-Host "Copying default silent installer configuration to $SilentConfigFile"
    Copy-Item -Path ".\common\config\standard.xml" -Destination $SilentConfigFile
    $fullConfigFilePath = (Resolve-Path -Path $SilentConfigFile).Path

    Write-Host "Setting application to install to ${$Product.ToUpper()}"
    $xml = New-Object XML
    $xml.Load($fullConfigFilePath)
    $xml.SilentConfig.InstallerConfiguration.ProductsToInstall = $Product.ToUpper()
    $xml.Save($fullConfigFilePath)
}

if ($BuildPackage) {
    $outputPath = ".\.build\$Product\"
    if (-not (Test-Path $outputPath)) {
        New-Item $outputPath -ItemType "Directory"
    }

    $date = Get-Date -Format "yyyy_MM_dd"
    Write-Host "Building a deployment package..."
    Get-ChildItem -Path $WorkFolder -Exclude "azuredeploy.parameters.json" |
    Compress-Archive -DestinationPath "$outputPath\$Product-$date.zip" -Update
}

# Exit if deployment is not needed
if ($SkipDeploy) {
    Write-Host "Configuration for $Product has been created"
    Write-Host "Skipping deployment..."
    exit
}

if ($SkipParametersUpdate) {
    Copy-Item -Path $ParametersFile -Destination "$WorkFolder\azuredeploy.parameters.json"
}
else {
    $azuredeploy = Get-Content $ParametersFile -raw | ConvertFrom-Json
    $parametersToSuffix = @("subnetName", "virtualNetworkName", "publicIpAddressName", "virtualMachineName")
    $passwordsToReplace = @("dbPassword", "appUserPassword", "adminPassword")
    $vnetResourceGroupNames = @("publicIpResourceGroupName", "virtualNetworkRG")
    $azuredeploy.parameters.PSObject.Properties | ForEach-Object { 
        if ($parametersToSuffix -contains $_.Name) { 
            $value = $_.Value.value
            $_.Value.value = "$value-$Product"
        } 
        if ($passwordsToReplace -contains $_.Name) { 
            $value = $_.Value.value
            $_.Value.value = $Password
        } 
        if ($vnetResourceGroupNames -contains $_.Name) { 
            $value = $_.Value.value
            $_.Value.value = $ResourceGroupName
        } 
    }
    if ($VNetResourceGroupName) {
        $azuredeploy.parameters.virtualNetworkNewOrExisting.value = "existing"     
        $azuredeploy.parameters.virtualNetworkRG.value = $VNetResourceGroupName
    }

    if ($PublicIpResourceGroupName) {
        $azuredeploy.parameters.publicIpNewOrExisting = "existing"
        $azuredeploy.parameters.publicIpResourceGroupName.value = $ResourceGroupName
    }
    if ($PublicIpAddressName) {
        $azuredeploy.parameters.publicIpAddressName = $PublicIpAddressName
    }
    if ($PublicIpDns) {
        $azuredeploy.parameters.publicIpDns = $PublicIpDns
    }
    else {
        $azuredeploy.parameters.publicIpDns.value = "web-$Product-$Guid" 
    }

    $azuredeploy.parameters.dbServerName.value = "sqldb-test-$Product-$Guid"
    $azuredeploy | ConvertTo-Json -depth 32 | Set-Content "$WorkFolder\azuredeploy.parameters.json"
}

#Deploy
.\Deploy-AzTemplate.ps1 -ArtifactStagingDirectory $WorkFolder -Location $Location -ResourceGroupName $ResourceGroupName
