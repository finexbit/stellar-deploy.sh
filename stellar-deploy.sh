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

function create_testnet_config {
  sudo echo 'NETWORK_PASSPHRASE="'${TESTNET_PASSHPRASE}'"' >>  /etc/stellar/stellar-core.cfg
  sudo echo 
  '
    KNOWN_PEERS=[
    "core-testnet1.stellar.org",
    "core-testnet2.stellar.org",
    "core-testnet3.stellar.org"]
    
    #The public keys of the Stellar testnet servers
    [QUORUM_SET]
    THRESHOLD_PERCENT=51 # rounded up -> 2 nodes out of 3
    VALIDATORS=[
    "GDKXE2OZMJIPOSLNA6N6F2BVCI3O777I2OOC4BV7VOYUEHYX7RTRYA7Y  sdf1",
    "GCUCJTIYXSOXKBSNFGNFWW5MUQ54HKRPGJUTQFJ5RQXZXNOLNXYDHRAP  sdf2",
    "GC2V2EFSXN6SQTWVYA5EPJPBWWIMSD2XQNKUOHGEKB535AQE2I6IXV2Z  sdf3"]


    #The history store of the Stellar testnet
    [HISTORY.h1]
    get="curl -sf http://s3-eu-west-1.amazonaws.com/history.stellar.org/prd/core-testnet/core_testnet_001/{0} -o {1}"

    [HISTORY.h2]
    get="curl -sf http://s3-eu-west-1.amazonaws.com/history.stellar.org/prd/core-testnet/core_testnet_002/{0} -o {1}"

    [HISTORY.h3]
    get="curl -sf http://s3-eu-west-1.amazonaws.com/history.stellar.org/prd/core-testnet/core_testnet_003/{0} -o {1}"
  ' >> /etc/stellar/stellar-core.cfg
}

function create_pubnet_config {
  echo '
    NETWORK_PASSPHRASE="'${PUBNET_PASSPHRASE}'"

    NODE_NAMES=[
    "GAOO3LWBC4XF6VWRP5ESJ6IBHAISVJMSBTALHOQM2EZG7Q477UWA6L7U  eno",
    "GAXP5DW4CVCW2BJNPFGTWCEGZTJKTNWFQQBE5SCWNJIJ54BOHR3WQC3W  moni",
    "GBFZFQRGOPQC5OEAWO76NOY6LBRLUNH4I5QYPUYAK53QSQWVTQ2D4FT5  dzham",
    "GDXWQCSKVYAJSUGR2HBYVFVR7NA7YWYSYK3XYKKFO553OQGOHAUP2PX2  jianing",
    "GCJCSMSPIWKKPR7WEPIQG63PDF7JGGEENRC33OKVBSPUDIRL6ZZ5M7OO  tempo.eu.com",
    "GCCW4H2DKAC7YYW62H3ZBDRRE5KXRLYLI4T5QOSO6EAMUOE37ICSKKRJ  sparrow_tw",
    "GD5DJQDDBKGAYNEAXU562HYGOOSYAEOO6AS53PZXBOZGCP5M2OPGMZV3  fuxi.lab",
    "GBGGNBZVYNMVLCWNQRO7ASU6XX2MRPITAGLASRWOWLB4ZIIPHMGNMC4I  huang.lab",
    "GDPJ4DPPFEIP2YTSQNOKT7NMLPKU2FFVOEIJMG36RCMBWBUR4GTXLL57  nezha.lab",
    "GCDLFPQ76D6YUSCUECLKI3AFEVXFWVRY2RZH2YQNYII35FDECWUGV24T  SnT.Lux",
    "GBAR4OY6T6M4P344IF5II5DNWHVUJU7OLQPSMG2FWVJAFF642BX5E3GB  telindus",
    # non validating
    "GCGB2S2KGYARPVIA37HYZXVRM2YZUEXA6S33ZU5BUDC6THSB62LZSTYH  sdf_watcher1",
    "GCM6QMP3DLRPTAZW2UZPCPX2LF3SXWXKPMP3GKFZBDSF3QZGV2G5QSTK  sdf_watcher2",
    "GABMKJM6I25XI4K7U6XWMULOUQIQ27BCTMLS6BYYSOWKTBUXVRJSXHYQ  sdf_watcher3",
    # seem down
    "GB6REF5GOGGSEHZ3L2YK6K4T4KX3YDMWHDCPMV7MZJDLHBDNZXEPRBGM  donovan",
    "GBGR22MRCIVW2UZHFXMY5UIBJGPYABPQXQ5GGMNCSUM2KHE3N6CNH6G5  nelisky1",
    "GA2DE5AQF32LU5OZ5OKAFGPA2DLW4H6JHPGYJUVTNS3W7N2YZCTQFFV6  nelisky2",
    "GDJ73EX25GGUVMUBCK6DPSTJLYP3IC7I3H2URLXJQ5YP56BW756OUHIG  w00kie",
    "GAM7A32QZF5PJASRSGVFPAB36WWTHCBHO5CHG3WUFTUQPT7NZX3ONJU4  ptarasov"
    ]

    KNOWN_PEERS=[
    "core-live-a.stellar.org:11625",
    "core-live-b.stellar.org:11625",
    "core-live-c.stellar.org:11625",
    "confucius.strllar.org",
    "stellar1.bitventure.co",
    "stellar.256kw.com"]

    [QUORUM_SET]
    VALIDATORS=[
    "$sdf_watcher1","$eno","$tempo.eu.com","$sdf_watcher2","$sdf_watcher3"
    ]

    [HISTORY.cache]
    get="cp /opt/stellar/history-cache/{0} {1}"

    # Stellar.org history store
    [HISTORY.sdf1]
    get="curl -sf http://history.stellar.org/prd/core-live/core_live_001/{0} -o {1}"

    [HISTORY.sdf2]
    get="curl -sf http://history.stellar.org/prd/core-live/core_live_002/{0} -o {1}"

    [HISTORY.sdf3]
    get="curl -sf http://history.stellar.org/prd/core-live/core_live_003/{0} -o {1}"
  ' >> /etc/stellar/stellar-core.cfg
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