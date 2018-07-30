#!/bin/bash

# Copyright 2016 - 2018 Crunchy Data Solutions, Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

source /opt/cpm/bin/common_lib.sh
enable_debugging
ose_hack

export PATH=$PATH:/usr/pgsql-*/bin
PGADMIN_DIR='/usr/lib/python2.7/site-packages/pgadmin4-web'
PGADMIN_PIDFILE='/tmp/pgadmin.pid'
HAPROXY_PIDFILE='/tmp/haproxy.pid'

function trap_sigterm() {
    echo_info "Doing trap logic.."

    echo_warn "Clean shutdown of haproxy..."
    # Use SIGUSER1 to stop listening and wait on existing connections to complete.
    kill -SIGTERM $(head -1 $HAPROXY_PIDFILE)
    
    echo_warn "Clean shutdown of pgAdmin4..."
    kill -SIGINT $(head -1 $PGADMIN_PIDFILE)
}

trap 'trap_sigterm' SIGINT SIGTERM

env_check_err "PGADMIN_SETUP_EMAIL"
env_check_err "PGADMIN_SETUP_PASSWORD"

cp /opt/cpm/conf/config_local.py /var/lib/pgadmin/config_local.py

if [[ ${ENABLE_TLS:-false} == 'true' ]]
then
    echo_info "TLS enabled. Applying https configuration.."      # REMOVE / CHANGE
    if [[ ( ! -f /certs/server.key ) || ( ! -f /certs/server.crt ) ]]; then
        echo_err "ENABLE_TLS true but /certs/server.key or /certs/server.crt not found, aborting"
        exit 1
    fi

    cp /opt/cpm/conf/haproxy-https.conf /var/lib/haproxy/haproxy.conf

else
    echo_info "TLS disabled. Applying http configuration.."
    cp /opt/cpm/conf/haproxy-http.conf /var/lib/haproxy/haproxy.conf
fi

sed -i "s/^DEFAULT_SERVER_PORT.*/DEFAULT_SERVER_PORT = ${SERVER_PORT:-5000}/" /var/lib/pgadmin/config_local.py
sed -i "s|\"pg\":.*|\"pg\": \"/usr/pgsql-${PGVERSION?}/bin\",|g" /var/lib/pgadmin/config_local.py

cd ${PGADMIN_DIR?}

if [[ ! -f /var/lib/pgadmin/pgadmin4.db ]]
then
    echo_info "Setting up pgAdmin4 database.."
    python setup.py
fi

cd ${PGADMIN_DIR?}
echo_info "Starting haproxy..."
haproxy -D -f /var/lib/haproxy/haproxy.conf -p /tmp/haproxy.pid 

echo_info "Starting pgAdmin4 server.."
python pgAdmin4.py &

echo $! > $PGADMIN_PIDFILE

wait
