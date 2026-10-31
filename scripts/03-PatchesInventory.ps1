<#
.SYNOPSIS
    Partie 3 - Inventaire detaille des correctifs installes sur chaque poste.

.DESCRIPTION
    Pour chaque machine accessible de computers.txt, recupere via PowerShell
    Remoting la liste complete des correctifs installes (KB, description,
    date d'installation, utilisateur si disponible), les regroupe, les trie
    par poste puis par date decroissante, et exporte le tout dans
    PatchesInventory.csv. Affiche aussi, par machine : nombre total de
    correctifs, date du plus recent, KB du dernier installe.

.NOTES
    Fichier attendu : config\computers.txt
    Export genere   : reports\PatchesInventory.csv
#>

[CmdletBinding()]
param(
    [string]$ComputersFile = "$PSScriptRoot\..\config\computers.txt",
    [string]$OutputCsv     = "$PSScriptRoot\..\reports\PatchesInventory.csv",
    [System.Management.Automation.PSCredential]$Credential
)

Import-Module "$PSScriptRoot\modules\PatchManager.psm1" -Force

if (-not $Credential) {
    $Credential = Get-Credential -Message "Identifiants pour PowerShell Remoting (vide = session courante)" -ErrorAction SilentlyContinue
}

$computers = Get-ComputerInventory -Path $ComputersFile
Write-Host "`n=== Inventaire des correctifs - $($computers.Count) poste(s) ===" -ForegroundColor Cyan

$allPatches = foreach ($pc in $computers) {

    Write-Host "Traitement de $($pc.Nom) ($($pc.AdresseIP))..." -NoNewline

    if (-not (Test-PCAvailability -ComputerName $pc.AdresseIP)) {
        Write-Host " Inaccessible" -ForegroundColor Red
        Write-PatchLog -Message "$($pc.Nom) ; Inaccessible (ping)"
        [PSCustomObject]@{
            Poste = $pc.Nom; AdresseIP = $pc.AdresseIP
            KB = $null; Description = $null; DateInstallation = $null; InstallePar = $null
            Erreur = "Hote injoignable"
        }
        continue
    }

    try {
        $sessionParams = @{ ComputerName = $pc.AdresseIP; ErrorAction = "Stop" }
        if ($Credential) { $sessionParams["Credential"] = $Credential }

        $patches = Invoke-Command @sessionParams -ScriptBlock {
            Get-HotFix | ForEach-Object {
                [PSCustomObject]@{
                    KB               = $_.HotFixID
                    Description      = $_.Description
                    DateInstallation = $_.InstalledOn
                    InstallePar      = $_.InstalledBy
                }
            }
        }

        Write-Host " OK ($($patches.Count) correctif(s))" -ForegroundColor Green
        Write-PatchLog -Message "$($pc.Nom) ; Accessible ; $($patches.Count) correctifs recenses"

        foreach ($p in $patches) {
            [PSCustomObject]@{
                Poste = $pc.Nom; AdresseIP = $pc.AdresseIP
                KB = $p.KB; Description = $p.Description
                DateInstallation = $p.DateInstallation; InstallePar = $p.InstallePar
                Erreur = $null
            }
        }

    } catch {
        Write-Host " Erreur remoting" -ForegroundColor Yellow
        Write-PatchLog -Message "$($pc.Nom) ; Erreur remoting ; $($_.Exception.Message)"
        [PSCustomObject]@{
            Poste = $pc.Nom; AdresseIP = $pc.AdresseIP
            KB = $null; Description = $null; DateInstallation = $null; InstallePar = $null
            Erreur = $_.Exception.Message
        }
    }
}

# --- Tri : par poste puis date d'installation decroissante ---
$sorted = $allPatches | Sort-Object Poste, @{Expression = "DateInstallation"; Descending = $true}

# --- Resume par machine ---
Write-Host "`n=== Resume par poste ===" -ForegroundColor Cyan
$summary = $sorted | Where-Object { $_.KB } | Group-Object Poste | ForEach-Object {
    $latest = $_.Group | Sort-Object DateInstallation -Descending | Select-Object -First 1
    [PSCustomObject]@{
        Poste            = $_.Name
        NbCorrectifs     = $_.Count
        DatePlusRecente  = $latest.DateInstallation
        DernierKB        = $latest.KB
    }
}
$summary | Format-Table -AutoSize

# --- Export CSV ---
$outputDir = Split-Path $OutputCsv -Parent
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
$sorted | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Delimiter ";"

Write-Host "`nExport genere : $OutputCsv" -ForegroundColor Cyan
return $sorted