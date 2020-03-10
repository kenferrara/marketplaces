#Requires -Module Az.Compute

param 
(
    [ValidateSet("eoc", "ets", "ipam", "ncm", "npm", "nta", "la", "sam", "scm", "srm", "udt", "vman", "vnqm", "wpm")] [string] [Parameter(Mandatory = $true)] $Product,
    [string] [Parameter(Mandatory = $true)] $Password,
    [string] [alias("ResourceGroupLocation")] $Location = "westeurope",
    [string] $ParametersFile,
    [string] $DscSourceFolder = ".\common\DSC",
    [string] $ResourceGroupName,
    [string] $VNetResourceGroupName,
    [string] $VnetName,
    [string] $SubnetName,
    [string] $PublicIpResourceGroupName,
    [string] $PublicIpAddressName,
    [string] $PublicIpDns,
    [switch] $SkipDeploy,
    [switch] $BuildPackage
)

if (-not (Test-Path ".\Deploy-AzTemplate.ps1")) {
    Invoke-WebRequest "https://github.com/Azure/azure-quickstart-templates/raw/master/Deploy-AzTemplate.ps1" -UseBasicParsing -OutFile "Deploy-AzTemplate.ps1"
}
if (-not (Test-Path ".\SideLoad-AzCreateUIDefinition.ps1")) {
    Invoke-WebRequest "https://github.com/Azure/azure-quickstart-templates/raw/master/SideLoad-AzCreateUIDefinition.ps1" -UseBasicParsing -OutFile "SideLoad-AzCreateUIDefinition.ps1"
}

Write-Host "Building $($Product.ToUpper())..."
$Product = $Product.ToLower()
$Guid = New-Guid
$WorkFolder = ".\$Product\templates"
$DscFolder = "$WorkFolder\DSC"
$InstallerFolder = "$WorkFolder\installer"
$SilentConfigFolder = "$WorkFolder\config"

$SilentConfigFileName = "standard.xml"
$MainTemplateFileName = "mainTemplate.json"
$AzureDeployParametersFileName = "azuredeploy.parameters.json"
$UiDefinitionFileName = "createUiDefinition.json"

$SilentConfigFilePath = "$SilentConfigFolder\$SilentConfigFileName"
$MainTemplateFilePath = "$WorkFolder\$MainTemplateFileName"
$AzureDeployParametersFilePath = "$WorkFolder\$AzureDeployParametersFileName"
$UiDefinitionFilePath = "$WorkFolder\$UiDefinitionFileName"

$ProductNames = @{
    WPM  = "Web Performance Monitor"
    VNQM = "VoIP & Network Quality Manager"
    LA   = "Log Analyzer"
    NCM  = "Network Configuration Manager"
    VMAN = "Virtualization Manager"
    SRM  = "Storage Resource Monitor"
    NPM  = "Network Performance Monitor";
    NTA  = "NetFlow Traffic Analyzer";
    UDT  = "User Device Tracker";
    IPAM = "IP Address Manager";
    ETS  = "Engineers Toolset";
    SAM  = "Server & Application Monitor";
    EOC  = "Enterprise Operations Console";
    SCM  = "Server Configuration Monitor";
}

if (-not $ResourceGroupName) {
    $ResourceGroupName = "rg-test-$Product"
}
Write-Host "Resource Group: $ResourceGroupName"

Write-Host "Creating a folder structure..."
if (-not (Test-Path $DscFolder)) {
    New-Item $DscFolder -ItemType "Directory"
}
if (-not (Test-Path $InstallerFolder)) {
    New-Item $InstallerFolder -ItemType "Directory"
}
if (-not (Test-Path $SilentConfigFolder)) {
    New-Item $SilentConfigFolder -ItemType "Directory"
}

Write-Host "Creating DSC archives..."
if (Test-Path $DscSourceFolder) {
    $DscSourceFilePaths = @(Get-ChildItem $DscSourceFolder -File -Filter '*.ps1' | ForEach-Object -Process { $_.FullName })
    foreach ($DscSourceFilePath in $DscSourceFilePaths) {
        $DscZipFileName = (Split-Path $DSCSourceFilePath -Leaf).Split(".")[0] + ".zip"
        $DscArchiveFilePath = "$DscFolder\$DscZipFileName"
        Write-Host "Creating and copying DSC configurations to $DscArchiveFilePath ..."
        Publish-AzVMDscConfiguration $DscSourceFilePath -OutputArchivePath $DscArchiveFilePath -Force -Verbose
    }
}

