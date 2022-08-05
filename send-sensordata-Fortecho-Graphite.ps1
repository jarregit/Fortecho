<#
.Synopsis
   Test klimadata fra Fortecho til Grafana
.DESCRIPTION
   Sende klimadata fra FortechoDB til Graphite
.EXAMPLE
   run script
.NOTES
    Author  JarrE
#>


Import-Module SqlServer 

$configXML = Select-Xml -Path "$PSScriptRoot\klimadata.xml" -XPath "//Fortecho"
$config = $configXML.Node

# Initialisering
$date = get-date -format "dd.MM"
$global:logfile = $config.LoggFil+$date+".log" 

$fortecho_database = $config.FortechoDatabase 
$fortecho_dbserver = $config.FortechoDatabaseServer 


$Computer = $config.graphite_computer 
$Port = $config.graphite_port 
$Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
$Encoding = [System.Text.Encoding]::ASCII
$splitoption = [System.StringSplitOptions]::RemoveEmptyEntries
$EpochDate = -1 # = now

# Function for seding the data

function Send-GraphiteData
{
   [CmdletBinding()]
   Param([switch]$SendToGraphite,
         [string]$Data)

    # Establish a connection to grafitti
    Begin{
        
        # Establish the connection and a stream writer
        $Client = New-Object -TypeName System.Net.Sockets.TcpClient
        $Client.Connect($Computer, $Port)
        $Stream = $Client.GetStream()
        $Writer = New-Object -Type System.IO.StreamWriter -ArgumentList $Stream, $Encoding, $Client.SendBufferSize, $true
    }      
    
    Process{           
      # Send data to graphite
      if ($SendToGraphite) {
 
        # Send data
        $Writer.WriteLine($Data)
  #      Write-Output ($Data)
      } # End If
            
   } # End Process

    end {
        # Flush and close the connection send
        $Writer.Flush()
        $Writer.Dispose()
        $Client.Client.Shutdown('Send')
 
        # Read the response. More can be done here to catch reponse errors
        $Stream.ReadTimeout = [System.Threading.Timeout]::Infinite
        if ($Timeout -ne [System.Threading.Timeout]::InfiniteTimeSpan) {
            $Stream.ReadTimeout = $Timeout.TotalMilliseconds
            }
 
        $Result = ''
        $Buffer = New-Object -TypeName System.Byte[] -ArgumentList $Client.ReceiveBufferSize
        do {
            try {
                $ByteCount = $Stream.Read($Buffer, 0, $Buffer.Length)
            } 
                catch [System.IO.IOException] {
                $ByteCount = 0
            }
            if ($ByteCount -gt 0) {
                $Result += $Encoding.GetString($Buffer, 0, $ByteCount)
            }
        } 
        
        while ($Stream.DataAvailable -or $Client.Client.Connected)
       
        # Cleanup
        $Stream.Dispose()
        $Client.Dispose()
    }

}


## get data from database

### Temperatur 
$fortechosql1 = @"
Select Top (5) A.Marque, S.EvDate, S.ProcessedData, S.ProcessedMean, S.StandardDeviation, S.RawData, S.EvDateUTC
		FROM SensorData  S
		Left join [dbo].[Asset] A on A.TagKey = S.TagKey 
		WHERE SensorCode=4 
		ORDER BY EvDateUTC desc

"@

# Hente Fortecho Assets 
$ft_assets = Invoke-Sqlcmd -Query $fortechosql1 -Database $fortecho_database -ServerInstance $fortecho_dbserver
Write-Output $ft_assets | Out-File -FilePath $logFile -Append 

$Resolution = "resolution.15minly"
$marque = @()

$ft_assets | ForEach-Object {
  $navn = $_.Marque
  $navn = $($navn.ToLower()).Trim()
  $Temp = $_.ProcessedData

  $bygg = $($navn.split('-',2,$splitoption))[0]
  $bygg = $bygg.Trim()
  $navn = $navn -replace (' ','_')
  $FirstName = "eiendom.ua.test.fortecho." + $bygg 

  if ($navn -in $marque) { 
    Write-Output "$navn  Sendt" | Out-File -FilePath $logFile -Append  
    $LastName = 'temperatur'
    $tiden = $_.EvDate
    $EpochDate = [int][double]::Parse((Get-date $(($tiden).ToUniversalTime()) -UFormat %s))
    $Datatemp = "$Resolution.$FirstName.$navn.$LastName $Temp  $EpochDate"
    Write-Output "$tiden = $EpochDate ," | Out-File -FilePath $logFile -Append 
    Write-Output $Datatemp | Out-File -FilePath $logFile -Append 
    Send-GraphiteData -SendToGraphite -Data $Datatemp
    
    }
  else {
    Write-Output "$navn  ikke Sendt" | Out-File -FilePath $logFile -Append 

# Temperatur
    $LastName = 'temperatur'
    $tiden = $_.EvDate
    $EpochDate = -1
    $Datatemp = "$Resolution.$FirstName.$navn.$LastName $Temp  $EpochDate"
 #   Write-Output "$tiden = $EpochDate ," | Out-File -FilePath $logFile -Append 
    Write-Output $Datatemp | Out-File -FilePath $logFile -Append 
    Send-GraphiteData -SendToGraphite -Data $Datatemp
    $marque += $navn 
  }
}

