<#
.SYNOPSIS
    Partie 6 - Rapport de securite consolide (synthese du parc + HTML).

.DESCRIPTION
    Combine les resultats d'inventaire (02-Inventory) et de conformite
    (04-ComplianceCheck) pour produire un rapport par poste, une synthese
    globale du parc, une section "postes necessitant une intervention", et
    une version HTML. Journalise le debut/fin de l'audit.

.NOTES
    Entrees : reports\Inventory.csv, reports\ComplianceReport.csv
    Sorties : reports\SecurityReport.csv, reports\SecurityReport.html
#>

[CmdletBinding()]
param(
    [string]$InventoryCsv   = "$PSScriptRoot\..\reports\Inventory.csv",
    [string]$ComplianceCsv  = "$PSScriptRoot\..\reports\ComplianceReport.csv",
    [string]$OutputCsv      = "$PSScriptRoot\..\reports\SecurityReport.csv",
    [string]$OutputHtml     = "$PSScriptRoot\..\reports\SecurityReport.html",
    [string]$TemplatePath   = "$PSScriptRoot\..\templates\report-template.html"
)

Import-Module "$PSScriptRoot\modules\PatchManager.psm1" -Force

Write-PatchLog -Message "Debut de l'audit"

if (-not (Test-Path $InventoryCsv))  { Write-Error "Introuvable : $InventoryCsv. Lance d'abord 02-Inventory.ps1"; return }
if (-not (Test-Path $ComplianceCsv)) { Write-Error "Introuvable : $ComplianceCsv. Lance d'abord 04-ComplianceCheck.ps1"; return }

$inventory   = Import-Csv -Path $InventoryCsv   -Delimiter ";"
$compliance  = Import-Csv -Path $ComplianceCsv  -Delimiter ";"

# --- Fusion inventaire + conformite par poste ---
$report = foreach ($inv in $inventory) {
    $comp = $compliance | Where-Object { $_.Poste -eq $inv.Poste } | Select-Object -First 1

    [PSCustomObject]@{
        Poste               = $inv.Poste
        AdresseIP           = $inv.AdresseIP
        Accessibilite       = $inv.Etat
        Windows             = $inv.Windows
        DernierDemarrage    = $inv.DernierDemarrage
        WindowsUpdateEtat   = $inv.WindowsUpdateEtat
        KBRequises          = $comp.KBRequises
        NbManquantes        = $comp.NbManquantes
        KBManquantes        = $comp.KBManquantes
        EtatConformite      = $comp.Etat
        DateControle        = $comp.DateControle
    }
}

# --- Synthese globale ---
# @(...) force le contexte tableau : sans lui, .Count renvoie $null (silencieusement,
# pas 0, pas d'erreur visible) quand Where-Object ne retourne qu'un seul objet au lieu
# d'une collection. C'est exactement ce qui se produit avec 1 seul poste conforme et
# 1 seul poste non conforme : chaque filtre retourne un objet isole, pas un tableau.
$totalPostes       = @($report).Count
$accessibles       = @($report | Where-Object { $_.Accessibilite -eq "Accessible" }).Count
$inaccessibles     = $totalPostes - $accessibles
$conformes         = @($report | Where-Object { $_.EtatConformite -eq "CONFORME" }).Count
$nonConformes      = @($report | Where-Object { $_.EtatConformite -eq "NON CONFORME" }).Count
$totalManquants    = ($report | Where-Object { $_.NbManquantes } | Measure-Object -Property NbManquantes -Sum).Sum
if (-not $totalManquants) { $totalManquants = 0 }
$evalues           = $conformes + $nonConformes
$tauxConformite    = if ($evalues -gt 0) { [math]::Round(($conformes / $evalues) * 100, 1) } else { 0 }

Write-Host "`n=== Synthese du parc ===" -ForegroundColor Cyan
Write-Host "Nombre total de postes      : $totalPostes"
Write-Host "Nombre de postes accessibles: $accessibles"
Write-Host "Nombre de postes inaccessibles : $inaccessibles"
Write-Host "Nombre de postes conformes  : $conformes"
Write-Host "Nombre de postes non conformes : $nonConformes"
Write-Host "Nombre total de correctifs manquants : $totalManquants"
Write-Host "Taux de conformite          : $tauxConformite %" -ForegroundColor Cyan

