<#
.SYNOPSIS
    Partie 4 - Controle de conformite des postes vis-a-vis d'une liste de
    correctifs obligatoires.

.DESCRIPTION
    Compare les correctifs installes sur chaque poste accessible avec la
    liste de KB obligatoires (required-patches.txt). Attribue un etat
    CONFORME / NON CONFORME / INACCESSIBLE, liste les KB manquantes,
    horodate le controle, exporte ComplianceReport.csv et calcule un taux
    global de conformite (hors postes inaccessibles).

.NOTES
    Fichiers attendus : config\computers.txt, config\required-patches.txt
    Export genere     : reports\ComplianceReport.csv
#>

[CmdletBinding()]
param(
    [string]$ComputersFile      = "$PSScriptRoot\..\config\computers.txt",
    [string]$RequiredPatchesFile= "$PSScriptRoot\..\config\required-patches.txt",
    [string]$OutputCsv          = "$PSScriptRoot\..\reports\ComplianceReport.csv",
    [System.Management.Automation.PSCredential]$Credential
)

Import-Module "$PSScriptRoot\modules\PatchManager.psm1" -Force

if (-not (Test-Path $RequiredPatchesFile)) {
    Write-Error "Fichier introuvable : $RequiredPatchesFile"
    return
}

if (-not $Credential) {
    $Credential = Get-Credential -Message "Identifiants pour PowerShell Remoting (vide = session courante)" -ErrorAction SilentlyContinue
}

$requiredPatches = Get-Content $RequiredPatchesFile | Where-Object { $_.Trim() -ne "" }
$computers       = Get-ComputerInventory -Path $ComputersFile

Write-Host "`n=== Controle de conformite - $($computers.Count) poste(s) / $($requiredPatches.Count) KB requise(s) ===" -ForegroundColor Cyan

$controlDate = Get-Date

$results = foreach ($pc in $computers) {

    Write-Host "Controle de $($pc.Nom) ($($pc.AdresseIP))..." -NoNewline

    if (-not (Test-PCAvailability -ComputerName $pc.AdresseIP)) {
        Write-Host " Inaccessible" -ForegroundColor Red
        Write-PatchLog -Message "$($pc.Nom) ; WinRM inaccessible"
        [PSCustomObject]@{
            Poste         = $pc.Nom
            AdresseIP     = $pc.AdresseIP
            KBRequises    = $requiredPatches.Count
            KBManquantes  = $null
            NbManquantes  = $null
            Etat          = "INACCESSIBLE"
            DateControle  = $controlDate
        }
        continue
    }

    try {
        $sessionParams = @{ ComputerName = $pc.AdresseIP; ErrorAction = "Stop" }
        if ($Credential) { $sessionParams["Credential"] = $Credential }

        $installedKB = Invoke-Command @sessionParams -ScriptBlock {
            (Get-HotFix).HotFixID
        }

        $missing = @($requiredPatches | Where-Object { $_ -notin $installedKB })
        $etat = if ($missing.Count -eq 0) { "CONFORME" } else { "NON CONFORME" }

        $color = if ($etat -eq "CONFORME") { "Green" } else { "Yellow" }
        Write-Host " $etat" -ForegroundColor $color

        if ($etat -eq "NON CONFORME") {
            Write-PatchLog -Message "$($pc.Nom) ; Non conforme ; $($missing -join ',')"
        } else {
            Write-PatchLog -Message "$($pc.Nom) ; Conforme"
        }

        [PSCustomObject]@{
            Poste         = $pc.Nom
            AdresseIP     = $pc.AdresseIP
            KBRequises    = $requiredPatches.Count
            KBManquantes  = ($missing -join ", ")
            NbManquantes  = $missing.Count
            Etat          = $etat
            DateControle  = $controlDate
        }

    } catch {
        Write-Host " Erreur remoting" -ForegroundColor Yellow
        Write-PatchLog -Message "$($pc.Nom) ; Erreur remoting ; $($_.Exception.Message)"
        [PSCustomObject]@{
            Poste         = $pc.Nom
            AdresseIP     = $pc.AdresseIP
            KBRequises    = $requiredPatches.Count
            KBManquantes  = $null
            NbManquantes  = $null
            Etat          = "INACCESSIBLE"
            DateControle  = $controlDate
        }
    }
}

# --- Tableau recapitulatif ---
Write-Host "`n=== Resultats ===" -ForegroundColor Cyan
$results | Format-Table Poste, AdresseIP, KBRequises, NbManquantes, Etat -AutoSize

# --- Postes non conformes : detail des KB manquantes ---
$nonConformes = $results | Where-Object { $_.Etat -eq "NON CONFORME" }
if ($nonConformes) {
    Write-Host "`n=== Detail des postes non conformes ===" -ForegroundColor Yellow
    foreach ($pc in $nonConformes) {
        Write-Host "$($pc.Poste) : $($pc.KBManquantes)"
    }
}

# --- Taux global de conformite (hors inaccessibles) ---
# @(...) force le contexte tableau pour que .Count fonctionne meme avec un seul resultat.
$evalues   = @($results | Where-Object { $_.Etat -ne "INACCESSIBLE" })
$conformes = @($evalues | Where-Object { $_.Etat -eq "CONFORME" })
$taux = if ($evalues.Count -gt 0) { [math]::Round(($conformes.Count / $evalues.Count) * 100, 1) } else { 0 }

Write-Host "`nTaux de conformite du parc : $taux % ($($conformes.Count)/$($evalues.Count) postes evalues)" -ForegroundColor Cyan

# --- Export CSV ---
$outputDir = Split-Path $OutputCsv -Parent
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Delimiter ";"
Write-Host "Export genere : $OutputCsv" -ForegroundColor Cyan

return $results