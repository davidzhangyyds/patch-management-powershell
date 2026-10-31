<#
.SYNOPSIS
    Module partage - fonctions communes utilisees par tous les scripts du projet.
#>

function Get-ComputerInventory {
    <#
    .SYNOPSIS
        Lit un fichier computers.txt (format Nom;IP) et retourne des objets.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Fichier introuvable : $Path"
    }

    Get-Content -Path $Path |
        Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("#") } |
        ForEach-Object {
            $parts = $_ -split ";"
            [PSCustomObject]@{
                Nom       = $parts[0].Trim()
                AdresseIP = $parts[1].Trim()
            }
        }
}

function Write-PatchLog {
    <#
    .SYNOPSIS
        Ajoute une ligne horodatee au fichier de journal PatchManager.log.
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$LogPath = "$PSScriptRoot\..\..\logs\PatchManager.log"
    )

    $logDir = Split-Path $LogPath -Parent
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

    $timestamp = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    "$timestamp ; $Message" | Add-Content -Path $LogPath -Encoding UTF8
}

function Test-PCAvailability {
    <#
    .SYNOPSIS
        Teste la disponibilite ICMP d'une machine.
    #>
    param([Parameter(Mandatory)][string]$ComputerName)

    Test-Connection -ComputerName $ComputerName -Count 2 -Quiet -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function Get-ComputerInventory, Write-PatchLog, Test-PCAvailability