# Tilbakestille....
$EpochDate = -1 # = now


### Luftfuktighet 
$fortechosql1 = @"
Select Top (5) A.Marque, S.EvDate, S.ProcessedData, S.ProcessedMean, S.StandardDeviation, S.RawData, S.EvDateUTC
		FROM SensorData  S
		Left join [dbo].[Asset] A on A.TagKey = S.TagKey 
		WHERE SensorCode=8
		ORDER BY EvDateUTC desc

"@

# Hente Fortecho Assets 
$ft_assets = Invoke-Sqlcmd -Query $fortechosql1 -Database $fortecho_database -ServerInstance $fortecho_dbserver
Write-Output $ft_assets | Out-File -FilePath $logFile -Append 

$Resolution = "resolution.15minly"
$marque = @()

$ft_assets | ForEach-Object {
  $navn = $_.Marque
  $navn = $($navn.ToLower()).Trim()
  $Temp = $_.ProcessedData

  $bygg = $($navn.split('-',2,$splitoption))[0]
  $bygg = $bygg.Trim()
  $navn = $navn -replace (' ','_')
  $FirstName = "eiendom.ua.test.fortecho." + $bygg 

  if ($navn -in $marque) { 
    Write-Output "$navn  Sendt" | Out-File -FilePath $logFile -Append  
    $LastName = 'luftfuktighet'
    $tiden = $_.EvDate
    $EpochDate = [int][double]::Parse((Get-date $(($tiden).ToUniversalTime()) -UFormat %s))

    $Datatemp = "$Resolution.$FirstName.$navn.$LastName $Temp  $EpochDate"
    Write-Output $Datatemp | Out-File -FilePath $logFile -Append 
    Send-GraphiteData -SendToGraphite -Data $Datatemp
    
    }
  else {
    Write-Output "$navn  ikke Sendt" | Out-File -FilePath $logFile -Append 
    $EpochDate = -1

# Luftfuktighet
    $LastName = 'luftfuktighet'
    $Datatemp = "$Resolution.$FirstName.$navn.$LastName $Temp  $EpochDate"
    Write-Output $Datatemp | Out-File -FilePath $logFile -Append 
    Send-GraphiteData -SendToGraphite -Data $Datatemp
    $marque += $navn 
  }
}


### Lys 
$fortechosql1 = @"
Select Top (5) A.Marque, S.EvDate, S.ProcessedData, S.ProcessedMean, S.StandardDeviation, S.RawData, S.EvDateUTC
		FROM SensorData  S
		Left join [dbo].[Asset] A on A.TagKey = S.TagKey 
		WHERE SensorCode=32
		ORDER BY EvDateUTC desc

"@

# Hente Fortecho Assets 
$ft_assets = Invoke-Sqlcmd -Query $fortechosql1 -Database $fortecho_database -ServerInstance $fortecho_dbserver
Write-Output $ft_assets | Out-File -FilePath $logFile -Append 

$Resolution = "resolution.15minly"
$marque = @()

$ft_assets | ForEach-Object {
  $navn = $_.Marque
  $navn = $($navn.ToLower()).Trim()
  $Temp = $_.ProcessedData

  $bygg = $($navn.split('-',2,$splitoption))[0]
  $bygg = $bygg.Trim()
  $navn = $navn -replace (' ','_')
  $FirstName = "eiendom.ua.test.fortecho." + $bygg 

  if ($navn -in $marque) { 
    Write-Output "$navn  Sendt" | Out-File -FilePath $logFile -Append 
    $tiden = $_.EvDate
    $EpochDate = [int][double]::Parse((Get-date $(($tiden).ToUniversalTime()) -UFormat %s))

# Luminositet
    $LastName = 'lys'
    $Datatemp = "$Resolution.$FirstName.$navn.$LastName $Temp  $EpochDate"
    Write-Output $Datatemp | Out-File -FilePath $logFile -Append 
    Send-GraphiteData -SendToGraphite -Data $Datatemp
    
    }
  else {
    Write-Output "$navn  ikke Sendt" | Out-File -FilePath $logFile -Append 
    $EpochDate = -1
# Luminositet
    $LastName = 'lys'
    $Datatemp = "$Resolution.$FirstName.$navn.$LastName $Temp  $EpochDate"
    Write-Output $Datatemp | Out-File -FilePath $logFile -Append 
    Send-GraphiteData -SendToGraphite -Data $Datatemp
    $marque += $navn 
  }
}
