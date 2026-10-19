# Gravação de CD/DVD pelo IMAPI2, a API de gravação do próprio Windows.
#
# Substitui o DiscRecording/DiscRecordingUI do macOS usado pelo Horos
# (DRTrack trackForRootFolder + DRBurnSetupPanel + DRBurnProgressPanel).
# O fluxo é o mesmo: a pasta preparada vira a raiz do disco.
#
# Os parâmetros chegam por variáveis de ambiente, não pela linha de
# comando: caminhos com espaço, acento ou apóstrofo não passam por nenhuma
# camada de aspas. A saída é uma linha JSON por evento, em UTF-8, com
# códigos em vez de frases: o PowerShell 5.1 lê scripts sem BOM na página
# de código ANSI, e texto acentuado em strings sairia corrompido. As
# mensagens em português são montadas pelo lado Python (windows.py).
#
#   HORUS_ACTION          list | burn
#   HORUS_RECORDER_INDEX  índice do gravador (burn)
#   HORUS_FOLDER          pasta a gravar (burn)
#   HORUS_LABEL           rótulo do volume, até 15 caracteres (burn)
#   HORUS_EJECT           1 para ejetar ao final (burn)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

function Emit([hashtable]$data) {
    [Console]::Out.WriteLine(($data | ConvertTo-Json -Compress -Depth 4))
    [Console]::Out.Flush()
}

function Fail([string]$code, [int]$exitCode, [string]$detail = '') {
    Emit @{ event = 'error'; code = $code; detail = $detail; hresult = '' }
    exit $exitCode
}

# IMAPI_MEDIA_PHYSICAL_TYPE
$MediaNames = @{
    0 = 'desconhecida'; 1 = 'CD-ROM'; 2 = 'CD-R'; 3 = 'CD-RW'; 4 = 'DVD-ROM';
    5 = 'DVD-RAM'; 6 = 'DVD+R'; 7 = 'DVD+RW'; 8 = 'DVD+R DL'; 9 = 'DVD-R';
    10 = 'DVD-RW'; 11 = 'DVD-R DL'; 12 = 'disco'; 13 = 'DVD+RW DL';
    14 = 'HD DVD-ROM'; 15 = 'HD DVD-R'; 16 = 'HD DVD-RAM'; 17 = 'BD-ROM';
    18 = 'BD-R'; 19 = 'BD-RE'
}

# IMAPI_FORMAT2_DATA_MEDIA_STATE: sobrescrevível (1), vazia (2) ou com
# espaço para nova sessão (4); a máscara 0xFC00 reúne os estados que
# impedem a gravação (danificada, protegida, finalizada, não suportada...).
$WritableMask = 0x7
$UnusableMask = 0xFC00

function Open-Recorder($master, [int]$index) {
    $recorder = New-Object -ComObject IMAPI2.MsftDiscRecorder2
    $recorder.InitializeDiscRecorder($master.Item($index))
    return $recorder
}

function Describe-Recorder($master, [int]$index) {
    $recorder = Open-Recorder $master $index
    $info = @{
        event          = 'recorder'
        index          = $index
        id             = "$($recorder.ActiveDiscRecorder)"
        vendor         = "$($recorder.VendorId)".Trim()
        product        = "$($recorder.ProductId)".Trim()
        drive          = (@($recorder.VolumePathNames) -join ';')
        media_present  = $false
        media_writable = $false
        media_type     = -1
        media_name     = ''
        free_bytes     = 0
    }
    try {
        $format = New-Object -ComObject IMAPI2.MsftDiscFormat2Data
        if ($format.IsRecorderSupported($recorder)) {
            $format.Recorder = $recorder
            try {
                $type = [int]$format.CurrentPhysicalMediaType
                $info.media_present = $true
                $info.media_type = $type
                $info.media_name = $MediaNames[$type]
            } catch {
                # Sem mídia: a leitura do tipo falha com E_IMAPI_RECORDER_MEDIA_NO_MEDIA.
            }
            if ($info.media_present -and $format.IsCurrentMediaSupported($recorder)) {
                $state = [int]$format.CurrentMediaStatus
                $info.media_writable = (($state -band $WritableMask) -ne 0) -and (($state -band $UnusableMask) -eq 0)
                $info.free_bytes = [int64]$format.FreeSectorsOnMedia * 2048
            }
        }
    } catch {
        $info.media_present = $false
    }
    return $info
}

try {
    $master = New-Object -ComObject IMAPI2.MsftDiscMaster2
    if (-not $master.IsSupportedEnvironment) {
        Fail 'no_recorder' 2
    }

    $action = "$env:HORUS_ACTION"
    if ($action -eq 'list') {
        for ($i = 0; $i -lt $master.Count; $i++) {
            Emit (Describe-Recorder $master $i)
        }
        Emit @{ event = 'done' }
        exit 0
    }

    if ($action -ne 'burn') {
        Fail 'unknown_action' 64 $action
    }

    $index = [int]$env:HORUS_RECORDER_INDEX
    $folder = "$env:HORUS_FOLDER"
    $label = "$env:HORUS_LABEL"
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        Fail 'folder_missing' 66 $folder
    }

    $recorder = Open-Recorder $master $index
    $format = New-Object -ComObject IMAPI2.MsftDiscFormat2Data
    if (-not $format.IsRecorderSupported($recorder)) {
        Fail 'recorder_unsupported' 3
    }
    $format.Recorder = $recorder
    if (-not $format.IsCurrentMediaSupported($recorder)) {
        Fail 'media_unsupported' 4
    }
    $format.ClientName = 'Horus'
    # Disco fechado: é o que leitores de consultório e PACS esperam.
    $format.ForceMediaToBeClosed = $true

    Emit @{ event = 'progress'; code = 'building'; fraction = $null }
    $image = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $image.ChooseImageDefaults($recorder)
    $type = [int]$format.CurrentPhysicalMediaType
    # ISO 9660 (1) + Joliet (2) sempre — o PS3.12 pede ISO 9660 em CD —
    # e UDF (4) a partir de DVD, como no perfil DICOM de DVD.
    if ($type -in 1, 2, 3) { $image.FileSystemsToCreate = 3 } else { $image.FileSystemsToCreate = 7 }
    $image.VolumeName = $label
    $image.Root.AddTree($folder, $false)
    $result = $image.CreateResultImage()

    $needed = [int64]$result.TotalBlocks
    $free = [int64]$format.FreeSectorsOnMedia
    if ($free -gt 0 -and $needed -gt $free) {
        # Mesma checagem do Horos em deviceContainsSuitableMedia.
        Emit @{ event = 'error'; code = 'capacity'; needed_bytes = $needed * 2048; free_bytes = $free * 2048; hresult = '' }
        exit 5
    }

    Emit @{ event = 'progress'; code = 'writing'; fraction = $null; total_bytes = $needed * 2048 }
    $format.Write($result.ImageStream)
    Emit @{ event = 'progress'; code = 'written'; fraction = 1.0 }

    if ("$env:HORUS_EJECT" -eq '1') {
        try { $recorder.EjectMedia() } catch { }
    }
    Emit @{ event = 'done' }
    exit 0
} catch {
    $hr = ''
    if ($_.Exception.HResult) { $hr = ('0x{0:X8}' -f $_.Exception.HResult) }
    # A mensagem do sistema já vem no idioma do Windows instalado.
    Emit @{ event = 'error'; code = 'exception'; detail = $_.Exception.Message; hresult = $hr }
    exit 1
}
