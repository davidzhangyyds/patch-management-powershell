<#
.SYNOPSIS
    Partie 1 - Verifie la disponibilite des postes listes dans computers.txt.

.DESCRIPTION
    Lit le fichier computers.txt (format Nom;IP), teste chaque machine avec
    Test-Connection (ping ICMP), puis affiche un tableau recapitulatif avec
    le nom, l'adresse IP et l'etat de disponibilite de chaque poste.

.NOTES
    Fichier attendu : config\computers.txt
    Format d'une ligne : PC01;192.168.10.11
#>

[CmdletBinding()]
param(
    [string]$ComputersFile = "$PSScriptRoot\..\config\computers.txt"
)

# --- Verification de l'existence du fichier d'inventaire ---
if (-not (Test-Path $ComputersFile)) {
    Write-Error "Fichier introuvable : $ComputersFile"
    return
}

# --- Lecture et parsing du fichier computers.txt ---
$computers = Get-Content -Path $ComputersFile |
    Where-Object { $_.Trim() -ne "" } |
    ForEach-Object {
        $parts = $_ -split ";"
        [PSCustomObject]@{
            Nom       = $parts[0].Trim()
            AdresseIP = $parts[1].Trim()
        }
    }

if ($computers.Count -eq 0) {
    Write-Warning "Aucune machine trouvee dans $ComputersFile"
    return
}

Write-Host "`n=== Verification de la disponibilite de $($computers.Count) poste(s) ===" -ForegroundColor Cyan

# --- Test de disponibilite de chaque machine ---
$results = foreach ($pc in $computers) {

    $isReachable = Test-Connection -ComputerName $pc.AdresseIP -Count 2 -Quiet -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        Nom       = $pc.Nom
        AdresseIP = $pc.AdresseIP
        Etat      = if ($isReachable) { "Accessible" } else { "Inaccessible" }
    }
}

# --- Affichage du tableau recapitulatif ---
$results | Format-Table -AutoSize

# --- Petit resume chiffre ---
# @(...) force le contexte tableau : sans lui, .Count renvoie $null (pas 0 ni 1)
# quand Where-Object ne retourne qu'un seul objet - piege classique PowerShell.
$accessibles   = @($results | Where-Object { $_.Etat -eq "Accessible" }).Count
$inaccessibles = @($results).Count - $accessibles

Write-Host "Resume : $accessibles accessible(s), $inaccessibles inaccessible(s)." -ForegroundColor Cyan

# --- Retourne les objets pour reutilisation par d'autres scripts (ex: Run-FullAudit.ps1) ---
return $results