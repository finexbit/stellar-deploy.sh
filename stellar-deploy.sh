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


function setup_stellar_core {
  echo "Installing Stellar Core"
  echo "Adding the SDF stable repository to your system"
  # from https://github.com/stellar/packages
  echo "Download public key: $(wget -qO - https://apt.stellar.org/SDF.asc | sudo apt-key add -)"
  echo "Saving the repository definition to /etc/apt/sources.list.d/SDF.list: $(echo "deb https://apt.stellar.org/public stable/" | sudo tee -a /etc/apt/sources.list.d/SDF.list)"

  #Do not start automatically
  ln -s /dev/null /etc/systemd/system/stellar-core.service

  sudo apt-get update && apt-get install stellar-core
  echo "Stellar Core Installed"
  echo "Configuring....... "
  echo "Creating stellar core config "
  sudo touch ${CORE_CONFIG_FILE}
  sudo echo "HTTP_PORT=$CORE_PORT" >> ${CORE_CONFIG_FILE}
  sudo echo "PUBLIC_HTTP_PORT=true" >> ${CORE_CONFIG_FILE}
  sudo echo 'LOG_FILE_PATH="/var/log/stellar/stellar-core.log"' >> ${CORE_CONFIG_FILE}
  sudo echo 'BUCKET_DIR_PATH="/var/lib/stellar/buckets"' >> ${CORE_CONFIG_FILE}
  sudo echo "DATABASE=\"postgresql://dbname=$CORE_DB_NAME user=$DB_USER\"" >> ${CORE_CONFIG_FILE}
  sudo echo 'UNSAFE_QUORUM=true' >> ${CORE_CONFIG_FILE}
  sudo echo 'FAILURE_SAFETY=1' >> ${CORE_CONFIG_FILE}

  if [ "$CATCHUP_COMPLETE" == "true" ]
  then
    sudo echo 'CATCHUP_COMPLETE=true' >> ${CORE_CONFIG_FILE}
  else
    sudo echo 'CATCHUP_COMPLETE=false' >> ${CORE_CONFIG_FILE}
    sudo echo 'CATCHUP_RECENT=1024' >> ${CORE_CONFIG_FILE}
  fi

  if [ "$STELLAR_NETWORK" == "testnet" ]
  then
    create_testnet_config
  else
    create_pubnet_config
  fi

  echo "Initialise Stellar Core Database"
  sudo -u ${DB_USER} stellar-core --conf ${CORE_CONFIG_FILE} --newdb
  
  echo "Enabling Stellar Core"
  sudo systemctl enable stellar-core
  echo "Starting Stellar Core"
  sudo systemctl start stellar-core 


}

function setup_horizon {
  echo "Installing Horizon Server"
  sudo apt-get update && apt-get install stellar-horizon
  echo "Horizon Server Installed"
  echo "Configuring....... "
  echo "Creating horizon config "
  sudo touch ${HORIZON_CONFIG_FILE}
  sudo echo "## ${HORIZON_CONFIG_FILE}" >> ${HORIZON_CONFIG_FILE}
  if [ "$STELLAR_NETWORK" == "testnet" ]
  then
    sudo echo 'NETWORK_PASSPHRASE="'${TESTNET_PASSPHRASE}'"' >> ${HORIZON_CONFIG_FILE}
  else
    sudo echo 'NETWORK_PASSPHRASE="'${PUBNET_PASSPHRASE}'"' >> ${HORIZON_CONFIG_FILE}
  fi
  sudo echo "DATABASE_URL=\"dbname=$HORIZON_DB_NAME user=$DB_USER\" host=/var/run/postgresql" >> ${HORIZON_CONFIG_FILE}

  sudo echo "STELLAR_CORE_DATABASE_URL=\"dbname=$HORIZON_DB_NAME user=$DB_USER\" host=/var/run/postgresql" >> ${HORIZON_CONFIG_FILE}

  sudo echo '
    STELLAR_CORE_URL="http://127.0.0.1:11626"
    FRIENDBOT_SECRET=
    PORT='${HORIZON_PORT}'
    SENTRY_DSN=
    LOGGLY_TOKEN=
    PER_HOUR_RATE_LIMIT='${HORIZON_RATE_LIMIT}'
    INGEST=true
    # ingestion is currently only supported on 1 Horizon instance
  ' >> ${HORIZON_CONFIG_FILE}

  if [ "$CATCHUP_COMPLETE" == "true" ]
  then
    sudo echo 'HISTORY_RETENTION_COUNT=0' >> ${HORIZON_CONFIG_FILE}  
  fi

  echo "Initializing Horizon DB"
  stellar-horizon-cmd db init

  echo "Enable Horizon Server"
  sudo systemctl enable stellar-horizon
  # echo "Starting Horizon Server"
  # sudo systemctl start stellar-horizon
  
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