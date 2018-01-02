# Import vSphere PowerCLI for use within script.
if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
. "C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1"
}

$json = Get-Content -Path .\config.json
$config = $json | ConvertFrom-Json
Connect-VIServer -Server $config.server -ErrorAction Stop

<#
.Synopsis
   Get-SnapshotInfo
.DESCRIPTION
   Used to pull data about a snapshot that can be used in other
   functions.
.EXAMPLE
   $vms = Get-VM
   Get-SnapshotInfo -VM $vms
#>
function Get-SnapshotInfo {
    [CmdletBinding()]
    [OutputType([PSObject])]
    Param
    (
        # @param $VM: Supply a VM or list of VM's to gather their snapshot data.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [String[]]
        $VM
    )
    Process {
        $snapshotInfo = @()
        foreach($m in $VM) {
            $snapshot = Get-Snapshot -VM $m -ErrorAction SilentlyContinue
            if($snapshot -ne $null) {
                $snap = Get-VMSnapshotData -VMSnapshot $snapshot 
                $snapshotInfo += $snap        
            }    
        }
        return $snapshotInfo
    }
}

function Get-VMSnapshotData {
    [CmdletBinding()]
    [OutputType([PSObject])]
    Param
    (
        # @param $VM: Supply a VM or list of VM's to gather their snapshot data.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $VMSnapshot
    )
    Process {
        foreach($snapshot in $VMSnapshot) {
            $vmSnapInfo = @{
                VMName = $m;
                SnapshotName = $snapshot.Name;
                Created = $snapshot.Created;
                SizeGB = $snapshot.SizeGB;
                SizeMB = $snapshot.SizeMB;
            }
            return $vmSnapInfo
        }    
    }
}

function New-SnapshotPolicy {
    [CmdletBinding()]
    [OutputType([PSObject])]
    Param (
        # @param Retention: The maximum amount of days a VM snapshot will persist.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false)]
        [int]
        $Retention,
        
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false)]
        # @param Size: The max allowed size of a snapshot.
        [int]
        $Size
    )
    $snapshotPolicy = @{
        Retention = $Retention;
        Size = $Size
    }
    return $snapshotPolicy
}

<#
.Synopsis
   Test-Snapshot
.DESCRIPTION
   Tests all snapshots against a defined snapshot policy. Will
   return the results of the test in the form of a hashmap.
.EXAMPLE
   Test-Snapshot -Snapshot $snaps -SnapshotPolicy $policy
#>
function Test-Snapshot {
    [CmdletBinding()]
    [OutputType([PSObject])]
    Param
    (
        # @param Snapshot: The snapshot that will be tested and reported on.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false)]
        $Snapshot,

        # @param SnapshotPolicy: The policy defined for snapshot retention and size.
        [PSObject]
        $SnapshotPolicy
        
    )
    Process {
        $snapshotTest = @()
        $result = @{}
        foreach($snap in $Snapshot) {
            $created = New-TimeSpan -Start $snap.Created `
                                    -End $(Get-Date)
            $result.Add("Snapshot", $snap.SnapshotName)
            $result.Add("VM", $snap.VMName)
            if($snap.Size -gt $SnapshotPolicy.Size) {
                $result.Add("SizeTest", $false)
            }
            else {
                $result.Add("SizeTest", $true)
            }

            if($created.Days -gt $SnapshotPolicy.Retention) {
                $result.Add("RetentionTest", $false)
            }
            else {
                $result.Add("RetentionTest", $true)
            }

            $snapshotTest += $result
        }
        return $snapshotTest      
    }
}

<#
.Synopsis
   Remove-VMSnapshot
.DESCRIPTION
   Removes all snapshots that fail the policy compliance test.
.EXAMPLE
   $test = Test-Snapshot -Snapshot $t -SnapshotPolicy $policy
   Remove-VMSnapshot -TestResult $test
#>
function Remove-VMSnapshot
{
    [CmdletBinding()]
    [OutputType([int])]
    Param
    (
        # @param TestResult: The result of a snapshot policy test that will
        # determine which VM's need to be removed.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false)]
        [PSObject]
        $TestResult
    )

    Process {
        foreach($result in $TestResult) {
            if($result.RetentionTest -eq $false -or $result.SizeTest -eq $false) {
                $snapshot = Get-Snapshot -Name $result.Snapshot -VM $result.VM
                Remove-Snapshot -Snapshot $snapshot -RunAsync -Confirm:$false
            }
        }
    }
}

$vms = Get-VM
$t = Get-SnapshotInfo -VM $vms
$policy = New-SnapshotPolicy -Retention $config.retention -Size $config.size

$test = Test-Snapshot -Snapshot $t -SnapshotPolicy $policy
$test
#Remove-VMSnapshot -TestResult $test
#Disconnect-VIServer -Confirm:$false