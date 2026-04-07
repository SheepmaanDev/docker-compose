#!/bin/bash
set -euo pipefail

# =========================
# Couleurs
# =========================
NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'

# =========================
# Variables globales
# =========================
LOCAL_IP=""
PUBLIC_IP=""
HOST_NAME=""

REPO_URL="https://github.com/SheepmaanDev/docker-compose.git"
REPO_BRANCH="main"
REPO_TMP_DIR="/tmp/docker-configs"

declare -a DIR_DOCKER=(monitoring urbackup traefik nextcloud)
declare -a SELECTED_DIRS=()

# Rapports (dans /tmp pour éviter les soucis de droits)
BASE_REPORT="/tmp/docker-bootstrap-$(date +%F-%H%M%S)"
LOG_FILE="${BASE_REPORT}.log"
REPORT_TXT="${BASE_REPORT}-report.txt"
REPORT_MD="${BASE_REPORT}-report.md"

# Rapport mémoire
declare -a REPORT_SERVICES=()
REPORT_TRAEFIK_DOMAIN=""
REPORT_NEXTCLOUD_DOMAIN=""
REPORT_NEXTCLOUD_ADMIN_USER=""
REPORT_NEXTCLOUD_ADMIN_PASSWORD=""
REPORT_NEXTCLOUD_DB_ROOT_PASSWORD=""
REPORT_NEXTCLOUD_DB_PASSWORD=""

# =========================
# Helpers UI
# =========================
info()   { echo -e "${CYAN}[INFO]${NC} $1"; }
success(){ echo -e "${GREEN}[OK]${NC}   $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERR]${NC}  $1"; }

step() {
    echo ""
    echo -e "${BOLD}${BLUE}==> $1${NC}"
}

mask() {
    echo "$1" | sed 's/./*/g'
}

# =========================
# Fonctions core
# =========================
update_sys() {
    step "Mise à jour du système"
    sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get dist-upgrade -y | tee -a "$LOG_FILE"
    success "Système à jour"
}

install_tools() {
    step "Installation des outils"
    sudo apt-get install -y curl wget ncdu htop iotop mtr nmap rsync btrfs-progs git mdadm smartmontools parted gettext-base | tee -a "$LOG_FILE"
    success "Outils installés"
}

check_raid() {
    local answer

    clear
    step "Vérification du RAID /mnt/raid"
    read -r -p "As-tu déjà créé ton RAID sur /mnt/raid ? (oui/non) : " answer

    case "${answer,,}" in
        oui|o|yes|y)
            success "RAID OK, on continue..."
            ;;
        non|n|no)
            error "RAID non créé, crée-le et relance le script."
            warn  "Le point de montage doit être /mnt/raid."
            exit 1
            ;;
        *)
            error "Réponse invalide. Merci de répondre par oui ou non."
            exit 1
            ;;
    esac
}

install_docker() {
    step "Installation de Docker"

    sudo apt-get install -y ca-certificates curl gnupg lsb-release | tee -a "$LOG_FILE"

    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    local CODENAME
    CODENAME=$(awk -F= '/^VERSION_CODENAME/{print $2}' /etc/os-release)

    printf "deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian %s stable\n" \
        "$(dpkg --print-architecture)" "$CODENAME" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update | tee -a "$LOG_FILE"
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin | tee -a "$LOG_FILE"

    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"

    success "Docker installé et démarré"
    warn "Relance ta session plus tard pour utiliser docker sans sudo."
}

