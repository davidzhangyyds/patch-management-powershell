<#
.SYNOPSIS
    Partie 7 - Notification automatique de l'administrateur en cas d'anomalie.

.DESCRIPTION
    Analyse le rapport de securite genere par 05-SecurityReport.ps1. Si au
    moins un poste est NON CONFORME ou INACCESSIBLE, construit un message
    recapitulatif et l'envoie par email avec le rapport en piece jointe. Si
    aucune anomalie n'est detectee, le script se termine sans rien envoyer.
    Les identifiants SMTP ne sont jamais ecrits en clair dans le script :
    ils sont lus depuis un fichier credentials chiffre (Export-Clixml).

.NOTES
    Entree  : reports\SecurityReport.csv (+ SecurityReport.html en piece jointe)
    Credentials SMTP : secrets\smtp-credentials.xml (genere via Export-Clixml,
                        jamais commite - voir secrets\smtp-credentials.example.xml)
#>

[CmdletBinding()]
param(
    [string]$SecurityReportCsv  = "$PSScriptRoot\..\reports\SecurityReport.csv",
    [string]$SecurityReportHtml = "$PSScriptRoot\..\reports\SecurityReport.html",
    #[string]$CredentialsFile    = "$PSScriptRoot\..\secrets\smtp-credentials.xml",
    [string]$SmtpServer         = "smtp.entreprise.local",
    [int]$SmtpPort              = 587,
    [string]$From               = "patchmanager@entreprise.local",
    [string]$To                 = "admin@entreprise.local",
    [switch]$NoAuth,             # a utiliser avec un serveur de test type smtp4dev (localhost:25, sans auth)
    [switch]$NoSsl               # a utiliser avec un serveur de test sans TLS
)

Import-Module "$PSScriptRoot\modules\PatchManager.psm1" -Force

if (-not (Test-Path $SecurityReportCsv)) {
    Write-Error "Introuvable : $SecurityReportCsv. Lance d'abord 05-SecurityReport.ps1"
    return
}

$report = Import-Csv -Path $SecurityReportCsv -Delimiter ";"

# --- Detection d'anomalie ---
$anomalies = $report | Where-Object { $_.EtatConformite -eq "NON CONFORME" -or $_.Accessibilite -eq "Inaccessible" }

if (-not $anomalies) {
    Write-Host "Aucune anomalie detectee. Pas de notification envoyee." -ForegroundColor Green
    return
}

# @(...) force le contexte tableau : sans lui, .Count renvoie $null quand un seul
# poste correspond au filtre (piege classique PowerShell avec Where-Object).
$nonConformes  = @($anomalies | Where-Object { $_.EtatConformite -eq "NON CONFORME" })
$inaccessibles = @($anomalies | Where-Object { $_.Accessibilite -eq "Inaccessible" })

# --- Construction du message ---
$bodyLines = @()
$bodyLines += "Date du controle : $(Get-Date -Format 'dd/MM/yyyy')"
$bodyLines += ""
$bodyLines += "Postes controles    : $($report.Count)"
$bodyLines += "Postes non conformes: $($nonConformes.Count)"
$bodyLines += "Postes inaccessibles: $($inaccessibles.Count)"
$bodyLines += ""

foreach ($pc in $nonConformes) {
    $bodyLines += "$($pc.Poste) : NON CONFORME"
    $bodyLines += "    $($pc.KBManquantes) manquante(s)"
    $bodyLines += ""
}
foreach ($pc in $inaccessibles) {
    $bodyLines += "$($pc.Poste) : INACCESSIBLE"
    $bodyLines += ""
}

$subject = "[PATCH MANAGEMENT] Anomalies detectees"
$body    = $bodyLines -join "`n"

Write-Host "`n=== Message de notification ===" -ForegroundColor Cyan
Write-Host $body

# --- Lecture des identifiants SMTP (jamais en clair dans le script) ---
# Avec -NoAuth (serveur de test type smtp4dev), aucun credential n'est requis.
$cred = $null
if (-not $NoAuth) {
    if (-not (Test-Path $CredentialsFile)) {
        Write-Warning "Fichier de credentials introuvable : $CredentialsFile"
        Write-Warning "Cree-le au prealable avec :"
        Write-Warning '  Get-Credential | Export-Clixml -Path "secrets\smtp-credentials.xml"'
        Write-Warning "Ou relance avec -NoAuth si tu testes avec un serveur SMTP local (smtp4dev)."
        Write-PatchLog -Message "ERREUR ; Notification non envoyee ; credentials introuvables"
        return
    }
    $cred = Import-Clixml -Path $CredentialsFile
}

try {
    $mailParams = @{
        SmtpServer = $SmtpServer
        Port       = $SmtpPort
        UseSsl     = -not $NoSsl
        From       = $From
        To         = $To
        Subject    = $subject
        Body       = $body
        ErrorAction= "Stop"
    }
    if ($cred) { $mailParams["Credential"] = $cred }
    if (Test-Path $SecurityReportHtml) {
        $mailParams["Attachments"] = $SecurityReportHtml
    }

    Send-MailMessage @mailParams

    Write-Host "`nNotification envoyee a $To" -ForegroundColor Green
    Write-PatchLog -Message "Notification envoyee a $To"

} catch {
    Write-Host "`nEchec de l'envoi : $($_.Exception.Message)" -ForegroundColor Red
    Write-PatchLog -Message "ERREUR ; Notification non envoyee ; $($_.Exception.Message)"
}