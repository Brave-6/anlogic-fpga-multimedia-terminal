param(
    [string]$VerifyCardDrive='',
    [string]$OutputDir=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$projectRoot=Split-Path -Parent $PSScriptRoot
if(!$OutputDir){$OutputDir=Join-Path $projectRoot 'verification\fast_boot_fixtures'}
$null=New-Item -ItemType Directory -Path $OutputDir -Force
function Get-Crc32([byte[]]$Bytes,[int]$Count){
    [uint32]$crc=[uint32]::MaxValue
    for($n=0;$n -lt $Count;$n++){
        $crc=$crc -bxor [uint32]$Bytes[$n]
        for($bit=0;$bit -lt 8;$bit++){
            if($crc -band 1){$crc=($crc -shr 1) -bxor [uint32]3988292384}else{$crc=$crc -shr 1}
        }
    }
    return ('{0:X8}' -f ($crc -bxor [uint32]::MaxValue))
}
$pages=@(foreach($index in 1..4){
    $file=Join-Path $projectRoot ('tf_pages\P'+$index+'.bmp')
    $bytes=[IO.File]::ReadAllBytes($file)
    if($bytes.Length -ne 921654 -or $bytes[0] -ne 66 -or $bytes[1] -ne 77 -or
       [BitConverter]::ToUInt32($bytes,10) -ne 54 -or
       [BitConverter]::ToInt32($bytes,18) -ne 640 -or [BitConverter]::ToInt32($bytes,22) -ne 480 -or
       [BitConverter]::ToUInt16($bytes,28) -ne 24 -or [BitConverter]::ToUInt32($bytes,30) -ne 0){throw 'Unexpected BMP format'}
    $crc=Get-Crc32 $bytes 512
    $bytes[0..511] | ForEach-Object {'{0:X2}' -f $_} | Set-Content -LiteralPath (Join-Path $OutputDir ('P'+$index+'.mem')) -Encoding ASCII
    [pscustomobject]@{File=('P'+$index+'.bmp');Length=$bytes.Length;CRC32=$crc;SHA256=(Get-FileHash -LiteralPath $file).Hash;StartSector=$null;PhysicalVerified=$false}
})
if($VerifyCardDrive){
    $letter=$VerifyCardDrive.TrimEnd(':').ToUpperInvariant()
    if($letter -notmatch '^[A-Z]$'){throw 'Specify a single drive letter'}
    $partition=Get-Partition -DriveLetter $letter
    $disk=Get-Disk -Number $partition.DiskNumber
    if($disk.IsBoot -or $disk.IsSystem -or $disk.BusType -notin @('USB','SD','MMC')){throw 'Refusing non-removable/system disk audit'}
    if($partition.Offset % 512){throw 'Unaligned partition offset'}
    $baseSector=[long]$partition.Offset/512
    $captureBytes=64*1024*1024-[long]$partition.Offset
    if($captureBytes -lt 4*1024*1024){throw 'Partition outside FPGA scan window'}
    # Read-only handle. No formatting, filesystem changes, raw writes or locks.
    $raw=[IO.File]::Open(('\\.\'+$letter+':'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{
        $image=New-Object byte[] $captureBytes
        $count=0
        while($count -lt $image.Length){
            $n=$raw.Read($image,$count,[Math]::Min(1024*1024,$image.Length-$count))
            if($n -le 0){throw 'Unexpected raw volume EOF'}
            $count+=$n
        }
    }finally{$raw.Dispose()}
    # Deleted files can leave byte-identical raw copies. Select the LIVE file
    # through the FAT32 root directory, not the first raw signature match.
    $bps=[BitConverter]::ToUInt16($image,11)
    $spc=[int]$image[13]
    $reserved=[BitConverter]::ToUInt16($image,14)
    $fatCount=[int]$image[16]
    $fatSectors=[BitConverter]::ToUInt32($image,36)
    $rootCluster=[BitConverter]::ToUInt32($image,44)
    $flags=[BitConverter]::ToUInt16($image,40)
    $activeFat=if($flags -band 128){$flags -band 15}else{0}
    if($bps -ne 512 -or $spc -lt 1 -or $spc -gt 128 -or ($spc -band ($spc-1)) -ne 0 -or
       $reserved -lt 1 -or $fatCount -lt 1 -or $fatCount -gt 4 -or $activeFat -ge $fatCount -or
       $fatSectors -eq 0 -or [BitConverter]::ToUInt16($image,17) -ne 0 -or
       [BitConverter]::ToUInt16($image,22) -ne 0 -or $image[510] -ne 85 -or $image[511] -ne 170){throw 'Unsupported FAT32 BPB'}
    $dataSector=[long]$reserved+[long]$fatCount*$fatSectors
    $fatOffset=([long]$reserved+[long]$activeFat*$fatSectors)*512
    $clusterBytes=$spc*512
    function Get-FatChain([uint32]$First){
        $chain=[Collections.Generic.List[uint32]]::new()
        $seen=[Collections.Generic.HashSet[uint32]]::new()
        $cluster=$First
        while($cluster -ge 2 -and $cluster -lt 0x0FFFFFF8){
            if($cluster -ge 0x0FFFFFF0 -or !$seen.Add($cluster) -or $chain.Count -ge 100000){throw 'Invalid/cyclic FAT chain'}
            $entry=$fatOffset+4L*$cluster
            if($entry+4 -gt $fatOffset+[long]$fatSectors*512 -or $entry+4 -gt $image.Length){throw 'FAT entry outside capture/table'}
            $chain.Add($cluster)
            $cluster=[BitConverter]::ToUInt32($image,[int]$entry) -band 0x0FFFFFFF
        }
        if($cluster -lt 0x0FFFFFF8){throw 'FAT chain without end marker'}
        return ,$chain.ToArray()
    }
    $rootFiles=@(foreach($cluster in (Get-FatChain $rootCluster)){
        $clusterOffset=($dataSector+([long]$cluster-2)*$spc)*512
        if($clusterOffset+$clusterBytes -gt $image.Length){throw 'Root directory outside capture'}
        $directoryEnd=$false
        for($offset=[int]$clusterOffset;$offset -lt $clusterOffset+$clusterBytes;$offset+=32){
            if($image[$offset] -eq 0){$directoryEnd=$true;break}
            $attr=$image[$offset+11]
            if($image[$offset] -eq 229 -or $attr -eq 15 -or ($attr -band 24) -ne 0){continue}
            $stem=[Text.Encoding]::ASCII.GetString($image,$offset,8).Trim()
            $ext=[Text.Encoding]::ASCII.GetString($image,$offset+8,3).Trim()
            $first=([uint32][BitConverter]::ToUInt16($image,$offset+20) -shl 16) -bor [BitConverter]::ToUInt16($image,$offset+26)
            [pscustomobject]@{Name=($stem+'.'+$ext);FirstCluster=$first;Length=[BitConverter]::ToUInt32($image,$offset+28)}
        }
        if($directoryEnd){break}
    })
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        foreach($page in $pages){
            $visible=Join-Path ($letter+':\') $page.File
            if((Get-FileHash -LiteralPath $visible).Hash -ne $page.SHA256){throw ('Mounted file differs from final media: '+$page.File)}
            $entries=@($rootFiles | Where-Object Name -eq $page.File)
            if($entries.Count -ne 1 -or $entries[0].Length -ne $page.Length){throw ('Live root entry missing, ambiguous or wrong size: '+$page.File)}
            $chain=Get-FatChain $entries[0].FirstCluster
            $required=[int][Math]::Ceiling($page.Length/[double]$clusterBytes)
            if($chain.Count -lt $required){throw 'FAT chain shorter than file'}
            for($j=1;$j -lt $required;$j++){if($chain[$j] -ne $chain[$j-1]+1){throw ('Fragmented file unsupported by FPGA: '+$page.File)}}
            $relativeSector=$dataSector+([long]$entries[0].FirstCluster-2)*$spc
            $offset=$relativeSector*512
            if($offset+$page.Length -gt $image.Length){throw 'File outside capture window'}
            $actual=[BitConverter]::ToString($sha.ComputeHash($image,[int]$offset,$page.Length)).Replace('-','')
            if($actual -ne $page.SHA256){throw ('Live raw file differs from final media: '+$page.File)}
            $page.StartSector=[long]($baseSector+$relativeSector);$page.PhysicalVerified=$true
        }
    }finally{$sha.Dispose()}
    for($i=1;$i -lt 4;$i++){
        if($pages[$i].StartSector -lt $pages[$i-1].StartSector+1801){throw 'Map overlaps or is not in P1/P2/P3/P4 physical order'}
    }
    [pscustomobject]@{Disk=$disk.Number;Serial=$disk.SerialNumber;BusType=[string]$disk.BusType;PartitionOffset=$partition.Offset;Drive=$letter;ReadOnly=$true;At=(Get-Date -Format o)} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDir 'card_identity.json') -Encoding UTF8
}
$pages | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDir 'page_map.json') -Encoding UTF8
$pages | Format-Table -AutoSize
if(!$VerifyCardDrive){Write-Output 'OFFLINE ONLY: fixtures and source fingerprints generated; no current TF card or physical address verified.'}
else{Write-Output 'READ-ONLY CARD AUDIT PASS. Use the verified map to update candidate parameters, then rebuild.'}
