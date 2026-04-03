#!/bin/bash
set -euo pipefail  # Arrêt sur erreur, undefined vars, pipefail

# =========================
# Création des variables
# =========================
LOCAL_IP=""
PUBLIC_IP=""
HOST_NAME=""

REPO_URL="https://github.com/SheepmaanDev/docker-compose.git"
REPO_BRANCH="main"
REPO_TMP_DIR="/tmp/docker-configs"

declare -a DIR_DOCKER=(monitoring urbackup traefik nextcloud)
declare -a SELECTED_DIRS=()  # ← tableau des choix validés

# =========================
# Création des fonctions
# =========================
update_sys () {
    sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get dist-upgrade -y
}

install_tools () {
    sudo apt-get install -y curl wget ncdu htop iotop mtr nmap rsync btrfs-progs git mdadm smartmontools parted gettext-base
}

check_raid() {
    local answer

    clear
    read -r -p "As-tu déjà créé ton RAID sur /mnt/raid ? (oui/non) : " answer

    case "${answer,,}" in
        oui|o|yes|y)
            echo "OK, on continue..."
            ;;
        non|n|no)
            echo "RAID non créé, crée-le et relance le script."
            echo "Attention au point de montage, il doit être /mnt/raid."
            exit 1
            ;;
        *)
            echo "Réponse invalide. Merci de répondre par oui ou non."
            exit 1
            ;;
    esac
}

install_docker () {
    # Dépendances
    sudo apt-get install -y ca-certificates curl gnupg lsb-release

    # Clé GPG
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Récup VERSION_CODENAME explicitement
    CODENAME=$(awk -F= '/^VERSION_CODENAME/{print $2}' /etc/os-release)

    # Repo avec printf
    printf "deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian %s stable\n" \
        "$(dpkg --print-architecture)" "$CODENAME" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Services et groupe
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    echo "Relancez votre session pour utiliser docker sans sudo."
}

