# Azure Orion ARM Templates

Each of products in this repository has following files necessary for deployment:
* mainTemplate.json - ARM template
* createUiDefinition.json - definition of UI for Markeplace offer
* config/standard.xml - configuration file for silent installer

## Requirements

This repository uses [Mustache](https://mustache.github.io) logic-less templates for easier maintenance of ARM template, UI definition file and others.

To run scripts in this repository you will need:

1. [PowerShell 6.2.4](https://github.com/PowerShell/PowerShell/releases/tag/v6.2.4) (*PowerShell 7 has problem with Poshstache at the moment*)
2. [Azure PowerShell module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps)

   ```powershell
   Install-Module -Name Az -AllowClobber -Scope CurrentUser
   ```

3. [Poshstache](https://github.com/baldator/Poshstache) module 

   ```powershell
   Install-Module Poshstache
   ```

   *If you want to install only for current user use -Scope switch as in Azure PowerShell module installation instruction*

## How to build each product package and test templates

You can build a package for each product using *BuildDeploy-AzTemplate.ps1*. This script will create necessary files from templates (e.g. ARM template, UI definition and other dependencies), copy necessary files to correct structure and place all of those in products folder. 

It also might prepare a \*.zip file for you containing all files for deployment of offer.

### Example

*Building a package for SCM*

```powershell
.\BuildDeploy-AzTemplate.ps1 -Product scm -Password N0tS3cur3P4$$w0rd
```

### Available options:

* **-Product** (mandatory)

   Defines product for which script should build a deployment package along with all templates

* **-Password** (mandatory) 

  Defines password that will be used for resources deployed on Azure for testing
* **-Location** (default: "westeurope") 

  Region where Azure resources will be deployed for testing
* **-ParametersFile** 

  [JSON with parameters](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/deploy-powershell#deploy-local-template) that will be passed to ARM temlate as input during testing 
* **-DscSourceFolder** (default: ".\common\DSC") 

  Folder where DSC extensions should be placed and from which 

* **-ResourceGroupName** (default: rg-test-\<product\>) 

  Resource group name that will be used for deploying product for test

* **-SkipDeploy** 

    If specified, script will not deploy offer to Azure for test

* **-BuildPackage** 

  If specified, script will build a package (*.zip) in *.build* folder

*If you want to specify an existing VNet which offer should be use for test, you have to provide values for 3 parameters below*

* **-VNetResourceGroupName**

  Resource group name where Vnet exists. **It has to be in the same location as a location where other resources will be created.**

* **-VnetName**

  Name of existing Vnet

* **-SubnetName**

  Name of existing subnet

*If you want to specify an existing public IP address which offer should be use for test, you have to provide values for 3 parameters below*

* **-PublicIpResourceGroupName**

  Resource group name where public IP address exists. **It has to be in the same location as a location where other resources will be created.**

* **-PublicIpAddressName**

  Name of existing IP address

* **-PublicIpDns**

  DNS name of existing IP address

## How to test UI

You can test UI definition file on Azure using 2 methods:

1. Using *SideLoad-AzCreateUIDefinition.ps* script

   When you run *BuildDeploy-AzTemplate.ps1* for first time, it will download 2 scripts that can be used for ARM template and UI definition development from [azure-quickstart-templates](https://github.com/Azure/azure-quickstart-templates) repository. One of them can be used to side load a UI definition and preview it in browser

   ### Example

   ```powershell
   .\SideLoad-AzCreateUIDefinition.ps1 -ArtifactsStagingDirectory .\scm\templates
   ```

2. Using Azure Portal

   Go to [Create UI Definition Sandbox](https://portal.azure.com/?feature.customPortal=false#blade/Microsoft_Azure_CreateUIDef/SandboxBlade), paste your UI definition to the windows and click *Preview >>* button to check how UI works. 

   To see outputs of UI, you can either download output on the last screen or check outputs in browser's console.

## How to build all products

If you want to apply changes or prepare packages for all products at once, you can use *Update-AllProducts.ps1* script

```powershell
 .\Update-AllProducts.ps1 -Password N0tS3cur3P4$$w0rd -BuildPackage
```

### Available options:

* **-Password** (mandatory)

  Defines password that will be used for resources deployed on Azure for testing

* **-BuildPackage** 

  If specified, script will build a packages (\*.zip) for all products in *.build* folder

