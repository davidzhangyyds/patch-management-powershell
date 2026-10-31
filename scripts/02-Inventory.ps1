# 02-Inventory.ps1

<#
.SYNOPSIS
    Partie 2 - Inventaire du parc : collecte des caracteristiques systeme
    et des informations Patch Management de chaque poste accessible.

.DESCRIPTION
    Lit computers.txt, teste la disponibilite de chaque machine, puis pour
    les postes accessibles utilise PowerShell Remoting (Invoke-Command) pour
    recuperer : modele, BIOS, version/edition Windows, architecture, dernier
    demarrage, RAM, espace disque disponible, date du dernier correctif,
    nombre de correctifs installes, etat du service Windows Update.

    Les machines inaccessibles ou en erreur sont conservees dans l'inventaire
    avec un etat explicite, sans interrompre l'execution du script.

.NOTES
    Fichier attendu : config\computers.txt
    Export genere   : reports\Inventory.csv
#>

[CmdletBinding()]
param(
    [string]$ComputersFile = "$PSScriptRoot\..\config\computers.txt",
    [string]$OutputCsv     = "$PSScriptRoot\..\reports\Inventory.csv",
    [System.Management.Automation.PSCredential]$Credential
)

if (-not (Test-Path $ComputersFile)) {
    Write-Error "Fichier introuvable : $ComputersFile"
    return
}

# Demande les identifiants une seule fois si non fournis (comptes locaux/domaine differents de la session courante)
if (-not $Credential) {
    $Credential = Get-Credential -Message "Identifiants pour PowerShell Remoting (laisser vide = session courante)" -ErrorAction SilentlyContinue
}

# --- Lecture de l'inventaire de base ---
$computers = Get-Content -Path $ComputersFile |
    Where-Object { $_.Trim() -ne "" } |
    ForEach-Object {
        $parts = $_ -split ";"
        [PSCustomObject]@{ Nom = $parts[0].Trim(); AdresseIP = $parts[1].Trim() }
    }

Write-Host "`n=== Inventaire de $($computers.Count) poste(s) ===" -ForegroundColor Cyan

$inventory = foreach ($pc in $computers) {

    Write-Host "Traitement de $($pc.Nom) ($($pc.AdresseIP))..." -NoNewline

    # --- Test de disponibilite reseau avant toute tentative de remoting ---
    $isReachable = Test-Connection -ComputerName $pc.AdresseIP -Count 2 -Quiet -ErrorAction SilentlyContinue

    if (-not $isReachable) {
        Write-Host " Inaccessible" -ForegroundColor Red
        [PSCustomObject]@{
            Poste               = $pc.Nom
            AdresseIP           = $pc.AdresseIP
            Etat                = "Inaccessible"
            Modele              = $null
            VersionBios         = $null
            Windows             = $null
            Architecture        = $null
            DernierDemarrage    = $null
            RAM_Go              = $null
            DisqueLibre_Go      = $null
            DateDernierCorrectif= $null
            NbCorrectifs        = $null
            WindowsUpdateEtat   = $null
            Erreur              = "Hote injoignable (ping)"
        }
        continue
    }

    # --- Collecte distante via Invoke-Command ---
    try {
        $sessionParams = @{
            ComputerName = $pc.AdresseIP
            ErrorAction  = "Stop"
        }
        if ($Credential) { $sessionParams["Credential"] = $Credential }

        $remoteData = Invoke-Command @sessionParams -ScriptBlock {

            $os     = Get-CimInstance -ClassName Win32_OperatingSystem
            $cs     = Get-CimInstance -ClassName Win32_ComputerSystem
            $bios   = Get-CimInstance -ClassName Win32_BIOS
            $disk   = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
            $hotfix = Get-HotFix | Sort-Object InstalledOn -Descending
            $wu     = Get-Service -Name wuauserv

            [PSCustomObject]@{
                Modele               = $cs.Model
                VersionBios          = $bios.SMBIOSBIOSVersion
                Windows              = "$($os.Caption) ($($os.Version))"
                Architecture         = $os.OSArchitecture
                DernierDemarrage     = $os.LastBootUpTime
                RAM_Go               = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
                DisqueLibre_Go       = [math]::Round($disk.FreeSpace / 1GB, 1)
                DateDernierCorrectif = ($hotfix | Select-Object -First 1).InstalledOn
                NbCorrectifs         = $hotfix.Count
                WindowsUpdateEtat    = $wu.Status
            }
        }

        Write-Host " Accessible" -ForegroundColor Green

        [PSCustomObject]@{
            Poste                = $pc.Nom
            AdresseIP            = $pc.AdresseIP
            Etat                 = "Accessible"
            Modele               = $remoteData.Modele
            VersionBios          = $remoteData.VersionBios
            Windows              = $remoteData.Windows
            Architecture         = $remoteData.Architecture
            DernierDemarrage     = $remoteData.DernierDemarrage
            RAM_Go               = $remoteData.RAM_Go
            DisqueLibre_Go       = $remoteData.DisqueLibre_Go
            DateDernierCorrectif = $remoteData.DateDernierCorrectif
            NbCorrectifs         = $remoteData.NbCorrectifs
            WindowsUpdateEtat    = $remoteData.WindowsUpdateEtat
            Erreur               = $null
        }

    } catch {
        # Ping OK mais WinRM/remoting en echec (service arrete, pare-feu, credentials...)
        Write-Host " Erreur remoting" -ForegroundColor Yellow
        [PSCustomObject]@{
            Poste                = $pc.Nom
            AdresseIP            = $pc.AdresseIP
            Etat                 = "Inaccessible"
            Modele               = $null
            VersionBios          = $null
            Windows              = $null
            Architecture         = $null
            DernierDemarrage     = $null
            RAM_Go               = $null
            DisqueLibre_Go       = $null
            DateDernierCorrectif = $null
            NbCorrectifs         = $null
            WindowsUpdateEtat    = $null
            Erreur               = $_.Exception.Message
        }
    }
}

# --- Tableau recapitulatif ---
Write-Host "`n=== Recapitulatif ===" -ForegroundColor Cyan
$inventory | Format-Table Poste, AdresseIP, Windows, Architecture, DernierDemarrage, WindowsUpdateEtat, Etat -AutoSize

# --- Export CSV ---
$outputDir = Split-Path $OutputCsv -Parent
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }

$inventory | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Delimiter ";"
Write-Host "`nInventaire exporte vers : $OutputCsv" -ForegroundColor Cyan

return $inventory
