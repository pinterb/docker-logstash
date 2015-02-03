#! /bin/bash
# #################################################################
# NAME: logstash.sh
# DESC: Logstash startup file.
#
# LOG:
# yyyy/mm/dd [user] [version]: [notes]
# 2015/02/02 cgwong v0.1.0: Use confd for configuration management.
# #################################################################

# Fail hard and fast
set -eo pipefail

# Set environment variables
LS_HOME=${LS_HOME:-/opt/logstash}
LS_CFG_FILE=${LS_CFG_FILE:-"/etc/logstash/conf.d/logstash.conf"}
LS_SSL=/etc/logstash/ssl

KV_TYPE=${KV_TYPE:-etcd}
KV_HOST=${KV_HOST:-172.17.8.101}
KV_PORT=${KV_PORT:-4001}
KV_URL=${KV_HOST}:${KV_PORT}

echo "[logstash] booting container. KV store: $KV_TYPE"

# Loop until confd has updated the logstash config
until confd -onetime -backend $KV_TYPE -node $KV_URL -config-file /etc/confd/conf.d/logstash.conf.toml; do
  echo "[logstash] waiting for confd to refresh logstash.conf (waiting for ElasticSearch to be available)"
  sleep 5
done

# Create a new SSL certificate for Logstash-Forwarder
openssl req -x509 -batch -nodes -newkey rsa:2048 -keyout ${LS_SSL}/logstash-forwarder.key -out ${LS_SSL}/logstash-forwarder.crt

# Publish SSL cert/key to KV store
if [ "$KV_TYPE" == "etcd" ]; then
  # Etcd as KV store
  curl -L $KV_URL/v2/keys/logstash/ssl_certificate -XPUT --data-urlencode value@${LS_SSL}/logstash-forwarder.crt
  curl -L $KV_URL/v2/keys/logstash/ssl_private_key -XPUT --data-urlencode value@${LS_SSL}/logstash-forwarder.key
else
  # Assume it's consul KV otherwise
  curl -L $KV_URL/v1/kv/logstash/ssl_certificate -XPUT --data-urlencode value@${LS_SSL}/logstash-forwarder.crt
  curl -L $KV_URL/v1/kv/logstash/ssl_private_key -XPUT --data-urlencode value@${LS_SSL}/logstash-forwarder.key
fi

# if `docker run` first argument start with `--` the user is passing launcher arguments
if [[ $# -lt 1 ]] || [[ "$1" == "--"* ]]; then
  exec ${LS_HOME}/bin/logstash -f ${LS_CFG_FILE} "$@"
fi

# As argument is not Logstash, assume user want to run his own process, for sample a `bash` shell to explore this image
exec "$@"
