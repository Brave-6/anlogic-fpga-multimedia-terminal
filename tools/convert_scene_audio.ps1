param(
    [string]$SourceDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\audio\source'),
    [string]$OutputDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\user_source\hdl_source\audio'
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

if (-not ('SceneAudioConverter' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

public static class SceneAudioConverter {
    public static int Append(string path, List<byte> output) {
        using (var br = new BinaryReader(File.OpenRead(path))) {
            if (Encoding.ASCII.GetString(br.ReadBytes(4)) != "RIFF") throw new InvalidDataException("Not RIFF: " + path);
            br.ReadUInt32();
            if (Encoding.ASCII.GetString(br.ReadBytes(4)) != "WAVE") throw new InvalidDataException("Not WAVE: " + path);
            byte[] data = null;
            while (br.BaseStream.Position < br.BaseStream.Length) {
                string id = Encoding.ASCII.GetString(br.ReadBytes(4));
                uint len = br.ReadUInt32();
                if (id == "fmt ") {
                    ushort format = br.ReadUInt16(); ushort channels = br.ReadUInt16(); uint rate = br.ReadUInt32();
                    br.ReadUInt32(); br.ReadUInt16(); ushort bits = br.ReadUInt16();
                    if (len > 16) br.ReadBytes((int)len - 16);
                    if (format != 1 || channels != 2 || rate != 48000 || bits != 16)
                        throw new InvalidDataException("Expected PCM 48kHz/16-bit stereo: " + path);
                } else if (id == "data") data = br.ReadBytes((int)len);
                else br.ReadBytes((int)len);
                if ((len & 1) != 0) br.ReadByte();
            }
            if (data == null) throw new InvalidDataException("No data chunk: " + path);
            int before = output.Count;
            for (int i = 0; i + 3 < data.Length; i += 24) {
                long sum = 0; int frames = 0;
                for (int j = 0; j < 6 && i + j * 4 + 3 < data.Length; j++) {
                    int p = i + j * 4;
                    short left = BitConverter.ToInt16(data, p);
                    short right = BitConverter.ToInt16(data, p + 2);
                    sum += (left + right) / 2; frames++;
                }
                int avg = (int)(sum / frames);
                int u8 = (avg + 32768) >> 8;
                output.Add((byte)Math.Max(0, Math.Min(255, u8)));
            }
            return output.Count - before;
        }
    }
}
'@
}

$names = @('boot_chime_48k16.wav', 'emergency_alarm_48k16.wav', 'all_clear_48k16.wav')
$samples = [System.Collections.Generic.List[byte]]::new()
$manifest = [System.Collections.Generic.List[string]]::new()
foreach ($name in $names) {
    $start = $samples.Count
    $count = [SceneAudioConverter]::Append((Join-Path $SourceDir $name), $samples)
    $manifest.Add(('{0}{1}{2}{1}{3}{1}{4}' -f $name, [char]9, $start, $count, [math]::Round($count / 8000.0, 6)))
}
$hex = [string[]]::new($samples.Count)
for ($i = 0; $i -lt $samples.Count; $i++) { $hex[$i] = $samples[$i].ToString('X2') }
[IO.File]::WriteAllLines((Join-Path $OutputDir 'scene_audio.mem'), $hex)
[IO.File]::WriteAllLines((Join-Path $OutputDir 'scene_audio_manifest.tsv'), $manifest)
$bankSize = 4096
$bankCount = [math]::Ceiling($samples.Count / $bankSize)
for ($bank = 0; $bank -lt $bankCount; $bank++) {
    $bankHex = [string[]]::new($bankSize)
    for ($i = 0; $i -lt $bankSize; $i++) {
        $index = $bank * $bankSize + $i
        $bankHex[$i] = if ($index -lt $samples.Count) { $samples[$index].ToString('X2') } else { '80' }
    }
    $mif = [System.Collections.Generic.List[string]]::new()
    $mif.Add('WIDTH=8;'); $mif.Add('DEPTH=4096;'); $mif.Add('')
    $mif.Add('ADDRESS_RADIX=UNS;'); $mif.Add('DATA_RADIX=HEX;'); $mif.Add('')
    $mif.Add('CONTENT BEGIN')
    for ($i = 0; $i -lt $bankSize; $i++) { $mif.Add(('{0} : {1};' -f $i, $bankHex[$i])) }
    $mif.Add('END;')
    [IO.File]::WriteAllLines((Join-Path $OutputDir ('scene_audio_bank{0:D2}.mif' -f $bank)), $mif)
}
Write-Output "Generated $($samples.Count) 8-bit mono samples at $OutputDir"
