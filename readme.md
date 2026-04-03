# Préparration de base


## Pré-requis :
* Avoir monté son RAID sur /mnt/raid

## Utilisation :

1. Copier le script et le rendre executable
```bash
chmod +x install.sh
```
3. Executer le script
```bash
./install.sh
```

## Architecture créé :

### Sur disque system
```text
/srv/
├── monitoring              → Stack observabilité (Prometheus, Grafana, Telegraf, )
│   ├── prometheus          → Collecte métriques
│   │   └── data            → Base de données TSDB
│   ├── grafana             → Dashboards et alertes
│   │   └── data            → Configs et dashboards persistants
│   └── telegraf            → Agent de collecte système
├── nextcloud               → Serveur de fichiers cloud
│   └── nextcloud-db        → BDD (metadonnes,users,groups,permissions,apps,logs)
├── traefik                 → Reverse proxy et Let's Encrypt
│   ├── acme                → Certificats SSL
│   ├── dynamic             → Configs dynamiques (labels Docker)
│   └── logs                → Logs d'accès et erreurs
└── urbackup                → Service de sauvegarde 
    └── db                  → Base SQLite des backups
```

### Sur disque RAID
```text
/mnt/raid/
├──nextcloud        → Données du cloud
└──urbackup         → Sauvegarde clients
```



