# 🚀 Préparation de base

## ✅ Pré-requis
- ✅ Avoir monté son **RAID sur `/mnt/raid`**

## 🚀 Utilisation

1. **Ajouter son utilisateur au sudoers**
```bash
su
nano /etc/sudoers
```

2. **Copier le script et le rendre exécutable**
```bash
chmod +x install.sh
```

3. **Exécuter le script**
```bash
./install.sh
```

4. **📊 Après exécution**
À la fin, le script génère **3 fichiers de rapport** dans `/tmp/docker-xxxxxx` :
   - 📄 **Rapport Markdown** : `docker-YYYY-MM-DD-HHMM-report.md`
   - 📄 **Rapport TXT** : `docker-YYYY-MM-DD-HHMM-report.txt`
   - 📋 **Log partiel** : `docker-YYYY-MM-DD-HHMM.log`

**⚠️ PENSEZ À BIEN SAUVEGARDER LES RAPPORTS ⚠️**  
*Ils contiennent les mots de passe générés lors de l'exécution !*

## 🏗️ Architecture créée pour les Dockers

### 💾 Sur disque système (`/srv/`)
```text
📁 /srv/
├── 🖥️ monitoring               → Stack monitoring (Prometheus,Grafana,Telegraf,Cadvisor,Node-exporter)
│   ├── 📊 prometheus          → Collecte métriques
│   │   ├── 💾 data            → Base de données
│   │   └── ⚙️ prometheus.yml  → Configuration Prometheus
│   ├── 📈 grafana             → Dashboards et alertes
│   │   └── 💾 data            → Configs et dashboards persistants
│   ├── 📡 telegraf            → Agent de collecte système
│   │   └── ⚙️ telegraf.conf   → Configuration Telegraf
│   └── 🐳 docker-compose.yml  → Docker compose "monitoring"
├── ☁️ nextcloud               → Serveur de fichiers cloud
│   ├── 🗄️ nextcloud-db       → BDD (métadonnées,users,groups,permissions,apps,logs)
│   ├── 🔄 nextcloud-redis     → Cache Redis
│   ├── ⚙️ .env               → Variables d'environnement Nextcloud
│   └── 🐳 docker-compose.yml  → Docker compose "nextcloud"
├── 🔄 traefik                 → Reverse proxy + Let's Encrypt
│   ├── 🔐 acme               → Certificats SSL
│   │   └── 🔒 acme.json      → /!\ Stockage certificats /!\
│   ├── ⚙️ dynamic            → Configs dynamiques (labels Docker)
│   ├── 📋 logs               → Logs d'accès/erreurs
│   ├── ⚙️ .env               → Variables d'environnement Traefik
│   ├── ⚙️ traefik.yml        → Configuration statique Traefik
│   └── 🐳 docker-compose.yml  → Docker compose "traefik"
└── 💾 urbackup                → Service de sauvegarde
    ├── 🗄️ db                 → Base SQLite backups
    ├── ⚙️ .env               → Variables d'environnement Urbackup
    └── 🐳 docker-compose.yml  → Docker compose "urbackup"
```


### 🗄️ Sur grappe RAID (`/mnt/raid/`)
```text
📁 /mnt/raid/
├── ☁️ nextcloud     → Données utilisateurs cloud
└── 💾 urbackup      → Sauvegardes clients
```

## 🌐 Ports utilisés

