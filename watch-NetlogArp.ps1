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