create_dir() {
    echo "Dossiers disponibles :"
    select_num=1
    for d in "${DIR_DOCKER[@]}"; do
        echo "$select_num) $d"
        ((select_num++))
    done

    read -r -p "Entrez les numéros (ex: 1 3 4) séparés par espaces: " -a choix

    echo "Choix: "
    for num in "${choix[@]}"; do
        if [[ $num =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#DIR_DOCKER[@]}" ]; then
            dossier="${DIR_DOCKER[$((num-1))]}"
            echo "  -> $dossier"
            sudo mkdir -p "/srv/$dossier"
            sudo chown "$USER:$USER" "/srv/$dossier"
            SELECTED_DIRS+=("$dossier")

            create_subdirs_for_service "$dossier"
        else
            echo "  -> Numéro invalide: $num"
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
            echo "{}" | sudo tee /srv/traefik/acme/acme.json >/dev/null
            sudo chmod 600 /srv/traefik/acme/acme.json
            ;;

        urbackup)
            sudo mkdir -p /srv/urbackup/db
            sudo mkdir -p /mnt/raid/urbackup
            sudo chown -R "$USER:$USER" /srv/urbackup /mnt/raid/urbackup
            ;;
    esac
}

clone_repo() {
    if [ -d "$REPO_TMP_DIR/.git" ]; then
        echo "Mise à jour du repo Git..."
        git -C "$REPO_TMP_DIR" fetch --all --prune
        git -C "$REPO_TMP_DIR" checkout "$REPO_BRANCH"
        git -C "$REPO_TMP_DIR" pull --ff-only origin "$REPO_BRANCH"
    else
        echo "Clonage du repo Git..."
        rm -rf "$REPO_TMP_DIR"
        git clone -b "$REPO_BRANCH" "$REPO_URL" "$REPO_TMP_DIR"
    fi
}

copy_service_files() {
    local service="$1"
    local src_dir="$REPO_TMP_DIR/$service"
    local dst_dir="/srv/$service"

    if [ ! -d "$src_dir" ]; then
        echo "  -> Aucun dossier trouvé dans le repo pour $service"
        return
    fi

    echo "  -> Copie des fichiers pour $service"
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
        "$src_dir/" "$dst_dir/"
}

generate_monitoring_files() {
    local srv_path="/srv/monitoring"

    cat > "$srv_path/.env" <<EOF
LOCAL_IP=${LOCAL_IP}
PUBLIC_IP=${PUBLIC_IP}
HOST_NAME=${HOST_NAME}
EOF

    echo "  -> .env généré pour monitoring"

    if [ -f "$srv_path/prometheus.yml.template" ]; then
        export LOCAL_IP PUBLIC_IP HOST_NAME
        envsubst < "$srv_path/prometheus.yml.template" > "$srv_path/prometheus/prometheus.yml"
        echo "  -> prometheus.yml généré"
    else
        echo "  -> prometheus.yml.template absent, génération ignorée"
    fi

    if [ -f "$srv_path/telegraf.conf.template" ]; then
        export LOCAL_IP PUBLIC_IP HOST_NAME
        envsubst < "$srv_path/telegraf.conf.template" > "$srv_path/telegraf/telegraf.conf"
        echo "  -> telegraf.conf généré"
    else
        echo "  -> telegraf.conf.template absent, génération ignorée"
    fi
}

generate_traefik_files() {
    local srv_path="/srv/traefik"
    local domain

    # Création network traefik 
    sudo docker network create traefik
    # Demande le domaine si pas déjà configuré
    if [ ! -f "$srv_path/.env" ]; then
        read -r -p "Domaine principal Traefik (ex: scsinformatique.com): " DOMAIN
    else
        DOMAIN=$(grep '^DOMAIN=' "$srv_path/.env" | cut -d= -f2- || echo "")
        if [ -z "$DOMAIN" ]; then
            read -r -p "Domaine principal Traefik (ex: scsinformatique.com): " DOMAIN
        fi
    fi

    # Génération .env avec toutes les infos
    cat > "$srv_path/.env" <<EOF
DOMAIN=${DOMAIN}
LOCAL_IP=${LOCAL_IP}
PUBLIC_IP=${PUBLIC_IP}
HOST_NAME=${HOST_NAME}
EOF

    echo "  -> .env généré pour traefik (${DOMAIN})"

    # Génération traefik.yml depuis template
    export DOMAIN LOCAL_IP PUBLIC_IP HOST_NAME
    if [ -f "$srv_path/traefik.yml.template" ]; then
        envsubst < "$srv_path/traefik.yml.template" > "$srv_path/traefik.yml"
        echo "  -> traefik.yml généré"
    else
        echo "  -> traefik.yml.template absent, génération ignorée"
    fi

    # acme.json toujours créé/validé
    touch "$srv_path/acme.json"
    chmod 600 "$srv_path/acme.json"
    echo "  -> acme.json créé/mis à jour"
}

generate_nextcloud_files() {
    local srv_path="/srv/nextcloud"

    # Variables automatiques
    local mysql_root_password mysql_password nextcloud_admin_user nextcloud_admin_password
    local nextcloud_domain sous_reseau

    # Domaine Nextcloud
    if [ ! -f "$srv_path/.env" ]; then
        read -r -p "Domaine Nextcloud (ex: cloud.scsinformatique.com): " nextcloud_domain
    else
        nextcloud_domain=$(grep '^NEXTCLOUD_DOMAIN=' "$srv_path/.env" | cut -d= -f2- || echo "")
        if [ -z "$nextcloud_domain" ]; then
            read -r -p "Domaine Nextcloud (ex: cloud.scsinformatique.com): " nextcloud_domain
        fi
    fi

    # Sous-réseau (par défaut 192.168.1.0/16 si Traefik)
    read -r -p "Sous-réseau Docker (ex: 192.168.1.0 sans le /16): " sous_reseau
    sous_reseau="${sous_reseau:-192.168.1.0}"

    # Mots de passe MariaDB (générés si pas fournis)
    mysql_root_password="${MYSQL_ROOT_PASSWORD:-$(openssl rand -base64 32 | tr -d "=+/" | tr 'A-Za-z0-9' 'A-Za-z0-9!@#%^&*()')}"
    mysql_password="${MYSQL_PASSWORD:-$(openssl rand -base64 32 | tr -d "=+/" | tr 'A-Za-z0-9' 'A-Za-z0-9!@#%^&*()')}"

    # Admin Nextcloud (générés si pas fournis)
    nextcloud_admin_user="${NEXTCLOUD_ADMIN_USER:-scsinfo}"
    nextcloud_admin_password="${NEXTCLOUD_ADMIN_PASSWORD:-$(openssl rand -base64 32 | tr -d "=+/" | tr 'A-Za-z0-9' 'A-Za-z0-9!@#%^&*()')}"
    echo

    # Génération complète .env
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

    echo "  -> .env Nextcloud généré complètement"
    echo "  -> Domaine: ${nextcloud_domain}"
    echo "  -> Sous-réseau: ${sous_reseau}"
    echo "  -> Admin: ${nextcloud_admin_user}"
    echo "  -> Mot de passe MariaDB root: ${mysql_root_password}" | sed 's/./*/g'
    echo "  -> Mot de passe MariaDB nextcloud: ${mysql_password}" | sed 's/./*/g'
}

generate_urbackup_files() {
    local srv_path="/srv/urbackup"

    if [ ! -f "$srv_path/.env" ]; then
        cat > "$srv_path/.env" <<EOF
LOCAL_IP=${LOCAL_IP}
PUBLIC_IP=${PUBLIC_IP}
HOST_NAME=${HOST_NAME}
EOF
        echo "  -> .env généré pour urbackup"
    fi
}

prepare_service() {
    local service="$1"

    case "$service" in
        monitoring)
            generate_monitoring_files
            ;;
        traefik)
            generate_traefik_files
            ;;
        nextcloud)
            generate_nextcloud_files
            ;;
        urbackup)
            generate_urbackup_files
            ;;
        *)
            echo "  -> Aucun traitement spécifique pour $service"
            ;;
    esac
}

deploy_service() {
    local service="$1"
    local srv_path="/srv/$service"

    echo ""
    echo "Déploiement de $service..."

    copy_service_files "$service"
    prepare_service "$service"

    if [ -f "$srv_path/docker-compose.yml" ]; then
        sudo docker compose -f "$srv_path/docker-compose.yml" up -d
        echo "  -> $service démarré"
    elif [ -f "$srv_path/compose.yml" ]; then
        sudo docker compose -f "$srv_path/compose.yml" up -d
        echo "  -> $service démarré"
    else
        echo "  -> Aucun fichier docker-compose.yml trouvé pour $service"
    fi
}

deploy_selected_services() {
    echo ""
    echo "=== Déploiement des services sélectionnés ==="

    for service in "${SELECTED_DIRS[@]}"; do
        deploy_service "$service"
    done
    echo ""
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

    echo ""
    echo "✅ Tous les services sélectionnés ont été traités."
}

# =========================
# Execution des fonctions
# =========================

main "$@"
