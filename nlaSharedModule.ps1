


Import-Module PSSQLite

function initDB {
    <#
    .SYNOPSIS
    Initialisation base de donnée SQLite avec schéma initial 
    .DESCRIPTION
    Crée le fichier de base de donnée SQLite, configure les tables 
    initials et inscrit les données initiales de base pour requises 
    pour les différents modules de NetLog-Arp
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
        [String[]] $databasePath
        )
    
    $nlaDB = New-SqliteConnection -DataSource $databasePath
    $error.clear()
    $null=Invoke-SqliteQuery -Connection $nladb -Query "pragma schema_version;" -ErrorAction SilentlyContinue
    if ($error.Count) { 
        Write-Output "Erreur d'accès à la base de donnée"
        Return $false
    }

    #
    # Définition des requêtes de création des tables
    #

    $nlaCreateTable=@{}

    <# définition dbml
        Table Segment {
            rowid integer [primary key]
            name TEXT
            description TEXT
            GW_IP INT 
            GW_MAC TEXT(12)
            protected BOOL
            deleted BOOL
        }
    #>
    $nlaCreateTable["Segment"] = "
        CREATE TABLE Segment ( rowid, name TEXT, 
        description TEXT, GW_IP INT, GW_MAC TEXT,
        protected BOOLEAN, deleted BOOLEAN );
    "
    <# définition dbml
        Table AddressMAC {
            rowid interger [primary key]
            segmentID INT [ref: > Segment.rowid]
            address TEXT (16)
            vendorPrefix TEXT [ref: > vendorMAC.vendorPrefix]
            description TEXT
            FirstSeen datetime
            deleted BOOL
        }
    #>
    $nlaCreateTable["AddressMAC"] = "
        CREATE TABLE AddressMAC ( rowid, segmentID INTEGER, 
        address TEXT, vendorPrefix TEXT, description TEXT, 
        FirstSeen datetime, deleted BOOLEAN );
    "

    <# définition dbml
    Table CommentMAC {
        rowid interger [primary key]
        addressID integer [ref: > AddressMAC.rowid]
        comment TEXT
        date dattime
    }
    #>
    $nlaCreateTable["CommentMAC"] = "
        CREATE TABLE CommentMAC ( rowid,  
        addressID INTEGER, comment TEXT , date datetime );
    " 

    <# définition dbml
    Table Is {
        rowid integer [primary key]
        MACID integer [ref: > AddressMAC.rowid]
        IPID integer [ref: > AddressIP.rowid ]
        Seen datetime
    }                
    #>
    $nlaCreateTable["T_Is"] = "
        CREATE TABLE T_Is ( rowid, MacID INT, IpID INT, Seen datetime);
    "
    

    <# définition dbml
        Table AddressIP {
            rowid interger [primary key] 
            segmentID INT [ref: > Segment.rowid]
            address INT  
            subnet INT 
            mask INT 
            description TEXT
            firstSeen datetime
            deleted BOOL
        }
    #>
    $nlaCreateTable["AddressIP"] = "
        CREATE TABLE AddressIP ( rowid, segmentID INTEGER,
        address INTEGER, subnet INT, mask INT, description TEXT,
        FirstSeen datetime, deleted BOOLEAN );
    "

    <# définition dbml
        Table SeenIP {
            rowid integer [primary key]
            address integer [ref: > AddressIP.address]
            segment integer [ref: > AddressIP.segmentID]
            date datetime
        }        
    #>
    $nlaCreateTable["SeenIP"] = "
        CREATE TABLE SeenIP ( rowid, 
        address INTEGER, segment INT, date datetime );
    "

    <# définition dbml
    Table CommentIP {
        rowid integer [primary key]
        addressID integer [ref: > AddressIP.rowid]
        comment TEXT
        date datetime
    }        
    #>
    $nlaCreateTable["CommentIP"] = "
        CREATE TABLE CommentIP ( rowid,
        addressID INTEGER, comment TEXT,
        date datetime );
    "

    foreach ( $nlaTable in $nlaCreateTable.Keys ) {
        #check if table exist
        $nlaQuery="SELECT name FROM sqlite_master WHERE type='table' AND name='$nlaTable';"
        
        if ( -not ( Invoke-SqliteQuery -SQLiteConnection $nlaDB -Query $nlaQuery ) ) {
            # Création des tables
            Invoke-SqliteQuery -SQLiteConnection $nlaDB -Query $nlaCreateTable[$nlaTable] -ErrorAction SilentlyContinue
            if ($error.Count) {Write-Output "Erreur lors de la création de la table $nlaTable"}
        } 
                
    }
    
    $nlaQuery="Select count(*) as count from Segment"
    if  ( -not $(Invoke-SqliteQuery -SQLiteConnection $nlaDB -Query $nlaQuery -ErrorAction SilentlyContinue).count ) {
        $nlaInsertQuery='INSERT INTO Segment 
        (name, description, protected, deleted )
        VALUES ("DEFAUT","Segment par defaut", FALSE, FALSE)'
        Invoke-SqliteQuery -SQLiteConnection $nlaDB -Query $nlaInsertQuery -ErrorAction SilentlyContinue
    }

    $nlaDB.Close()
    Return $True
        
    }

    function FichierDeConfiguration {
        <#
        .SYNOPSIS
        Retourne les paramètres du fichier de configuraiton, le cré au besoin 
        .DESCRIPTION
        Permet de retourner les valeurs du fichier de configuration.
        Retourn $null si le fichier de configuration n'est pas un json conforme
        Valide, propose des valeurs par défaut ou des valeurs null.
        Il est possible que les données manquantes aient étés fournis par la ligne de commande
        .PARAMETER configFilePath
        Chemin d'accès et nom du fichier de configuration
        .TODO
        tbd
        #>
    
        param(
            [Parameter(Mandatory=$false)][String[]] $configFilePath
        )

        # Initialisation de $nlaConfig
        $nlaConfig = "" | select-object sqlitePath,interface
        # Si la variable $configFulePath est vide, pointer sur le dossier courant du script
        if ( -not $configFilePath ) { $configFilePath = $PSScriptRoot+"\nla.json" }

        #Tentative de lecture du fichier de configuration
        try {              
            $nlaTempConfig = Get-Content -Raw -Path $configFilePath -ErrorAction Stop | 
                ConvertFrom-Json |
                Select-Object sqlitePath,interface
            $nlaConfig.sqlitePath = (&{If($nlaTempConfig.sqlitePath) {$nlaTempConfig.sqlitePath} Else {$null}})
            $nlaConfig.interface = (&{If($nlaTempConfig.interface) {$nlaTempConfig.interface} Else {$null}})
        }
        catch [System.ArgumentException] 
            { #Fichier JSON mal-formé
              Return $null  }
        catch [System.Management.Automation.ItemNotFoundException]
            { #Fichier de configuration n'existe pas
              Return $null  }
        catch {  
            # Ne devrait pas arriver, croisons nous les doigts
            write-output $Error[-1].exception.GetType().fullname 
        }
        
        # validation des paramètres de configuration
        # Vérifier si le chemin d'accès au fichier de base de donnée est valide
        
        if (!( $nlaConfig.sqlitePath )) {
            # sqlitePath n'est pas défini, utilisons la valeur par défaut
            $nlaConfig.sqlitePath=$PSScriptRoot+"\nladb.db"
        }

        if ( $nlaConfig.sqlitePath -eq (split-path -Path $nlaConfig.sqlitePath -Leaf) ) { 
            # Fichier de donné n'est pas un chemin complet, utilisons le dossier du script.
            $nlaConfig.sqlitePath=$PSScriptRoot+"\"+$nlaConfig.sqlitePath         
        }
        
        $interfaceValide = Get-NetAdapter -InterfaceAlias $nlaConfig.interface -ErrorAction SilentlyContinue
        if ( !$interfaceValide ) {
            # Interface n'est pas valide
            Write-Host "L'interface défini dans le fichier de configuration n'est pas valide :  $($nlaConfig.interface)"
            $nlaConfig.interface = $null
        }

        Return [pscustomobject]$nlaConfig
    }

