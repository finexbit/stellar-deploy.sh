#!/bin/bash
set -e
# Shell script to install and setup the following Stellar components
# - Stellar Core
# - Horizon Server
# - Bridge Server
# - Compliance Server
# - Federation Server
# - Stellar toml file
# The following softwares will be installed as well 
# - Postgresql DB
# - Supervisor
# - Apache web server
# - Letsencrypt certbot

# source config file
. ./stellar-deploy.conf

function system_check {
  echo "Checking system requirements...."
  sleep 1
  
  dist=`lsb_release -a | grep "ID" | cut -d: -f2`
  dist_version=`lsb_release -a | grep "Release" | cut -d: -f2`
  available_storage=`df -Ph . | awk 'NR==2 {print $4}'`
  storage_type=${available_storage: -1}
  available_storage_size=`echo $available_storage | cut -d$storage_type -f1`
  
  echo "Available disk: $available_storage" 
  echo "OS: $dist $dist_version"
  
  sleep 1

  if [ $storage_type != "G" -o $available_storage_size -lt 20 ]
  then
    echo "Minimum of 20G disk space is recommended... Exiting."
    exit 1
  elif [ $dist != "Ubuntu" -a $dist_version != "16.04" ]
  then
    cat <<-EOF
      Installation aborted. 
      Ubuntu 16.04 is required.
EOF
        exit 1
  fi
}

function setup_postgresql {
  echo "Installing Postgresql ..."
  sudo apt-get update
  sudo apt-get install postgresql postgresql-contrib
  echo "Create postgresql role ..."
  sudo -u postgres psql -e<<-EOF 
  
  CREATE ROLE ${DB_USER} PASSWORD '${DB_PASSWORD}' CREATEDB CREATEROLE INHERIT LOGIN;
EOF
  sudo -u postgres createdb ${DB_USER} 
  #create system user
  sudo useradd ${DB_USER}
}


echo "Start Stellar Deploy"

system_check
# setup_postgresql
# setup_stellar_core
# setup_horizon
# setup_bridge
# setup_compliance
# setup_federation
# setup_supervisor
# setup_apache
# setup_stellar_toml
# setup_ssl
# setup_mock_callback
# start_services

echo "Stellay Deploy ... OK"