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
    [Parameter(Mandatory=$false)][String[]]$MACAddress, 
    [Parameter(Mandatory=$false)][String[]]$ConfigFile,
    [Parameter(Mandatory=$false)][String[]]$Database,
    [Parameter(Mandatory=$false)][switch]$ResolveIP,
    [Parameter(ValueFromRemainingArguments=$true)] $args
)
if ($args) { Write-Output "Arguments non utilisés : $args" }

# Charge les fonctions de nlaSharedModule.ps1
. .\nlaSharedModule.ps1

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

# Initialisation de la base de donnée
$nlaDBConnexion = initDB -databasePath $nlaEffectiveConfig.sqlitePath
if (!$nlaDBConnexion) {
    Write-Output "Erreur d'initialisation de la base de donnée"
    Exit 1 # retour avec erreur
}

if ($MACAddress) {
    # Si une adress MAC est spécifié, on retourne l'historique IP liées
    $sqlquery = "SELECT AddressMAC.address as MacAddr, AddressIP.Address as IPAddr, AddressIP.mask as IPMask, AddressIP.subnet as IPMask , T_IS.Seen as LastRelate, AddressMAC.FirstSeen as FirstSeen
    FROM AddressIP
    JOIN T_Is ON AddressIP.ROWID = T_Is.IpID
    JOIN AddressMAC ON T_Is.MacID = AddressMAC.ROWID
    WHERE AddressMAC.address=@MAC";
} else {
    # Sinon on retourne le dernier IP associé à chaque MAC
    $sqlquery = "SELECT AddressMAC.address as MacAddr, AddressIP.Address as IPAddr, AddressIP.mask as IPMask, AddressIP.subnet as IPMask, T_IS.Seen as LastRelated, AddressMAC.FirstSeen as FirstSeen
    FROM AddressIP
    JOIN T_Is ON AddressIP.ROWID = T_Is.IpID
    JOIN AddressMAC ON T_Is.MacID = AddressMAC.ROWID
    WHERE T_Is.ROWID IN (SELECT ROWID FROM (SELECT  ROWID, MAX(Seen) FROM T_Is GROUP BY MACID))"
    }
Invoke-SqliteQuery -SQLiteConnection $nlaDBConnexion -Query $sqlquery -SqlParameters @{
    MAC = (Clean-MacAddress -MacAddress $($MACAddress) )
}