Write-Host "Copying installers to $WorkFolder\installer..."
Copy-Item -Path ".\common\installer\*.exe" -Destination $InstallerFolder -Recurse

Write-Host "Copying provisioning scripts to $WorkFolder..."
Copy-Item -Path ".\common\provisioning\*" -Destination $WorkFolder -Recurse

$TemplateParameters = @"
{ 
    product: '$Product',
    productToInstall: '$(if($Product -eq 'la') { "OrionLogManager" } else { $Product.ToUpper() })',
    productFull: '$($ProductNames[$Product])', 
    productUpper: '$($Product.ToUpper())', 
    additionalDatabase: '$(if($Product -eq "nta" -or $Product -eq "la") { "true" } else {"false" })',
    la: '$(if($Product -eq "la") { "true" } else {"false" })',
    nta: '$(if($Product -eq "nta") { "true" } else {"false" })' }
"@

Write-Host "Template parameters: $TemplateParameters"
Write-Host "Processing configuration template and saving to $SilentConfigFilePath"
& ".\Build-Template.ps1" -TemplatePath ".\common\templates\$SilentConfigFileName.mustache" -OutputFile $SilentConfigFilePath -Parameters $TemplateParameters

Write-Host "Processing UI definition template and saving to $UiDefinitionFilePath"
& ".\Build-Template.ps1" -TemplatePath ".\common\templates\$UiDefinitionFileName.mustache" -OutputFile $UiDefinitionFilePath -Parameters $TemplateParameters

Write-Host "Processing main template and saving to $MainTemplateFilePath"
& ".\Build-Template.ps1" -TemplatePath ".\common\templates\$MainTemplateFileName.mustache" -OutputFile $MainTemplateFilePath -Parameters $TemplateParameters

if ($BuildPackage) {
    Write-Host "Building a deployment package..."
    $outputPath = ".\.build\$Product\"
    if (-not (Test-Path $outputPath)) {
        New-Item $outputPath -ItemType "Directory"
    }

    $date = Get-Date -Format "yyyy_MM_dd"
    Get-ChildItem -Path $WorkFolder -Exclude $AzureDeployParametersFileName |
    Compress-Archive -DestinationPath "$outputPath\$Product-$date.zip" -Update
}

if ($ParametersFile) {
    Copy-Item -Path $ParametersFile -Destination $AzureDeployParametersFilePath
}
else {
    $TemplateParameters = @"
    { 
        location: '$Location',
        product: '$Product',
        password: '$Password',
        guid: '$Guid',
        resourceGroup: '$ResourceGroupName',
        isNta: '$(if($Product -eq "nta") { "true" } else {"false" })'
        $( if($VNetResourceGroupName) {
            @"
            ,existingVnet: {
                vnet: "$VnetName",
                subnet: "$SubnetName",
                resourceGroup: "$VNetResourceGroupName"  
            }
"@      })
        $( if($PublicIpResourceGroupName) {
            @"
            ,existingIp: {
                ipName: "$PublicIpAddressName",
                ipDns: "$PublicIpDns",
                resourceGroup: "$PublicIpResourceGroupName"  
            }
"@      })
    }
"@

    Write-Host "Template parameters: $TemplateParameters"
    Write-Host "Processing deployment parameters and saving to $AzureDeployParametersFilePath"
    & ".\Build-Template.ps1" -TemplatePath  ".\common\templates\$AzureDeployParametersFileName.mustache" `
        -OutputFile $AzureDeployParametersFilePath `
        -Parameters $TemplateParameters
}

if ($SkipDeploy) {
    Write-Host "Configuration for $Product has been created"
    Write-Host "Skipping deployment..."
    exit
}

Write-Host "Starting deployment..."
& ".\Deploy-AzTemplate.ps1" -ArtifactStagingDirectory $WorkFolder -Location $Location -ResourceGroupName $ResourceGroupName
