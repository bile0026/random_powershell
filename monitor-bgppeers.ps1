# Monitor Status of BGP Peers in Cisco Devices using bgpPeerState within 1.3.6.1.2.1.15.3.1.2 in PRTG (Summaries) v0.5 10/01/2017
# Originally published here: https://kb.paessler.com/en/topic/25313
#
# Modified heavily by Zachary Biles to include other parameters and set some default limits. Other information polled is 
# number of received prefixes, and AS numbers. 
#
# Version 2: created 4/9/2020
#
#
# Parameters in PRTG should be (pulls from definied fields in the PRTG "Device"): 
# -hostaddr '%host' -community '%snmpcommunity' -port '161' -timeout '5'
# Alternatively (without placeholders):
# -hostaddr 'myrouter.domain.tld' -community 'public' -port '161' -timeout '5'
#
# Requites net-snmp installed and in the path since it will use snmpwalk.exe (http://www.net-snmp.org/)
#
# It's recommended to use large scanning intervals for exe/xml scripts. (Not below 300 seconds)


param(
    [string]$hostaddr = "<single device IP>",
    [string]$community = "<snmp string>",
    [string]$port = "161",
    [string]$timeout = "5",
    [string]$troubleshooting = 0
)

$version = "0.5"

$queryMeasurement = [System.Diagnostics.Stopwatch]::StartNew()
#get peer info
$walkresult = (snmpwalk.exe -Ln -On -v 2c -c $community $hostaddr":"$port ".1.3.6.1.2.1.15.3.1.2" -t $timeout 2>&1)
#get received routes
$walkresult2 = (snmpwalk.exe -Ln -On -v 2c -c $community $hostaddr":"$port "1.3.6.1.4.1.9.9.187.1.2.4.1.1" -t $timeout 2>&1)
#get local asn
$walkresult3 = (snmpwalk.exe -Ln -On -v 2c -c $community $hostaddr":"$port "1.3.6.1.2.1.15.2" -t $timeout 2>&1)
$localASN = $walkresult3.Substring($walkresult3.Length-5)
#get remote asn
$walkresult4 = (snmpwalk.exe -Ln -On -v 2c -c $community $hostaddr":"$port "1.3.6.1.2.1.15.3.1.9" -t $timeout 2>&1)

#build list of peer IP<>ASN pairs
foreach($peerPair in $walkresult4){
    $peerIP = $peerPair
    $peerASN = $peerPair.Substring($peerPair.Length-5)
    ################################################################################################ finish pairing the remote IPs with ASNs
    $remoteASNs += [PSCustomObject] @{
        peerIP = $peerIP
        peerASN = $peerASN
    } 
}

if ($troubleshooting -eq 1){
    snmpwalk.exe -Ln -On -v 2c -c $community $hostaddr":"$port ".1.3.6.1.2.1.15.3.1.2" -t $timeout
    snmpwalk.exe -Ln -On -v 2c -c $community $hostaddr":"$port "1.3.6.1.4.1.9.9.187.1.2.4.1.1" -t $timeout
    snmpwalk.exe -Ln -On -v 2c -c $community $hostaddr":"$port "1.3.6.1.2.1.15.2" -t $timeout
    snmpwalk.exe -Ln -On -v 2c -c $community $hostaddr":"$port "1.3.6.1.2.1.15.3.1.9" -t $timeout
    Exit
    }

#Check if snmwalk.exe suceeded.
if ($LASTEXITCODE -ne 0 ){
    write-host "<prtg>"
    write-host "<error>1</error>"
    write-host "<text>Error: $($walkresult) / ScriptV: $($version) / PSv: $($PSVersionTable.PSVersion)</text>"
    write-host "</prtg>"
    Exit
}

#Validate output. Expects *INTEGER* in the result. Example: "12.34.56.78 = INTEGER: 6" - String and array have distinc handling.
if (($walkresult -is [String]) -and ($walkresult -notlike "*INTEGER*") -or ($walkresult -is [array]) -and ($walkresult[0].ToString() -notlike "*INTEGER*")){
    write-host "<prtg>"
    write-host "<error>1</error>"
    write-host "<text>Error: $($walkresult) / ScriptV: $($version) / PSv: $($PSVersionTable.PSVersion)</text>"
    write-host "</prtg>"
    Exit
}

$walkresult = $walkresult.Substring(22)
$walkresult2 = $walkresult2.Substring(31)
$peersmsg = $null
$peersmsg2 = $null

foreach($entry in $walkresult | where-object { $_ -notlike "*: 6"}){
    $peersmsg += "$($entry.split()[-0]) "
}

foreach($entry in $walkresult2 | where-object { $_ -notlike "* Counter32:*"}){
    $peersmsg2 += "$($entry.split()[-0]) "
}

$peerstatus = new-object int[] 6
$peerstatus[5] = ($walkresult | where-object { $_ -like "*: 6"}).Count
$peerstatus[4] = ($walkresult | where-object { $_ -like "*: 5"}).Count
$peerstatus[3] = ($walkresult | where-object { $_ -like "*: 4"}).Count
$peerstatus[2] = ($walkresult | where-object { $_ -like "*: 3"}).Count
$peerstatus[1] = ($walkresult | where-object { $_ -like "*: 2"}).Count
$peerstatus[0] = ($walkresult | where-object { $_ -like "*: 1"}).Count

