Configuration Net48Install
{
    param
    (
        [string]$installerUri
    )

    Import-DSCResource -Module PSDesiredStateConfiguration
   
    node "localhost"
    {

        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
        }

        Script Install_Net_4.8 {
            SetScript  = {
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

                Write-Verbose "Downloading installer ($using:installerUri)"
                $FileName = ($using:installerUri).Split('/')[-1].Split('?')[0] # remove SAS token as well if needed
                $BinPath = Join-Path $env:SystemRoot -ChildPath "Temp\$FileName"

                if (!(Test-Path $BinPath)) {
                    Invoke-Request -Uri $using:installerUri -OutFile $BinPath -RetryIntervalSec 30 -MaximumRetryCount 3
                }

                Write-Verbose "Installing .Net 4.8 from $BinPath"
                Write-Verbose "Executing $binpath /q /norestart"

                Start-Sleep 5
                Start-Process -FilePath $BinPath -ArgumentList "/q /norestart" -Wait -NoNewWindow            
                Start-Sleep 5

                Write-Verbose "Setting DSCMachineStatus to reboot server after DSC run is completed"
                $global:DSCMachineStatus = 1
            }

            TestScript = {
                [int]$NetBuildVersion = 528049

                if (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' | % { $_ -match 'Release' }) {
                    [int]$CurrentRelease = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Release
                    if ($CurrentRelease -lt $NetBuildVersion) {
                        Write-Verbose "Current .Net build version is less than 4.8 ($CurrentRelease)"
                        return $false
                    }
                    else {
                        Write-Verbose "Current .Net build version is the same as or higher than 4.8 ($CurrentRelease)"
                        return $true
                    }
                }
                else {
                    Write-Verbose ".Net build version not recognised"
                    return $false
                }
            }

            GetScript  = {
                if (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' | % { $_ -match 'Release' }) {
                    $NetBuildVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Release
                    return $NetBuildVersion
                }
                else {
                    Write-Verbose ".Net build version not recognised"
                    return ".Net 4.8 not found"
                }
            }
        }
    }
}