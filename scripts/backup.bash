#!/bin/bash
set -e

# Intended for Ubuntu 22.04 LTS
# MYSQL_DATABASE, MYSQL_PASSWORD, and MYSQL_USER set in .env file

_install_dependencies() {
  if ! command -V git >/dev/null 2>&1; then
    printf "%s\n" "INFO : Installing git..."
    apt -yqq update
    apt install -yqq git
  fi
  if ! command -V zip >/dev/null 2>&1; then
    printf "%s\n" "INFO : Installing zip..."
    apt -yqq update
    apt install -yqq zip
  fi
}

_create_backup_zip() {
  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    printf "%s\n" "ERROR : Git repository not detected. Exiting."
    exit 3
  else
    local git_toplevel=$(git rev-parse --show-toplevel)
  fi
  if [ ! -d "${git_toplevel}/backups" ]; then
    printf "%s\n" "ERROR : backups directory not found. Exiting."
    exit 3
  fi
  if [ ! -d "${git_toplevel}/tmp" ]; then
    printf "%s\n" "ERROR : tmp directory not found. Exiting."
    exit 3
  fi

  local backup_time=$(date +%s-%Y-%m-%d)
  local maintenance_message="'Backing up database. Write access will be restored shortly...';"

  # Lock database writes
  printf "%s\n" "INFO : Setting the wiki into read-only mode - $(date +%s)..."
  if docker exec -it nexipedia grep "?>" /var/www/html/LocalSettings.php >/dev/null; then
    docker exec -it nexipedia sed -i "s|?>|\$wgReadOnly = $maintenance_message?>|ig" /var/www/html/LocalSettings.php
  else
    docker exec -it nexipedia /bin/bash -c "printf '%s%s\n' '$' \"wgReadOnly = ${maintenance_message}?>\" >>/var/www/html/LocalSettings.php"
  fi

  # Retrieve data from mariadb
  printf "%s\n" "INFO : Copying files from mariadb..."
  docker exec -it nexipedia_mariadb /bin/bash -c "mysqldump --database ${MYSQL_DATABASE} -u ${MYSQL_USER} -p${MYSQL_PASSWORD}" >${git_toplevel}/tmp/${backup_time}.sql

  # Retrieve data from mediawiki
  printf "%s\n" "INFO : Copying files from mediawiki..."
  docker cp nexipedia:/var/www/html/extensions ${git_toplevel}/tmp
  docker cp nexipedia:/var/www/html/images ${git_toplevel}/tmp
  docker cp nexipedia:/var/www/html/LocalSettings.php ${git_toplevel}/tmp


  # Unlock database writes
  printf "%s\n" "INFO : Setting the wiki out of read-only mode - $(date +%s)..."
  if docker exec -it nexipedia grep "?>" /var/www/html/LocalSettings.php >/dev/null; then
    docker exec -it nexipedia sed -i "s|\$wgReadOnly = $maintenance_message?>|?>|ig" /var/www/html/LocalSettings.php
  else
    docker exec -it nexipedia sed -i "s|\$wgReadOnly = $maintenance_message?>||ig" /var/www/html/LocalSettings.php
  fi

  printf "%s\n" "INFO : Creating backup zip file '${backup_time}.zip' with latest contents..."

  zip -r -q ${git_toplevel}/backups/${backup_time}.zip \
    ${git_toplevel}/tmp/${backup_time}.sql \
    ${git_toplevel}/tmp/extensions/ \
    ${git_toplevel}/tmp/images/ \
    ${git_toplevel}/tmp/LocalSettings.php

  rm -rf ${git_toplevel}/tmp/${backup_time}.sql \
    ${git_toplevel}/tmp/extensions/ \
    ${git_toplevel}/tmp/images/ \
    ${git_toplevel}/tmp/LocalSettings.php
}

_rotate_local_backup_zips() {
  local num_local_backups='5'

  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    printf "%s\n" "ERROR : Git repository not detected. Exiting."
    exit 3
  else
    local git_toplevel=$(git rev-parse --show-toplevel)
  fi

  # Keep five local backups
  while [ $(ls ${git_toplevel}/backups | wc -l) -gt ${num_local_backups} ]; do
    printf "%s\n" "INFO : More than ${num_local_backups} local backups. Removing $(ls ${git_toplevel}/backups | head -n 1)..."
    # Delete alphabetically oldest file (ls sort by name is default)
    rm ${git_toplevel}/backups/$(ls ${git_toplevel}/backups | head -n 1)
    sleep 1
  done
}

cd /root/Projects/Nexus/Nexus.Nexipedia
_install_dependencies
_create_backup_zip
_rotate_local_backup_zips

printf "%s\n" "INFO : Backup routine finished successfully"