$numPeers = ($walkresult2 | where-object { $_ -like "* Counter32:*"}).Count
$peerObjects = @()
$peerstatus2 = New-Object int[] $numPeers
#$peerstatus[$numPeers-1] = ($walkresult2 | where-object { $_ -like "* Counter32:*"}).Count
foreach($peer in $walkresult2){
    $peerSplit = $peer.split(" ")
    $peerString = $peerSplit[0].ToString()
    $peerName = $peerString.Substring(0,$peerString.Length-4)
    
    $receivedRoutes = $peerSplit[3]

    $peerObjects += [PSCustomObject] @{
        peername = $peerName
        receivedroutes = $receivedRoutes
    } 
}

$queryMeasurement.Stop()


write-host "<prtg>"

Write-Host "<result>"
Write-Host "<channel>BGP ASN</channel>"
Write-Host "<value>$($localASN)</value>"
Write-Host "</result>"

if($numPeers -le 1) {
    write-host "<result>"
    write-host "<channel>Peers Established</channel>"
    write-host "<value>$($peerstatus[5])</value>"
    Write-host "<LimitMode>1</LimitMode>"
    write-host "<LimitMinError>$($numPeers-1)</LimitMinError>"
    write-host "</result>"
}
elseif($numPeers -eq 2) {
    write-host "<result>"
    write-host "<channel>Peers Established</channel>"
    write-host "<value>$($peerstatus[5])</value>"
    Write-host "<LimitMode>1</LimitMode>"
    write-host "<LimitMinWarning>$($numPeers-1)</LimitMinWarning>"
    write-host "<LimitMinError>$($numPeers-2)</LimitMinError>"
    write-host "</result>"
}
elseif($numPeers -eq 3) {
    write-host "<result>"
    write-host "<channel>Peers Established</channel>"
    write-host "<value>$($peerstatus[5])</value>"
    Write-host "<LimitMode>1</LimitMode>"
    write-host "<LimitMinWarning>$($numPeers-1)</LimitMinWarning>"
    write-host "<LimitMinError>$($numPeers-2)</LimitMinError>"
    write-host "</result>"
}
else {
    write-host "<result>"
    write-host "<channel>Peers Established</channel>"
    write-host "<value>$($peerstatus[5])</value>"
    Write-host "<LimitMode>1</LimitMode>"
    write-host "<LimitMinWarning>$($numPeers-1)</LimitMinWarning>"
    write-host "<LimitMinError>$($numPeers-3)</LimitMinError>"
    write-host "</result>"
}

#build text for routes received channels
foreach($object in $peerObjects){
    write-host "<result>"
    write-host "<channel>Peer Routes Received from $($object.peername)</channel>"
    write-host "<value>$($object.receivedroutes)</value>"
    Write-host "<LimitMode>1</LimitMode>"
    write-host "<LimitMinWarning>100</LimitMinWarning>"
    write-host "<LimitMinError>50</LimitMinError>"
    write-host "</result>"
}

write-host "<result>"
write-host "<channel>Peers OpenConfirm</channel>"
write-host "<value>$($peerstatus[4])</value>"
Write-host "<LimitMode>1</LimitMode>"
write-host "<LimitMaxWarning>1</LimitMaxWarning>"
write-host "</result>"

write-host "<result>"
write-host "<channel>Peers OpenSent</channel>"
write-host "<value>$($peerstatus[3])</value>"
Write-host "<LimitMode>1</LimitMode>"
write-host "<LimitMaxWarning>1</LimitMaxWarning>"
write-host "</result>"

write-host "<result>"
write-host "<channel>Peers Active</channel>"
write-host "<value>$($peerstatus[2])</value>"
Write-host "<LimitMode>1</LimitMode>"
write-host "<LimitMaxWarning>1</LimitMaxWarning>"
write-host "</result>"

write-host "<result>"
write-host "<channel>Peers Connect</channel>"
write-host "<value>$($peerstatus[1])</value>"
Write-host "<LimitMode>1</LimitMode>"
write-host "<LimitMaxWarning>1</LimitMaxWarning>"
write-host "</result>"

write-host "<result>"
write-host "<channel>Peers Idle</channel>"
write-host "<value>$($peerstatus[0])</value>"
Write-host "<LimitMode>1</LimitMode>"
write-host "<LimitMaxWarning>1</LimitMaxWarning>"
write-host "</result>"

Write-Host "<result>"
Write-Host "<channel>Script Execution Time</channel>"
Write-Host "<value>$($queryMeasurement.ElapsedMilliseconds)</value>"
Write-Host "<CustomUnit>msecs</CustomUnit>"
Write-Host "</result>"

if ($peersmsg) {
    write-host "<text>Not Established: $($peersmsg)</text>"
    write-host "<Warning>1</Warning>"
}

if ($peersmsg2) {
    write-host "<text>Not Established: $($peersmsg2)</text>"
    write-host "<Warning>1</Warning>"
}

write-host "</prtg>"