create_dir() {
    step "Sélection des services à déployer"

    echo -e "${CYAN}Dossiers / services disponibles :${NC}"
    local i=1
    for d in "${DIR_DOCKER[@]}"; do
        echo "  $i) $d"
        ((i++))
    done

    read -r -p "Entrez les numéros (ex: 1 3 4) séparés par espaces: " -a choix

    echo -e "${CYAN}Services sélectionnés :${NC}"
    for num in "${choix[@]}"; do
        if [[ $num =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#DIR_DOCKER[@]}" ]; then
            local dossier="${DIR_DOCKER[$((num-1))]}"
            echo -e "${GREEN}  -> $dossier${NC}"
            sudo mkdir -p "/srv/$dossier"
            sudo chown "$USER:$USER" "/srv/$dossier"
            SELECTED_DIRS+=("$dossier")
            create_subdirs_for_service "$dossier"
        else
            warn "Numéro invalide : $num"
        fi
    done
}

create_subdirs_for_service() {
    local service="$1"

    case "$service" in
        monitoring)
            sudo mkdir -p /srv/monitoring/prometheus/data
            sudo mkdir -p /srv/monitoring/grafana/data
            sudo mkdir -p /srv/monitoring/telegraf
            sudo chown -R "$USER:$USER" /srv/monitoring
            ;;
        nextcloud)
            sudo mkdir -p /srv/nextcloud/nextcloud-db
            sudo mkdir -p /mnt/raid/nextcloud
            sudo chown -R "$USER:$USER" /srv/nextcloud /mnt/raid/nextcloud
            ;;
        traefik)
            sudo mkdir -p /srv/traefik/acme
            sudo mkdir -p /srv/traefik/dynamic
            sudo mkdir -p /srv/traefik/logs
            sudo chown -R "$USER:$USER" /srv/traefik
            ;;
        urbackup)
            sudo mkdir -p /srv/urbackup/db
            sudo mkdir -p /mnt/raid/urbackup
            sudo chown -R "$USER:$USER" /srv/urbackup /mnt/raid/urbackup
            ;;
    esac
}

clone_repo() {
    step "Synchronisation du dépôt docker-compose"

    if [ -d "$REPO_TMP_DIR/.git" ]; then
        info "Mise à jour du repo Git..."
        git -C "$REPO_TMP_DIR" fetch --all --prune   | tee -a "$LOG_FILE"
        git -C "$REPO_TMP_DIR" checkout "$REPO_BRANCH" | tee -a "$LOG_FILE"
        git -C "$REPO_TMP_DIR" pull --ff-only origin "$REPO_BRANCH" | tee -a "$LOG_FILE"
    else
        info "Clonage du repo Git..."
        rm -rf "$REPO_TMP_DIR"
        git clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_TMP_DIR" | tee -a "$LOG_FILE"
    fi

    success "Repo synchronisé : $REPO_TMP_DIR"
}

copy_service_files() {
    local service="$1"
    local src_dir="$REPO_TMP_DIR/$service"
    local dst_dir="/srv/$service"

    if [ ! -d "$src_dir" ]; then
        warn "Aucun dossier trouvé dans le repo pour $service"
        return
    fi

    info "Copie des fichiers pour $service"
    rsync -av \
        --delete \
        --exclude ".git" \
        --exclude ".env" \
        --exclude "prometheus/" \
        --exclude "grafana/" \
        --exclude "telegraf/" \
        --exclude "logs/" \
        --exclude "dynamic/" \
        --exclude "acme/" \
        --exclude "acme.json" \
        --exclude "nextcloud-db" \
        --exclude "urbackup/db" \
        --exclude "db/" \
        --exclude "/mnt/raid/nextcloud" \
        --exclude "/mnt/raid/urbackup" \
        "$src_dir/" "$dst_dir/" | tee -a "$LOG_FILE"
}

generate_monitoring_files() {
    local srv_path="/srv/monitoring"

    cat > "$srv_path/.env" <<EOF
LOCAL_IP=${LOCAL_IP}
PUBLIC_IP=${PUBLIC_IP}
HOST_NAME=${HOST_NAME}
EOF

    success "[monitoring] .env généré"

    if [ -f "$srv_path/prometheus.yml.template" ]; then
        export LOCAL_IP PUBLIC_IP HOST_NAME
        envsubst < "$srv_path/prometheus.yml.template" > "$srv_path/prometheus/prometheus.yml"
        success "[monitoring] prometheus.yml généré"
    else
        warn "[monitoring] prometheus.yml.template absent, génération ignorée"
    fi

    if [ -f "$srv_path/telegraf.conf.template" ]; then
        export LOCAL_IP PUBLIC_IP HOST_NAME
        envsubst < "$srv_path/telegraf.conf.template" > "$srv_path/telegraf/telegraf.conf"
        success "[monitoring] telegraf.conf généré"
    else
        warn "[monitoring] telegraf.conf.template absent, génération ignorée"
    fi
}

