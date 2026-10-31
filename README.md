# Patch Management Simplifié — PowerShell

Solution d'audit et de gestion des correctifs de sécurité pour un parc de postes Windows, via PowerShell Remoting (WinRM). Projet réalisé dans le cadre du cours de Sécurité des systèmes d'exploitation — EFREI ING2 S7.

## Objectif

Automatiser, depuis un poste d'administration, l'audit de conformité d'un parc Windows :

1. Vérifier la disponibilité des postes
2. Inventorier leurs caractéristiques système
3. Inventorier les correctifs de sécurité installés
4. Contrôler leur conformité par rapport à une liste de correctifs obligatoires
5. Générer un rapport de sécurité consolidé (CSV + HTML)
6. Notifier automatiquement l'administrateur par email en cas d'anomalie

## Architecture

```
Poste d'administration (PowerShell)
        │  PowerShell Remoting (WinRM)
        ▼
┌──────────────┬──────────────┐
│    PC01      │    PC02      │
│  (parc test) │  (parc test) │
└──────────────┴──────────────┘
```

Le poste d'administration exécute les scripts ; les postes du parc n'ont besoin que de WinRM activé (`Enable-PSRemoting`).

## Prérequis

- PowerShell 5.1 ou supérieur sur le poste d'administration
- WinRM activé et accessible sur chaque poste administré (voir `scripts/00-SetupRemoting.ps1`)
- Un compte disposant des droits d'administration sur les postes distants
- Pour la notification par email : un serveur SMTP (voir section [Notification](#notification-par-email))

## Structure du dépôt

```
patch-management-powershell/
│
├── README.md
├── .gitignore
│
├── config/
│   ├── computers.txt              # Inventaire du parc (Nom;IP)
│   └── required-patches.txt       # Liste des KB obligatoires
│
├── scripts/
│   ├── modules/
│   │   └── PatchManager.psm1      # Fonctions communes (log, lecture inventaire, test ping)
│   │
│   ├── 00-SetupRemoting.ps1       # Active/vérifie WinRM (à exécuter sur chaque poste cible)
│   ├── 01-CheckAvailability.ps1   # Vérifie la disponibilité des postes
│   ├── 02-Inventory.ps1           # Inventaire système du parc
│   ├── 03-PatchesInventory.ps1    # Inventaire détaillé des correctifs
│   ├── 04-ComplianceCheck.ps1     # Contrôle de conformité
│   ├── 05-SecurityReport.ps1      # Rapport de sécurité consolidé (CSV + HTML)
│   ├── 06-Notification.ps1        # Notification email en cas d'anomalie
│   └── Run-FullAudit.ps1          # Orchestrateur : exécute les étapes 1 à 6 dans l'ordre
│
├── templates/
│   └── report-template.html       # Gabarit HTML du rapport
│
├── logs/
│   └── PatchManager.log           # Journal d'exécution horodaté (généré)
│
├── reports/                       # Rapports générés (CSV/HTML, générés)
│
├── secrets/
│   └── smtp-credentials.example.txt   # Doc sur le format attendu — jamais les vrais identifiants
│
└── docs/
    └── Rapport-Projet.docx        # Rapport synthétique du projet
```

## Installation et configuration

### 1. Cloner le dépôt

```powershell
git clone https://github.com/<votre-compte>/patch-management-powershell.git
cd patch-management-powershell
```

### 2. Configurer le parc

Renseignez `config/computers.txt` (une machine par ligne) :

```
PC01;192.168.10.11
PC02;192.168.10.12
```

Renseignez `config/required-patches.txt` (un KB par ligne) :

```
KB5044284
KB5041585
```

### 3. Activer PowerShell Remoting sur chaque poste cible

En tant qu'administrateur, sur chaque poste administré :

```powershell
.\scripts\00-SetupRemoting.ps1
```

Si les postes ne sont pas dans un domaine commun, autorisez-les en `TrustedHosts` depuis le poste d'administration :

```powershell
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.10.*" -Force
```

## Exécution

### Audit complet (recommandé)

```powershell
cd scripts
.\Run-FullAudit.ps1
```

Le script demande les identifiants pour PowerShell Remoting (laisser vide pour utiliser la session courante), puis enchaîne automatiquement toutes les étapes.

### Scripts individuels

Chaque script peut aussi être exécuté séparément :

```powershell
.\01-CheckAvailability.ps1
.\02-Inventory.ps1
.\03-PatchesInventory.ps1
.\04-ComplianceCheck.ps1
.\05-SecurityReport.ps1
.\06-Notification.ps1
```

## Notification par email

Le script `06-Notification.ps1` n'envoie un email que si une anomalie est détectée (poste non conforme ou inaccessible).

### Avec un vrai serveur SMTP (authentifié)

Générez d'abord le fichier de credentials chiffré (jamais en clair, jamais committé) :

```powershell
Get-Credential | Export-Clixml -Path "secrets\smtp-credentials.xml"
```

Puis lancez :

```powershell
.\06-Notification.ps1 -SmtpServer "smtp.exemple.com" -SmtpPort 587 -From "patchmanager@exemple.com" -To "admin@exemple.com"
```

### Avec un serveur SMTP de test local (smtp4dev)

Pratique pour démonstration sans compte ni serveur réel : voir [smtp4dev](https://github.com/rnwood/smtp4dev).

```powershell
.\06-Notification.ps1 -SmtpServer "localhost" -SmtpPort 25 -NoAuth -NoSsl
```

L'interface web de smtp4dev (`http://localhost:3000`) affiche les emails reçus.

## Sécurité

- **Aucun identifiant en clair** dans le code : les secrets SMTP sont stockés chiffrés via `Export-Clixml`, liés au compte Windows qui les a créés
- `secrets/*.xml` et `reports/*` sont exclus du suivi Git (voir `.gitignore`)
- Principe de moindre privilège recommandé : utiliser un compte dédié à l'administration des correctifs plutôt qu'un compte administrateur de domaine
- `required-patches.txt` doit être mis à jour régulièrement, les vulnérabilités et correctifs évoluant en continu (Patch Tuesday mensuel)

## Limites connues

- Suppose un environnement de confiance (workgroup ou domaine) ; pas de chiffrement WinRM par certificat
- Le contrôle de conformité se limite aux correctifs listés manuellement dans `required-patches.txt`
- Pas de gestion de parc à grande échelle (prévu pour un nombre restreint de postes de test)

## Auteur

David Zhang & Kevin Jiang — EFREI ING2 S7 — Projet Sécurité des systèmes d'exploitation
