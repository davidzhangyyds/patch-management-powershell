<#
.SYNOPSIS
    Orchestrateur - enchaine l'ensemble des etapes du Patch Management.

.DESCRIPTION
    Execute dans l'ordre : inventaire du parc, inventaire des correctifs,
    controle de conformite, generation du rapport de securite, puis
    notification si une anomalie est detectee. C'est ce script que l'on
    presente dans la video de demonstration.

.NOTES
    Pre-requis : computers.txt et required-patches.txt renseignes dans config\,
    WinRM actif sur les postes cibles (voir 00-SetupRemoting.ps1 sur chaque poste).
#>

[CmdletBinding()]
param(
    [System.Management.Automation.PSCredential]$Credential,

    # Parametres transmis a 06-Notification.ps1 (serveur SMTP de test type smtp4dev)
    [string]$SmtpServer = "smtp.entreprise.local",
    [int]$SmtpPort      = 587,
    [string]$From       = "patchmanager@entreprise.local",
    [string]$To         = "admin@entreprise.local",
    [switch]$NoAuth,
    [switch]$NoSsl
)

$ScriptsDir = $PSScriptRoot

if (-not $Credential) {
    $Credential = Get-Credential -Message "Identifiants pour PowerShell Remoting (vide = session courante)" -ErrorAction SilentlyContinue
}

Write-Host "`n#################################################" -ForegroundColor Magenta
Write-Host "#  AUDIT PATCH MANAGEMENT - $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor Magenta
Write-Host "#################################################`n" -ForegroundColor Magenta

Write-Host ">>> Etape 1/5 : Verification de disponibilite" -ForegroundColor Magenta
& "$ScriptsDir\01-CheckAvailability.ps1" | Out-Null

Write-Host "`n>>> Etape 2/5 : Inventaire du parc" -ForegroundColor Magenta
& "$ScriptsDir\02-Inventory.ps1" -Credential $Credential | Out-Null

Write-Host "`n>>> Etape 3/5 : Inventaire des correctifs" -ForegroundColor Magenta
& "$ScriptsDir\03-PatchesInventory.ps1" -Credential $Credential | Out-Null

Write-Host "`n>>> Etape 4/5 : Controle de conformite" -ForegroundColor Magenta
& "$ScriptsDir\04-ComplianceCheck.ps1" -Credential $Credential | Out-Null

Write-Host "`n>>> Etape 5/5 : Rapport de securite + notification" -ForegroundColor Magenta
$auditResult = & "$ScriptsDir\05-SecurityReport.ps1"

$notifParams = @{
    SmtpServer = $SmtpServer
    SmtpPort   = $SmtpPort
    From       = $From
    To         = $To
    NoAuth     = $NoAuth
    NoSsl      = $NoSsl
}
& "$ScriptsDir\06-Notification.ps1" @notifParams

Write-Host "`n#################################################" -ForegroundColor Magenta
Write-Host "#  AUDIT TERMINE" -ForegroundColor Magenta
Write-Host "#################################################" -ForegroundColor Magenta

return $auditResult