generate_traefik_files() {
    local srv_path="/srv/traefik"
    local domain=""

    sudo docker network inspect traefik >/dev/null 2>&1 || sudo docker network create traefik >/dev/null
    success "[traefik] réseau Docker 'traefik' prêt"

    if [ ! -f "$srv_path/.env" ]; then
        read -r -p "Domaine principal Traefik (ex: scsinformatique.com): " domain
    else
        domain=$(grep '^DOMAIN=' "$srv_path/.env" | cut -d= -f2- || echo "")
        if [ -z "$domain" ]; then
            read -r -p "Domaine principal Traefik (ex: scsinformatique.com): " domain
        fi
    fi

    cat > "$srv_path/.env" <<EOF
DOMAIN=${domain}
LOCAL_IP=${LOCAL_IP}
PUBLIC_IP=${PUBLIC_IP}
HOST_NAME=${HOST_NAME}
EOF

    REPORT_TRAEFIK_DOMAIN="$domain"

    success "[traefik] .env généré (${domain})"

    export DOMAIN="$domain" LOCAL_IP PUBLIC_IP HOST_NAME
    if [ -f "$srv_path/traefik.yml.template" ]; then
        envsubst < "$srv_path/traefik.yml.template" > "$srv_path/traefik.yml"
        success "[traefik] traefik.yml généré"
    else
        warn "[traefik] traefik.yml.template absent, génération ignorée"
    fi

    echo "{}" | sudo tee /srv/traefik/acme/acme.json >/dev/null
    sudo chmod 600 /srv/traefik/acme/acme.json
    success "[traefik] acme.json créé/mis à jour"
}

generate_nextcloud_files() {
    local srv_path="/srv/nextcloud"
    local mysql_root_password mysql_password nextcloud_admin_user nextcloud_admin_password
    local nextcloud_domain sous_reseau

    if [ ! -f "$srv_path/.env" ]; then
        read -r -p "Domaine Nextcloud (ex: cloud.scsinformatique.com): " nextcloud_domain
    else
        nextcloud_domain=$(grep '^NEXTCLOUD_DOMAIN=' "$srv_path/.env" | cut -d= -f2- || echo "")
        if [ -z "$nextcloud_domain" ]; then
            read -r -p "Domaine Nextcloud (ex: cloud.scsinformatique.com): " nextcloud_domain
        fi
    fi

    read -r -p "Sous-réseau Docker (ex: 192.168.1.0 sans le /16): " sous_reseau
    sous_reseau="${sous_reseau:-192.168.1.0}"

    mysql_root_password="${MYSQL_ROOT_PASSWORD:-$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)}"
    mysql_password="${MYSQL_PASSWORD:-$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)}"

    nextcloud_admin_user="${NEXTCLOUD_ADMIN_USER:-scsinfo}"
    nextcloud_admin_password="${NEXTCLOUD_ADMIN_PASSWORD:-$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)}"

    cat > "$srv_path/.env" <<EOF
# Nextcloud - Variables Docker Compose
MYSQL_ROOT_PASSWORD=${mysql_root_password}
MYSQL_PASSWORD=${mysql_password}
NEXTCLOUD_ADMIN_USER=${nextcloud_admin_user}
NEXTCLOUD_ADMIN_PASSWORD=${nextcloud_admin_password}
NEXTCLOUD_DOMAIN=${nextcloud_domain}
SOUS_RESEAU=${sous_reseau}

# Automatiques
LOCAL_IP=${LOCAL_IP}
PUBLIC_IP=${PUBLIC_IP}
HOST_NAME=${HOST_NAME}
EOF

    REPORT_NEXTCLOUD_DOMAIN="$nextcloud_domain"
    REPORT_NEXTCLOUD_ADMIN_USER="$nextcloud_admin_user"
    REPORT_NEXTCLOUD_ADMIN_PASSWORD="$nextcloud_admin_password"
    REPORT_NEXTCLOUD_DB_ROOT_PASSWORD="$mysql_root_password"
    REPORT_NEXTCLOUD_DB_PASSWORD="$mysql_password"

    success "[nextcloud] .env généré"
    info    "[nextcloud] Domaine : ${nextcloud_domain}"
    info    "[nextcloud] Sous-réseau : ${sous_reseau}"
    echo -e "${MAGENTA}[NEXTCLOUD] Admin :${NC} ${nextcloud_admin_user}"
    echo -e "${MAGENTA}[NEXTCLOUD] Mot de passe admin (masqué) :${NC} $(mask "$nextcloud_admin_password")"
    echo -e "${MAGENTA}[NEXTCLOUD] Mot de passe MariaDB root (masqué) :${NC} $(mask "$mysql_root_password")"
    echo -e "${MAGENTA}[NEXTCLOUD] Mot de passe MariaDB nextcloud (masqué) :${NC} $(mask "$mysql_password")"
    warn "Les mots de passe complets sont dans les rapports : ${REPORT_TXT} / ${REPORT_MD}"
}

