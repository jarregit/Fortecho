<#
Author/Owner: Jarre
Creation date: 2022
Responsible email (not personal, but e-mail list): ---
RT-Ticket (if applicable): internal

Revisions


.SYNOPSIS
  Alarms from Fortecho. TCP-listener 
.DESCRIPTION
  Creates alarms in Lenel OnGuard from Fortecho alarms
.NOTES
  Author     : JarrE
.LINK
.EXAMPLE
.INPUTTYPE
  csv-ish
.RETURNVALUE
  None
.COMPONENT
#>

$configXML = Select-Xml -Path "$scriptpath\fortechoalarm.xml" -XPath "//Fortecho"
$config = $configXML.Node

# Initialisering
$date = get-date -format "dd.MM"
$global:logfile = $config.LoggFil+$date+".log" 
$option = [System.StringSplitOptions]::RemoveEmptyEntries

# Invok-Wmi-method with parameters in right order...
# NB! argumentenes rekkefølge MÅ være riktig

# Rekkefølge:
#$class = [wmiclass]"Root\OnGuard:Lnl_IncomingEvent"
#$methodname = 'SendIncomingEvent'
#$class.psbase.GetMethodParameters($methodname).Properties 

Function Send-Alarm {
  param($Source ,$Device, $SubDevice, $Description)
  $Time=$nul
  $IsAccessGrant=$nul
  $IsAccessDeny=$nul
  $BadgeID=$nul
  $ExtendedID=$nul

  Write-Output "Send-Alarm $Source, $Device, $SubDevice, $Description, $Time, $IsAccessGrant, $IsAccessDeny, $BadgeID, $ExtendedID"  | Out-File -FilePath $logFile -Append

  Invoke-WmiMethod -Namespace Root\OnGuard  -Class Lnl_IncomingEvent  -Name SendIncomingEvent -ArgumentList $null, $Description, $Device, $null, False, False, $Source, $SubDevice
}

# Listener receiving alarms:
Function Receive-TCPMessage {
    Param ( 
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()] 
        [int] $Port
    ) 
    Process {
        Try { 
            # Set up endpoint and start listening
            $endpoint = new-object System.Net.IPEndPoint([ipaddress]::any,$port) 
            $listener = new-object System.Net.Sockets.TcpListener $EndPoint
            $listener.start() 
            Write-Output "Start" | Out-File -FilePath $logFile -Append
 
            # Wait for an incoming connection 
            $data = $listener.AcceptTcpClient() 
        
            # Stream setup
            $stream = $data.GetStream() 
            $bytes = New-Object System.Byte[] 1024
            #Write-Output $bytes
            # Read data from stream and write it to host
            while (($i = $stream.Read($bytes,0,$bytes.Length)) -ne 0){
                write-output $bytes
                $EncodedText = New-Object System.Text.ASCIIEncoding
                $data = $EncodedText.GetString($bytes,0, $i)
                Write-Output  $data | Out-File -FilePath $logFile -Append
                try {
                  $data2 = $data.Replace('<?xml version="1.0" encoding="utf-8" standalone="yes"?>','')
                  $usableXml = [xml]$data2
                  $dimp = $usableXml.tx_data.MobID
                  $melding = $usableXml.tx_data.Data

# Edit 02.05.2022
$part1 = $($melding.split(',',2,$option))[0]
($melding,$part2) = $part1.split(':',2,$option)
#$part2 = $($part1.split(':',2,$option))[1]
$part2 = $part2.Trim()
($device, $subdevice) = $part2.split('-',2,$option)
$device = $device.Trim()
$subdevice = $part2 # Ha med bygg i subdevice
                  Write-Output  "Send-Alarm -Source 'FortechoSource' -Device $device -SubDevice $subdevice  -Description $melding" | Out-File -FilePath $logFile -Append
                  Send-Alarm -Source 'FortechoSource' -Device $device -SubDevice $subdevice  -Description $melding

                } Catch {
                  Write-Output "Bad luck Charlie" | Out-File -FilePath $logFile -Append
                }
            }
         
            # Close TCP connection and stop listening
            $stream.close()
            $listener.stop()
        }
        Catch {
            "Receive Message failed with: `n" + $Error[0]
        }
    }
}


### Port defineres i Pager IP Setup i Fortecho
Receive-TCPMessage -Port 12345

