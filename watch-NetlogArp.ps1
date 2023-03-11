<#
.SYNOPSIS
Detection des requetes ARP et alimentation de la base de donnée
.DESCRIPTION
Fonction principale de NetLogArp.  Surveille les connexions réseaux afin de 
surveiller les requetes ARP et les inscrits dans 
.PARAMETER databasepath
Chemin d'accès et nom du fichier de base de donnée
.EXAMPLE
PS > initdb()
.TODO
validation du chemin $databasePath
Si le fichier n'existe pas et il est possible d'écrire dans le 
dossier, continuer.  SQLite créer le fichier s'il n'existe pas à la première connexion
#>

param(
    [Parameter(Mandatory=$false)][switch]$listInterface,
    [Parameter(Mandatory=$false)]$InterfaceID,
    [Parameter(Mandatory=$false)][String[]]$InterfaceName, 
    [Parameter(Mandatory=$false)][String[]]$ConfigFile,
    [Parameter(Mandatory=$false)][String[]]$Database,
    [Parameter(ValueFromRemainingArguments=$true)] $args
)
if ($args) { Write-Output "Arguments non utilisés : $args" }

# test seulement, à supprimer
Write-Host "listInterface : $listInterface"
Write-Host "InterfaceID : $InterfaceID"
Write-Host "InterfaceName : $InterfaceName"
write-host "ConfigFile : $ConfigFile"
write-host "Database : $Database"

# a effacer, pour test les parametres de ligne de commande
# $ConfigFile=".\nladb.delete"

# Charge les fonctions de nlaSharedModule.ps1
. .\nlaSharedModule.ps1

# Demande la liste des interfaces réseau
if ($listInterface) {
    get-netAdapter -Physical | Select-Object @{Name="InterfaceName";Expression={$_.Name}},@{Name="InterfaceID";Expression={$_.InterfaceIndex}}
    Exit 0  # retour sans erreur
}

# Déterminer les paramètres de fonctionnement
# Lecture du fichier de configuration
if ($ConfigFile) {
    $nlaEffectiveConfig=FichierDeConfiguration($ConfigFile)
} else {
    $nlaEffectiveConfig=FichierDeConfiguration
}
if (!$nlaEffectiveConfig) {
    Write-Output "Erreur d'interprétation du fichier de configuration.  Est-ce fichier JSON valide ?"
    Exit 1 # retour avec erreur
}

# Les paramètres de la fonction sont prioritaires sur ceux du fichier de configuration.
# L'interface nommé a priorité sur le numéro d'interface

if ($InterfaceID) {
    # Vérifier si l'interface est valide
    $interfaceValide = Get-NetAdapter -InterfaceIndex $InterfaceID -ErrorAction SilentlyContinue
    if ( !$interfaceValide ) {
        # Interface n'est pas valide
        Write-Output "Le numéro d'interface spécifié n'est pas valide :  $InterfaceID"
    } else {
        $nlaEffectiveConfig.interface = [string[]]$(Get-NetAdapter -InterfaceIndex $InterfaceID).Name
    }
}

if ($InterfaceName) {
    # Vérifier si l'interface est valide
    # note : cette section de code est utilisé à plusieurs endroits, il faudrait la mettre dans une fonction
    $interfaceValide = Get-NetAdapter -name $InterfaceName -ErrorAction SilentlyContinue
    if ( !$interfaceValide ) {
        # Interface n'est pas valide
        Write-Host "L'interface spécifié en ligne de commande n'est pas valide :  $InterfaceName"
        Write-Host "Je tente de trouve une interface valide"
        $nlaEffectiveConfig.interface = $null

    } else {
        $nlaEffectiveConfig.interface = $InterfaceName
    }
}
# Si nous avons toujours pas d'interface, nous choississons la première interface physique
if (!$nlaEffectiveConfig.interface) {
    $nlaEffectiveConfig.interface = [string[]]$(Get-NetAdapter -Physical | Select-Object -First 1).Name
    Write-Host "Interface non spécifié, je choisis la première interface physique : $($nlaEffectiveConfig.interface)"
}

# À ce point ci, nous devrions avoir pas mal une ocnfiguration valide.
# A retirer après le test
$nlaEffectiveConfig

# Début de la capture des adresses MAC
# Boucle principale

Get-NetIPAddress -InterfaceAlias $nlaEffectiveConfig.interface -AddressFamily IPv4 | Select-Object IPAddress, PrefixLength
$resultat=$(Get-NetNeighbor -InterfaceAlias $nlaEffectiveConfig.interface  -State "Reachable" | Select-Object  IPAddress, LinkLayerAddress)