generate_urbackup_files() {
    local srv_path="/srv/urbackup"

    if [ ! -f "$srv_path/.env" ]; then
        cat > "$srv_path/.env" <<EOF
LOCAL_IP=${LOCAL_IP}
PUBLIC_IP=${PUBLIC_IP}
HOST_NAME=${HOST_NAME}
EOF
        success "[urbackup] .env généré"
    fi
}

prepare_service() {
    local service="$1"

    case "$service" in
        monitoring) generate_monitoring_files ;;
        traefik)    generate_traefik_files ;;
        nextcloud)  generate_nextcloud_files ;;
        urbackup)   generate_urbackup_files ;;
        *)          warn "Aucun traitement spécifique pour $service" ;;
    esac
}

deploy_service() {
    local service="$1"
    local srv_path="/srv/$service"

    echo ""
    echo -e "${BOLD}${BLUE}Déploiement de $service...${NC}"

    copy_service_files "$service"
    prepare_service "$service"

    if [ -f "$srv_path/docker-compose.yml" ]; then
        sudo docker compose -f "$srv_path/docker-compose.yml" up -d
        success "$service démarré"
        REPORT_SERVICES+=("$service")
    elif [ -f "$srv_path/compose.yml" ]; then
        sudo docker compose -f "$srv_path/compose.yml" up -d
        success "$service démarré"
        REPORT_SERVICES+=("$service")
    else
        error "Aucun fichier docker-compose.yml trouvé pour $service"
    fi
}

deploy_selected_services() {
    step "Déploiement des services sélectionnés"

    for service in "${SELECTED_DIRS[@]}"; do
        deploy_service "$service"
    done
}

