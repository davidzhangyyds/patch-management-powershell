<#
.SYNOPSIS
    Cree l'arborescence complete du projet "patch-management-powershell".

.DESCRIPTION
    A executer depuis la racine du depot deja clone (le dossier qui contient .git).
    Cree les dossiers, les fichiers de configuration de depart, un .gitignore,
    un README.md minimal, et des .gitkeep dans les dossiers generes pour
    qu'ils soient conserves par Git meme vides.

.NOTES
    Executer avec : .\New-ProjectStructure.ps1
    Si l'execution de scripts est bloquee :
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#>

# --- Verification qu'on est bien a la racine d'un depot git ---
if (-not (Test-Path ".git")) {
    Write-Warning "Aucun dossier .git trouve ici. Assure-toi d'etre bien a la racine du depot clone."
    $continue = Read-Host "Continuer quand meme ? (O/N)"
    if ($continue -ne "O") { return }
}

# --- Liste des dossiers a creer ---
$folders = @(
    "config",
    "scripts\modules",
    "templates",
    "logs",
    "reports",
    "secrets",
    "docs\screenshots"
)

foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Write-Host "Dossier cree : $folder" -ForegroundColor Green
    } else {
        Write-Host "Dossier deja existant : $folder" -ForegroundColor Yellow
    }
}

# --- Fichiers .gitkeep dans les dossiers generes (vides pour l'instant) ---
$gitkeepFolders = @("logs", "reports", "docs\screenshots")
foreach ($folder in $gitkeepFolders) {
    $gitkeepPath = Join-Path $folder ".gitkeep"
    if (-not (Test-Path $gitkeepPath)) {
        New-Item -ItemType File -Path $gitkeepPath -Force | Out-Null
    }
}

# --- Fichiers de config de depart ---
$configFiles = @{
    "config\computers.txt" = "PC01;192.168.10.11`nPC02;192.168.10.12`n"
    "config\required-patches.txt" = "KB5034763`nKB5034123`n"
}
foreach ($path in $configFiles.Keys) {
    if (-not (Test-Path $path)) {
        Set-Content -Path $path -Value $configFiles[$path] -Encoding UTF8
        Write-Host "Fichier cree : $path" -ForegroundColor Green
    }
}

# --- Squelettes de scripts (vides avec juste un header) ---
$scriptFiles = @(
    "scripts\modules\PatchManager.psm1",
    "scripts\01-CheckAvailability.ps1",
    "scripts\02-Inventory.ps1",
    "scripts\03-PatchesInventory.ps1",
    "scripts\04-ComplianceCheck.ps1",
    "scripts\05-SecurityReport.ps1",
    "scripts\06-Notification.ps1",
    "scripts\Run-FullAudit.ps1"
)
foreach ($script in $scriptFiles) {
    if (-not (Test-Path $script)) {
        $header = "# $(Split-Path $script -Leaf)`n# TODO : a completer`n"
        Set-Content -Path $script -Value $header -Encoding UTF8
        Write-Host "Script cree : $script" -ForegroundColor Green
    }
}

# --- Gabarit HTML vide ---
if (-not (Test-Path "templates\report-template.html")) {
    Set-Content -Path "templates\report-template.html" -Value "<!-- TODO : gabarit du rapport HTML -->" -Encoding UTF8
}

# --- Exemple de credentials (jamais le vrai fichier) ---
if (-not (Test-Path "secrets\smtp-credentials.example.xml")) {
    $exampleXml = @"
<!-- Exemple de structure attendue pour les identifiants SMTP.
     Ne JAMAIS committer le vrai fichier smtp-credentials.xml -->
<Credentials>
    <SmtpServer>smtp.entreprise.local</SmtpServer>
    <Port>587</Port>
    <From>patchmanager@entreprise.local</From>
    <To>admin@entreprise.local</To>
</Credentials>
"@
    Set-Content -Path "secrets\smtp-credentials.example.xml" -Value $exampleXml -Encoding UTF8
}

# --- .gitignore ---
if (-not (Test-Path ".gitignore")) {
    $gitignore = @"
# Fichiers generes automatiquement par les scripts
logs/*.log
reports/*.csv
reports/*.html

# Secrets - ne jamais versionner les vrais identifiants
secrets/*.xml
!secrets/smtp-credentials.example.xml

# Divers
*.tmp
.vscode/
"@
    Set-Content -Path ".gitignore" -Value $gitignore -Encoding UTF8
    Write-Host "Fichier cree : .gitignore" -ForegroundColor Green
}

# --- README minimal ---
if (-not (Test-Path "README.md")) {
    $readme = @"
# Patch Management PowerShell

Solution simplifiee de Patch Management Windows via PowerShell Remoting / WinRM.

## Prerequis
- PowerShell 5.1+ sur le poste d'administration
- WinRM active sur les postes administres (Enable-PSRemoting)
- Fichier config/computers.txt renseigne avec le parc reel

## Structure
- config/      : inventaire du parc et liste des correctifs obligatoires
- scripts/     : scripts PowerShell (un par partie du projet)
- templates/   : gabarit HTML du rapport
- logs/        : journal d'execution (genere)
- reports/     : rapports generes (CSV/HTML)
- secrets/     : exemple de config SMTP (jamais les vrais identifiants)

## Execution
``````powershell
.\scripts\Run-FullAudit.ps1
``````
"@
    Set-Content -Path "README.md" -Value $readme -Encoding UTF8
    Write-Host "Fichier cree : README.md" -ForegroundColor Green
}

Write-Host "`nArborescence generee avec succes." -ForegroundColor Cyan
Write-Host "Prochaine etape : git add . ; git commit -m 'Initial structure' ; git push" -ForegroundColor Cyan
