# random_powershell
random powershell scripts

* Monitor-bgppeers.ps1
  * Pulls stats from devices that support bgp mib. Pulls peers and number of routes into PRTG sensors and creates down/warning thresholds based on the number of routes imported initially. These thresholds can be adjusted with in the script, or after creation to suit your needs. This could also be pretty easily modified to dump to something like an influxdb or other graphing database.
