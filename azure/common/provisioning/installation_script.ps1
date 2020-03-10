param
(
	[string]$silentConfigUri,
	[string]$installerUri,
	[string]$dbServerName, 
	[string]$databaseName, 
	[string]$dbUserName, 
	[string]$dbPassword,
	[string]$ntaDBServerName,
	[string]$ntaDBName,
	[string]$ntaDBUserName,
	[string]$ntaDBPassword,
	[string]$laDBServerName,
    [string]$laDBName,
    [string]$laDBUserName,
    [string]$laDBPassword,
	[string]$appUserPassword,
	[string]$vmName
)

function Invoke-Request {
	param 
	(
		[string]$Uri,
		[string]$OutFile,
		[int]$MaximumRetryCount = 1,
		[int]$RetryIntervalSec = 10
	)

	[string]$StatusText = ""
	[int]$Tries = 0
	[bool]$Success = $false

	do {
		$Tries++

		try { 
			Invoke-WebRequest -Uri $Uri -OutFile $OutFile -ErrorAction Stop
			$StatusText = "Invoke-WebRequest ($Uri) completed succesfully."
			$Success = $true
		} 
		catch { 
			if ($_.Exception.Response.StatusCode) {
				$StatusCode = $_.Exception.Response.StatusCode
				$StatusCodeInt = $StatusCode.value__
				$StatusText = "Invoke-WebRequest ($Uri) return $StatusCode ($StatusCodeInt)"
			}
			else {
				$StatusText = "Invoke-WebRequest ($Uri) error $($_.Exception)"
			}
		}

		Write-Host "[$Tries/$MaximumRetryCount] $StatusText"
		if (($Success -eq $false) -and ($Tries -ne $MaximumRetryCount)) {
			Write-Host "[$Tries/$MaximumRetryCount] Waiting $RetryIntervalSec seconds for another try."
			Start-Sleep $RetryIntervalSec
		}
	} 
	while (($Success -ne $true) -and ($Tries -lt $MaximumRetryCount)) 
}

Start-Transcript -Path C:\postinstall.Log

#download the silent installer config file from Artifacts
Write-Host "Downloading silent installer config file from $silentConfigUri"; [datetime]::Now
$configfilePath = "C:\Windows\Temp\silentconfig.xml"
Invoke-Request -Uri $silentConfigUri -OutFile $configfilePath -MaximumRetryCount 3 -RetryIntervalSec 30
Write-Host "Download Silent installer config file Completed"; [datetime]::Now

#download the installer from Artifacts
Write-Host "Downloading installer from $installerUri"; [datetime]::Now
$installer_name = "Solarwinds-Orion-Installer.exe"
Invoke-Request -Uri $installerUri -OutFile "C:\Windows\Temp\$installer_name" -MaximumRetryCount 3 -RetryIntervalSec 30
Write-Host "Download installer Completed"; [datetime]::Now

#update DB details
$xml = New-Object XML
$xml.Load($configfilePath)

if ($xml.SilentConfig.Host.Info.Database) {
	$dbnode = $xml.SilentConfig.Host.Info.Database	
	$dbnode.ServerName = $dbServerName
	$dbnode.DatabaseName = $databaseName
	$dbnode.User = $dbUserName    
	$dbnode.UserPassword = $dbPassword
	$dbnode.AccountPassword = $dbPassword
}

if ($xml.SilentConfig.Host.Info.NetFlowConfiguration.FlowStorageConfig) {
	$nodeStorageConfig = $xml.SilentConfig.Host.Info.NetFlowConfiguration.FlowStorageConfig
	$nodeStorageConfig.ServerName = $ntaDBServerName
	$nodeStorageConfig.DatabaseName = $ntaDBName
	$nodeStorageConfig.User = $ntaDBUserName
	$nodeStorageConfig.UserPassword = $ntaDBPassword
	$nodeStorageConfig.AccountPassword = $ntaDBPassword
}

if ($xml.SilentConfig.Host.Info.OrionLogConfiguration.StorageConfig) {
    $nodeStorageConfig = $xml.SilentConfig.Host.Info.OrionLogConfiguration.StorageConfig
    $nodeStorageConfig.ServerName = $laDBServerName
    $nodeStorageConfig.DatabaseName = $laDBName
    $nodeStorageConfig.User = $laDBUserName
    $nodeStorageConfig.UserPassword = $laDBPassword
    $nodeStorageConfig.AccountPassword = $laDBPassword
}

if ($xml.SilentConfig.Host.Info.Website) {
	$nodeWebsite = $xml.SilentConfig.Host.Info.Website
	$nodeWebsite.DefaultAdminPassword = $appUserPassword
	$nodeWebsite.CertificateResolvableCN = $vmName
}

$xml.Save($configfilePath)

#create installer file
New-Item C:\Windows\Temp\installer.ps1 -ItemType file
Add-Content 'C:\Windows\Temp\installer.ps1' .\$installer_name" /s /ConfigFile=""$configfilePath"""

#Start installation
Write-Host ' starting installation solarwindinstaller....'; [datetime]::Now
Set-Location "C:\Windows\Temp"
.\installer.ps1
Write-Host ' installation started solarwindinstaller....'; [datetime]::Now

#check for if installation status
$process_name = $installer_name.Substring(0, $installer_name.LastIndexOf('.'))
while (1) {
	$Solarwinds = Get-Process $process_name -ErrorAction SilentlyContinue
	if ($Solarwinds) {
		Start-Sleep 5
		Remove-Variable Solarwinds
		continue;
	}
	else {
		Write-Host "process completed"; [datetime]::Now
		Remove-Variable Solarwinds
		break;
	}
}

#delete files created in installation process
Write-Host ' Deleting the files created in installation process'; [datetime]::Now

$installer_file = "C:\Windows\Temp\installer.ps1"
if (Test-Path $installer_file) {
	Remove-Item $installer_file
	write-host 'silent installer file deleted'; [datetime]::Now
}

Write-Host 'Files deleted which has been created in installation process'; [datetime]::Now 

Stop-Transcript