print_report_files() {
    # TXT
    cat > "$REPORT_TXT" <<EOF
========= RAPPORT D'INSTALLATION =========

Date : $(date)
Hostname : $HOST_NAME
IP locale : $LOCAL_IP
IP publique : $PUBLIC_IP

Services déployés :
$(for s in "${REPORT_SERVICES[@]}"; do echo "- $s"; done)

Traefik :
- Domaine principal : ${REPORT_TRAEFIK_DOMAIN:-N/A}

Nextcloud :
- Domaine : ${REPORT_NEXTCLOUD_DOMAIN:-N/A}
- Admin : ${REPORT_NEXTCLOUD_ADMIN_USER:-N/A}
- Mot de passe admin Nextcloud : ${REPORT_NEXTCLOUD_ADMIN_PASSWORD:-N/A}
- Mot de passe MariaDB root : ${REPORT_NEXTCLOUD_DB_ROOT_PASSWORD:-N/A}
- Mot de passe MariaDB nextcloud : ${REPORT_NEXTCLOUD_DB_PASSWORD:-N/A}

Emplacements utiles :
- Repo temporaire : $REPO_TMP_DIR
- Monitoring : /srv/monitoring
- Traefik : /srv/traefik
- Nextcloud : /srv/nextcloud
- UrBackup : /srv/urbackup
EOF

    # Markdown
    cat > "$REPORT_MD" <<EOF
# Rapport d'installation Docker

- **Date** : $(date)
- **Hostname** : \`$HOST_NAME\`
- **IP locale** : \`$LOCAL_IP\`
- **IP publique** : \`$PUBLIC_IP\`

## Services déployés

$(for s in "${REPORT_SERVICES[@]}"; do echo "- \`$s\`"; done)

## Traefik

- Domaine principal : \`${REPORT_TRAEFIK_DOMAIN:-N/A}\`

## Nextcloud

- Domaine : \`${REPORT_NEXTCLOUD_DOMAIN:-N/A}\`
- Admin : \`${REPORT_NEXTCLOUD_ADMIN_USER:-N/A}\`
- Mot de passe admin Nextcloud : \`${REPORT_NEXTCLOUD_ADMIN_PASSWORD:-N/A}\`
- Mot de passe MariaDB root : \`${REPORT_NEXTCLOUD_DB_ROOT_PASSWORD:-N/A}\`
- Mot de passe MariaDB nextcloud : \`${REPORT_NEXTCLOUD_DB_PASSWORD:-N/A}\`

## Emplacements utiles

- Repo temporaire : \`$REPO_TMP_DIR\`
- Monitoring : \`/srv/monitoring\`
- Traefik : \`/srv/traefik\`
- Nextcloud : \`/srv/nextcloud\`
- UrBackup : \`/srv/urbackup\`
EOF
}

print_report_console() {
    step "Résumé"

    echo -e "${CYAN}Services déployés :${NC}"
    if [ "${#REPORT_SERVICES[@]}" -gt 0 ]; then
        for s in "${REPORT_SERVICES[@]}"; do
            echo "  - $s"
        done
    else
        echo "  - Aucun"
    fi
    echo ""

    if [ -n "$REPORT_TRAEFIK_DOMAIN" ]; then
        echo -e "${CYAN}Traefik :${NC}"
        echo "  - Domaine principal : $REPORT_TRAEFIK_DOMAIN"
        echo ""
    fi

    if [ -n "$REPORT_NEXTCLOUD_DOMAIN" ]; then
        echo -e "${CYAN}Nextcloud :${NC}"
        echo "  - Domaine : $REPORT_NEXTCLOUD_DOMAIN"
        echo "  - Admin : $REPORT_NEXTCLOUD_ADMIN_USER"
        echo "  - Mot de passe admin (masqué) : $(mask "$REPORT_NEXTCLOUD_ADMIN_PASSWORD")"
        echo "  - Mot de passe MariaDB root (masqué) : $(mask "$REPORT_NEXTCLOUD_DB_ROOT_PASSWORD")"
        echo "  - Mot de passe MariaDB nextcloud (masqué) : $(mask "$REPORT_NEXTCLOUD_DB_PASSWORD")"
        echo ""
    fi

    echo -e "${CYAN}Infos machine :${NC}"
    echo "  - Hostname : $HOST_NAME"
    echo "  - IP locale : $LOCAL_IP"
    echo "  - IP publique : $PUBLIC_IP"
    echo ""

    echo -e "${YELLOW}Rapport TXT :${NC} $REPORT_TXT"
    echo -e "${YELLOW}Rapport Markdown :${NC} $REPORT_MD"
    echo -e "${YELLOW}Log partiel (apt/git/rsync) :${NC} $LOG_FILE"
    warn "Sauvegarde les rapports dans ton gestionnaire de mots de passe / backup."
}

main() {
    update_sys
    install_tools
    check_raid
    install_docker

    LOCAL_IP=$(hostname -I | awk '{print $1}')
    PUBLIC_IP=$(curl -s https://api.ipify.org)
    HOST_NAME=$(hostname)

    clear
    create_dir
    clone_repo
    deploy_selected_services

    print_report_files
    print_report_console

    echo ""
    echo -e "${GREEN}✅ Tous les services sélectionnés ont été traités.${NC}"
}

main "$@"