| Stack      | Service          | Port hôte | Port conteneur | 🔍 Usage principal                          |
|------------|------------------|-----------|----------------|---------------------------------------------|
| **Monitoring** | prometheus     | **9090**  | 9090           | UI Prometheus + `/metrics`                 |
| **Monitoring** | grafana        | **3000**  | 3000           | UI Grafana dashboards                      |
| **Monitoring** | cadvisor       | **8081**  | 8080           | UI + `/metrics` cAdvisor                   |
| **Monitoring** | node-exporter  | **9100**  | 9100 (host)    | `/metrics` Node Exporter                   |
| **Monitoring** | telegraf       | **9126**  | 9126 (host)    | Output Prometheus (Telegraf)               |
| **Nextcloud**  | nextcloud-app  | **8181**  | 80             | UI Nextcloud HTTP (backend Traefik)        |
| **Nextcloud**  | nextcloud-db   | —         | 3306           | MariaDB interne (non exposé)               |
| **Nextcloud**  | nextcloud-redis| —         | 6379           | Redis interne (non exposé)                 |
| **UrBackup**   | urbackup       | **55414** | 55414 (host)   | UI web UrBackup                            |
| **UrBackup**   | urbackup       | **55415** | 55415 (host)   | Service backup clients                     |
| **UrBackup**   | urbackup       | **35623** | 35623 UDP      | Découverte/status clients (UDP)            |
| **Traefik**    | traefik        | **80**    | 80             | Entrypoint **HTTP** web                    |
| **Traefik**    | traefik        | **443**   | 443            | Entrypoint **HTTPS** websecure             |
| **Traefik**    | traefik        | **8080**  | 8080           | Dashboard/API Traefik                      |

## 🛠️ Outils système installés

### 📦 Outils de base & Développement
| Outil | Description | Usage typique |
|-------|-------------|---------------|
| **curl** | Client HTTP/transfert fichiers | APIs, téléchargements |
| **wget** | Téléchargeur non-interactif | Scripts d'automatisation |
| **git** | Contrôle de version | Repo docker-compose |
| **make** | Automatisation de builds | Makefile, compilations |
| **jq** | Parseur/manipulateur JSON | Traitement APIs JSON |
| **moreutils** | Utilitaires avancés (`ts`, `sponge`) | Scripts shell avancés |

### 🐍 Python & Node.js
| Outil | Description | Usage typique |
|-------|-------------|---------------|
| **nodejs** | Runtime JavaScript | Scripts Node.js |
| **npm** | Gestionnaire paquets Node | Installation dépendances |
| **node-corepack** | Gestionnaire yarn/pnpm natif | `yarn`/`pnpm` sans install |
| **yarnpkg** | Gestionnaire paquets rapide | Alternative npm |
| **python3.13-venv** | Environnements virtuels Python | Isolation projets Python |
| **python3** | Python 3.x | Scripts Python |

### 📊 Monitoring & Performance
| Outil | Description | Usage typique |
|-------|-------------|---------------|
| **htop** | Moniteur système interactif | CPU/RAM/processus |
| **ncdu** | Analyseur d'espace disque | Gros fichiers/dossiers |
| **iotop** | Monitoring I/O disque | Processus gourmands |
| **lazydocker** | Interface TUI Docker | Gestion conteneurs |
| **cockpit** | Interface web d'administration | Monitoring/système GUI |

### 🌐 Réseau & Diagnostic
| Outil | Description | Usage typique |
|-------|-------------|---------------|
| **mtr** | Traceroute + ping | Diagnostic réseau |
| **nmap** | Scanner réseau/ports | Audit sécurité |

### 💾 Stockage & Partage
| Outil | Description | Usage typique |
|-------|-------------|---------------|
| **rsync** | Synchronisation fichiers | Backups incrémentiels |
| **nfs-kernel-server** | Serveur NFS | Partage Linux/Linux |
| **samba** | Serveur SMB/CIFS | Partage Windows/Linux |
| **samba-common-bin** | Binaires Samba communs | Support SMB |
| **cockpit-file-sharing** | Interface Cockpit partage | GUI Samba/NFS |
| **acl** | Listes de contrôle d'accès | Permissions fines |
| **attr** | Attributs étendus fichiers | xattr (Samba, backups) |

### 🗄️ Gestion RAID/Stockage
| Outil | Description | Usage typique |
|-------|-------------|---------------|
| **btrfs-progs** | Outils BTRFS | Snapshots, volumes |
| **mdadm** | Gestion RAID logiciel | Monitoring RAID |
| **smartmontools** | Monitoring SMART disques | Santé disques |
| **parted** | Partitionnement avancé | Gestion partitions |
| **gettext-base** | Substitution variables | Génération `.env` |
