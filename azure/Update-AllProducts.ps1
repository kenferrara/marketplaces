[CmdletBinding()]
param (
    [string] [Parameter(Mandatory = $true)] $Password,
    [switch] $BuildPackage
)

$Products = @('WPM', 'VNQM', 'LA', 'NCM', 'VMAN', 'SRM', 'NPM', 'NTA', 'UDT', 'IPAM', 'ETS', 'SAM', 'EOC', 'SCM')

foreach ($Product in $Products) {
    if ($BuildPackage) {  
        & ".\BuildDeploy-AzTemplate.ps1" -Product $Product -Password $Password -SkipDeploy -BuildPackage
    } else {
        & ".\BuildDeploy-AzTemplate.ps1" -Product $Product -Password $Password -SkipDeploy
    }
   
}