# --- Postes necessitant une intervention ---
$aTraiter = @($report | Where-Object { $_.EtatConformite -eq "NON CONFORME" -or $_.Accessibilite -eq "Inaccessible" })

Write-Host "`n=== Postes necessitant une intervention ===" -ForegroundColor Yellow
if ($aTraiter.Count -gt 0) {
    $aTraiter | Format-Table Poste, AdresseIP, Accessibilite, EtatConformite, KBManquantes -AutoSize
} else {
    Write-Host "Aucun." -ForegroundColor Green
}

# --- Export CSV ---
$outputDir = Split-Path $OutputCsv -Parent
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
$report | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Delimiter ";"

# --- Generation HTML ---
function ConvertTo-Html5Row($row) {
    $etatClass = switch ($row.EtatConformite) {
        "CONFORME"     { "ok" }
        "NON CONFORME" { "warn" }
        default        { "err" }
    }
    "<tr class=`"$etatClass`">
        <td>$($row.Poste)</td><td>$($row.AdresseIP)</td><td>$($row.Accessibilite)</td>
        <td>$($row.Windows)</td><td>$($row.DernierDemarrage)</td>
        <td>$($row.WindowsUpdateEtat)</td><td>$($row.NbManquantes)</td>
        <td>$($row.KBManquantes)</td><td>$($row.EtatConformite)</td>
    </tr>"
}

$rowsHtml = ($report | ForEach-Object { ConvertTo-Html5Row $_ }) -join "`n"

$html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>Rapport de securite - Patch Management</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 2em; background: #f4f6f8; color: #222; }
h1 { color: #1a3c5e; }
.summary { background: #fff; padding: 1em 1.5em; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,.1); margin-bottom: 1.5em; }
.summary span { display: inline-block; margin-right: 2em; }
table { border-collapse: collapse; width: 100%; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,.1); }
th, td { border: 1px solid #ddd; padding: 8px 10px; text-align: left; font-size: 0.9em; }
th { background: #1a3c5e; color: #fff; }
tr.ok   { background: #e6f4ea; }
tr.warn { background: #fff4e5; }
tr.err  { background: #fde8e8; }
</style>
</head>
<body>
<h1>Rapport de securite - Patch Management</h1>
<p>Genere le $(Get-Date -Format "dd/MM/yyyy a HH:mm:ss")</p>

<div class="summary">
<span><strong>Postes totaux :</strong> $totalPostes</span>
<span><strong>Accessibles :</strong> $accessibles</span>
<span><strong>Inaccessibles :</strong> $inaccessibles</span>
<span><strong>Conformes :</strong> $conformes</span>
<span><strong>Non conformes :</strong> $nonConformes</span>
<span><strong>Correctifs manquants (total) :</strong> $totalManquants</span>
<span><strong>Taux de conformite :</strong> $tauxConformite %</span>
</div>

<h2>Detail par poste</h2>
<table>
<tr><th>Poste</th><th>IP</th><th>Accessibilite</th><th>Windows</th><th>Dernier demarrage</th><th>Windows Update</th><th>KB manquantes (nb)</th><th>KB manquantes (liste)</th><th>Conformite</th></tr>
$rowsHtml
</table>

</body>
</html>
"@

$outputHtmlDir = Split-Path $OutputHtml -Parent
if (-not (Test-Path $outputHtmlDir)) { New-Item -ItemType Directory -Path $outputHtmlDir -Force | Out-Null }
Set-Content -Path $OutputHtml -Value $html -Encoding UTF8

Write-Host "`nRapport CSV  : $OutputCsv" -ForegroundColor Cyan
Write-Host "Rapport HTML : $OutputHtml" -ForegroundColor Cyan

Write-PatchLog -Message "Rapport genere"
Write-PatchLog -Message "Fin de l'audit"

return [PSCustomObject]@{
    Report         = $report
    PostesATraiter = $aTraiter
    Synthese       = [PSCustomObject]@{
        TotalPostes      = $totalPostes
        Accessibles      = $accessibles
        Inaccessibles    = $inaccessibles
        Conformes        = $conformes
        NonConformes     = $nonConformes
        TotalManquants   = $totalManquants
        TauxConformite   = $tauxConformite
    }
}