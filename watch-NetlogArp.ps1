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
#$nlaEffectiveConfig

# Initialisation de la base de donnée
$nlaDBConnexion = initDB -databasePath $nlaEffectiveConfig.sqlitePath
if (!$nlaDBConnexion) {
    Write-Output "Erreur d'initialisation de la base de donnée"
    Exit 1 # retour avec erreur
}

# Début de la capture des adresses MAC

# initialisation des variables
# pour le moment, nous allons utiliser que le site par défaut
$nlaQuerySite = 'select rowid from segment where name="DEFAUT" LIMIT 1;'
if (!( $sqlresult=(Invoke-sqliteQuery -SQLiteConnection $nlaDBConnexion -Query $nlaQuerySite -ErrorAction SilentlyContinue) ) )
    { Write-Host "Erreur de lecture de la base de donnée"}
$nlaSiteID = $sqlresult.rowid

# Identification des caractéristiques de l'interface
$nlaInterfaceDetail = Get-NetIPAddress -InterfaceAlias $nlaEffectiveConfig.interface -AddressFamily IPv4 | Select-Object IPAddress, PrefixLength,  @{name="subnet"; Expression={calculateSubnet -IPString $_.IPAddress -mask $_.PrefixLength }}


# Boucle principale

while ($true) {
  
     # tache 1, récupérer les adresses MAC

    $MacIpNeighbor=$(Get-NetNeighbor -InterfaceAlias $nlaEffectiveConfig.interface  -State "Reachable" | Select-Object  IPAddress, LinkLayerAddress)    
    if ($MacIpNeighbor.Count) {
        $dateObservation = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        foreach ($MacIP in $MacIpNeighbor) {
                        
            $nlaQueryCheckMAC="SELECT rowid FROM AddressMAC
                WHERE AddressMAC.address=@MAC 
                AND AddressMAC.segmentID=1 AND AddressMAC.deleted=0;"
            
            # Est-ce que la MAC est déjà dans la base de donnée ?  Conserver rowid
            if (!( $sqlresult=(Invoke-sqliteQuery -SQLiteConnection $nlaDBConnexion -Query $nlaQueryCheckMAC -SqlParameters @{MAC=(Clean-MacAddress -MacAddress $MacIP.LinkLayerAddress )} -ErrorAction SilentlyContinue) ) ) {
                # aucun resultat.  ajoutons l'adresse
                $nlaQueryAddMac="INSERT INTO AddressMAC (segmentID, address, FirstSeen, deleted ) Values (1, @MAC, @DATE, 0 )"
                Invoke-SqliteQuery -SQLiteConnection $nlaDBConnexion -Query $nlaQueryAddMAC -SqlParameters @{
                    MAC = (Clean-MacAddress -MacAddress $MacIP.LinkLayerAddress )
                    DATE  = $dateObservation
                }
                # trouvons notre ROWID maintenant, on risque d'en avoir de besoin
                $macRowID=(Invoke-sqliteQuery -SQLiteConnection $nlaDBConnexion -Query $nlaQueryCheckMAC -SqlParameters @{MAC=(Clean-MacAddress -MacAddress $MacIP.LinkLayerAddress )} -ErrorAction SilentlyContinue)[0].ROWID
                $noteMAC="`u{270F} $(Clean-MacAddress -MacAddress $MacIP.LinkLayerAddress -Separator ":" )"
            } else {
                $macRowID=$sqlresult[0].ROWID
                $noteMAC="`u{1F4D8} $(Clean-MacAddress -MacAddress $MacIP.LinkLayerAddress -Separator ":" )"
            } # gestion MAC
            
            $nlaQueryCheckIP="SELECT rowid FROM AddressIP
                WHERE AddressIP.address=@IP 
                AND AddressIP.segmentID=1 AND AddressIP.deleted=0;"
            # Est-ce que l'IP est déjà dans la base de donnée ?  Conserver rowid
            if (!( $sqlresult=(Invoke-sqliteQuery -SQLiteConnection $nlaDBConnexion -Query $nlaQueryCheckIP -SqlParameters @{ IP=ip2int($MacIP.IPAddress) } -ErrorAction SilentlyContinue) ) ) {
                # aucun resultat.  ajoutons l'adresse
                $nlaQueryAddIP="INSERT INTO AddressIP (segmentID, address, subnet, mask,  FirstSeen, deleted ) Values (1, @IP, @SUBNET, @MASK, @DATE, 0 )"
                Invoke-SqliteQuery -SQLiteConnection $nlaDBConnexion -Query $nlaQueryAddIP -SqlParameters @{
                    IP = [UINT32](ip2int($MacIP.IPAddress))
                    SUBNET =$nlaInterfaceDetail.subnet
                    MASK = $nlaInterfaceDetail.PrefixLength
                    DATE  = $dateObservation
                    }
                # trouvons notre ROWID maintenant, on risque d'en avoir de besoin
                $IPRowID=(Invoke-sqliteQuery -SQLiteConnection $nlaDBConnexion -Query $nlaQueryCheckIP -SqlParameters @{ IP=ip2int($MacIP.IPAddress) } -ErrorAction SilentlyContinue)[0].ROWID
                $noteIP="`u{270F} $($MacIP.IPAddress)"
            } else {
                $IPRowID=$sqlresult[0].ROWID
                $noteIP="`u{1F4D8} $($MacIP.IPAddress)"
            } #gestion IP 
            
            $nlaQueryLatestIP="SELECT AddressIP.Address,T_Is.ROWID as ROWID
                FROM AddressMAC
                JOIN T_Is ON AddressMAC.ROWID = T_Is.MacID
                JOIN AddressIP ON T_Is.IpID = AddressIP.ROWID
                WHERE T_Is.ROWID IN (SELECT ROWID FROM (SELECT  ROWID, MAX(Seen) FROM T_Is GROUP BY MACID )) 
                AND AddressMAC.address=@MAC"
            # Est-ce que l'association MAC/IP est la dernière connue ? 
            if (!( $sqlresult=(Invoke-sqliteQuery -SQLiteConnection $nlaDBConnexion -Query $nlaQueryLatestIP -SqlParameters @{ MAC=(Clean-MacAddress -MacAddress $MacIP.LinkLayerAddress ) } -ErrorAction SilentlyContinue) ) ) {
                # Aucun résultat, ajoutons l'association    
                                                
                $nlaQueryAddRelation="INSERT INTO T_Is (MACId, IPId, Seen ) Values ( @MACID, @IPID, @DATE )"
                Invoke-SqliteQuery -SQLiteConnection $nlaDBConnexion -Query $nlaQueryAddRelation -SqlParameters @{
                        MACID=$macRowID
                        IPID=$IPRowID
                        DATE=$dateObservation 
                }
                $noteIS="| ajout Association"
                
            } else {
                #Vérifier si la dernière association est contre cette adresse IP
                if ( ($sqlresult[0].Address) -eq (ip2Int($MacIP.IPAddress)) ) {
                    # oui, changer le champs Seen de l'association dans T_Is.  Utiliser le ROWID identifié plus haut
                    $nlaQueryUpdateRelation="UPDATE T_Is SET Seen=@DATE WHERE ROWID=@ROWID"
                    Invoke-SqliteQuery -SQLiteConnection $nlaDBConnexion -Query $nlaQueryUpdateRelation -SqlParameters @{
                        ROWID = $sqlresult[0].ROWID
                        DATE  = $dateObservation
                        }
                    $noteIS="| Association mise à jour"
                } else {
                    # Non, ajouter une entrée dans T_Is.  Utiliser le ROWID identifiés dans les deux premières requêtes
                    $nlaQueryAddRelation="INSERT INTO T_Is (MACId, IPId, Seen ) Values ( @MACID, @IPID, @DATE )"
                    Invoke-SqliteQuery -SQLiteConnection $nlaDBConnexion -Query $nlaQueryAddRelation -SqlParameters @{
                           MACID=$macRowID
                           IPID=$IPRowID
                           DATE=$dateObservation 
                    }
                    $noteIS="| ajout Association"
                }

            }


            #write-host $notice "[$dateObservation] $noteMAC $(Clean-MacAddress -MacAddress $MacIP.LinkLayerAddress -Separator ":" ) | $noteIP $($MacIP.IPAddress) | $noteIs"
            write-host "$noteMAC $noteIP $noteIS"
        }
    }
    #On attend un peu, sinon c'est trop rapide
    Start-Sleep -Seconds 5
} # boucle principale



    # tache 2, connexion icmp sur le subnet pour générer des requetes ARP

    #$nlaSubnet = 
    #$nlaPrefixLenght = (get-netipaddress -InterfaceAlias "Wi-Fi" -AddressFamily IPv4 | Select-Object PrefixLength)[0].PrefixLength


