# Préparration de base


## Pré-requis :
* Avoir monté son RAID sur /mnt/raid

## Utilisation :

1. Ajouter son utilisateur au sudoers
```bash
su
nano /etc/sudoers
```
2. Copier le script et le rendre executable
```bash
chmod +x install.sh
```
3. Executer le script
```bash
./install.sh
```
4. Après execution  
A la fin, le script génére 3 fichiers de rapport dans /tmp/docker-xxxxxx :
    - Un rapport en MarkDown et en TXT avec : hostname, IP local, IP public, services déployés, infos Traefik + Nextcloud et infos sur les emplacements utiles
    - Un log partiel (apt/git/rsync)  

/!\ Pensez à bien sauvegarder le rapport car il contiendra les mots de passes générés lors de l'éxécution du script /!\

## Architecture créé :

### Sur disque system :
```text
/srv/
├── monitoring              → Stack monitoring (Prometheus, Grafana, Telegraf, Cadvisor, Node-exporter)
│   ├── prometheus          → Collecte métriques
|   |   ├── data            → Base de données
│   │   └── prometheus.yml  → Configuration Prometheus
│   ├── grafana             → Dashboards et alertes
│   │   └── data            → Configs et dashboards persistants
│   ├── telegraf            → Agent de collecte système
|   │   └── telegraf.conf   → Configuration Telegraf
│   └── docker-compose.yml  → Docker compose de la stack "monitoring"
├── nextcloud               → Serveur de fichiers cloud
│   ├── nextcloud-db        → BDD (metadonnes,users,groups,permissions,apps,logs)
|   ├── nextcloud-redis     → Stockage redis
|   ├── .env                → Variable d'environement pour Nextcloud
|   └── docker-compose.yml  → Docker compose de "nextcloud"
├── traefik                 → Reverse proxy et Let's Encrypt
│   ├── acme                → Certificats SSL
|   |   └── acme.json       → /!\ Stockage des certificats /!\
│   ├── dynamic             → Configs dynamiques (labels Docker)
│   ├── logs                → Logs d'accès et erreurs
|   ├── .env                → Variable d'environement pour Traefik
|   ├── traefik.yml         → Configuration statique Traefik
|   └── docker-compose.yml  → Docker compose de "traefik"
└── urbackup                → Service de sauvegarde 
    ├── db                  → Base SQLite des backups
    ├── .env                → Variable d'environement pour Urbackup
    └── docker-compose.yml  → Docker compose de "urbackup"
```

### Sur disque RAID :
```text
/mnt/raid/
├── nextcloud        → Données du cloud
└── urbackup         → Sauvegardes clients
```



