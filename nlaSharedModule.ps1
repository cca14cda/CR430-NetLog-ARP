Import-Module PSSQLite

function initDB {
    param(
        [String[]] $databasePath
        )
    
    # TODO: validation du chemin $databasePath
    # Si le fichier n'existe pas et il est possible d'écrire dans le 
    # dossier, continuer.  SQLite créer le fichier s'il n'existe pas à la première connexion

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
        addressID INTEGER, comment TEXT INT, date datetime );
    " 

    <# définition dbml
        Table SeenMAC {
            rowid integer [primary key]
            address integer [ref: > AddressMAC.address]
            segmentID integer [ref: > AddressMAC.segmentID]
            date datetime
        }        
    #>
    $nlaCreateTable["SeenMAC"] = "
        CREATE TABLE SeenMAC ( rowid,  
        address INTEGER, segmentID INT, date datetime );
    " 
    <# définition dbml
        Table vendorMAC {
            rowid inteter [primary key]
            vendorPrefix TEXT
            vendorName TEXT
            private integer
            lastupdate datetime
        }        
    #>
    $nlaCreateTable["vendorMAC"] = "
        CREATE TABLE vendorMAC ( rowid, 
        vendorPrefix TEXT, vendorName TEXT, private BOOLEAN, lastupdate DATETIME );
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


initDB(".\experiment\test.db")