# Appel à retirer,  
#initDB(".\experiment\test.db")
#FichierDeConfiguration("nladb.delete")

function Ip2Int {
    <#
    .SYNOPSIS
    Convertie une adresse IP en entier sans inverser les octets comme ce satané powershell fait nativement 
    .DESCRIPTION
    Convertie une adresse IP en entier dans un ordre qui permet de faire
    des opérations mathématique.
    .PARAMETER IPv4
    Chaine de caractère représentant une adresse IP
    .OUTPUTS
    [INT] Entier représentant l'adresse IP
    Retourn $null si l'adresse IP n'est pas valide
    .TODO 
    tbd
    #>

    param(
        [String[]] $IPString
    )

    #Vérifier si l'adresse IP est valide
    try {
        $IPv4 = [IPAddress]::Parse($IPString)
    }
    catch {
        Return $null
    }

    [array]$IPString=$IPv4.GetAddressBytes()
    [array]::reverse($IPString)
    [uint32]$IPInt = ([IPAddress]($IPString -join '.')).Address
    return $IPInt
}

function Int2Ip {
    <#
    .SYNOPSIS
    Convertie un nombre entier en adresse IP en entier sans inverser les octets comme 
    ce satané powershell fait nativement 
    .DESCRIPTION
    Convertie un nombre entier représentant une adresse IP en chaine de caractère
    .PARAMETER IPInt
    Nombre entier représentant une adresse IP
    .OUTPUTS
    Chaine représentant l'adresse IP
    Retourn $null si l'adresse IP n'est pas valide
    .TODO 
    tbd
    #>

    param(
        [UInt32[]] $IPInt
    )

    #Vérifier si l'adresse IP est valide
    #4294967295 représente 255.255.255.255
    if ($IPInt -gt 4294967295 -or $IPInt -lt 0) { Return $null }
    #Si j'utilise Parse, il inverse les octets comme un grand   
    Return ([String]([IPAddress]::Parse($IPInt)).IPAddressToString)
}

function IPRangeMinMax {
    <#
    .SYNOPSIS
    Retournes les valeurs min et max d'une plage d'adresse IP
    .DESCRIPTION
    
    .PARAMETER subnet
    Adresse IP contenu dans le sous-réseau.
    .PARAMETER mask
    Nombre de bit représentant le mask de sous-réseau
    .OUTPUTS
    Tableau contenant les valeurs min et max de la plage d'adresse IP
    .TODO 
    tbd
    #>

    param(
        [String[]] $subnet,
        [UInt32] $mask
    )

    if ($mask -gt 30) { return $null}
    $bitmask = [CONVERT]::ToUInt32(("1" * $mask + "0" * (32-$mask)),2)

    #Vérifier si l'adresse IP est valide
    try {
        $IPv4 = [IPAddress]::Parse($subnet)
    }
    catch {
        Return $null
    }

    $IPMin = ( (Ip2Int($IPv4)) -band $bitmask ) + 1
    $IPMax = ( $IPMin  + [Math]::Pow(2,(32-$mask)) -1 ) -2 

    return [pscustomobject]@{IPMin=([ipaddress]::Parse($IPmin) );IPMax=([ipaddress]::Parse($IPmax) )}

}
    
IPRangeMinMax -Subnet 192.168.0.0 -mask 8