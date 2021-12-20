#!/usr/bin/env bash
set -x
set +e
# shellcheck disable=SC1091
source /etc/satelliteflags/ibm-host-agent-vars
set -e
UPIADD_PASSWORD="{{ .UPIAddSecret }}"
IGNITION_TOKEN="{{ .IgnitionToken }}"
IGNITION_URL="{{ .IgnitionURL }}"
CA_CERT="{{ .IgnitionCACert }}"
mkdir -p /etc/satelliteflags
HOST_BOOTSTRAP_INITIATED_FLAG="/etc/satelliteflags/hostbootstrapinitatedflag"
if [[ -f "$HOST_BOOTSTRAP_INITIATED_FLAG" ]]; then
	echo "bootstrap process has already been initiated on this host. the host needs to be reloaded before further action is done"
	exit 0
fi

#STEP 1: GATHER INFORMATION THAT WILL BE USED TO POPULATE MODEL JUST LIKE ANY OTHER IKS/OPENSHIFT VPC WORKER
DEFAULT_INTERFACE=$(ip -4 route ls | grep default | head -n 1 | grep -Po '(?<=dev )(\S+)')
WORKER_SUBNET=$(ip addr show dev "$DEFAULT_INTERFACE" | grep "inet " | awk '{print $2}' | awk 'NR==1{print $1}')
WORKER_IP=$(echo "$WORKER_SUBNET" | awk -F / '{print $1}')
HOSTNAME=$(hostname -s)
HOSTNAME=${HOSTNAME,,}

{{ if .WorkerName }}
WORKER_NAME="{{ .WorkerName }}"
{{ end }}

if [[ -z "${WORKER_NAME}" ]]; then # set worker name if not being set by -api
	HOSTNAME_NO_DASHES=${HOSTNAME//-/}
	MACHINE_ID=$(cat /etc/machine-id)
	printf "%s%s" "$HOSTNAME" "$MACHINE_ID" >/tmp/uniqueid
	UNIQUE_ID_LONG=$(sha512sum /tmp/uniqueid | awk '{print $1}')
	UNIQUE_ID="sat-${HOSTNAME_NO_DASHES:0:10}-${UNIQUE_ID_LONG: -40}"
	WORKER_NAME="$UNIQUE_ID"
fi

BOOTSTRAP_URL="{{ .BootstrapURL }}"
WORKER_POOL="{{ .WorkerPoolID }}"
INSTANCE_GROUP="{{ .InstanceGroupID }}"
# INTELLIGENT Logic can be added down the line to auto template these values in but for MVP well defined
ZONE="{{ .Zone }}"
CLUSTERID="{{ .ClusterID }}"
REGION="{{ .Region }}"

#STEP 2: REPORT THAT TO THE ADD UPI WORKER API.
#UPI API IS GOING TO JUST SET KEYS IN ETCD TO CREATE THE WORKER IN DEPLOYING STATE
# AFTER VALIDATING THE REQUEST AND THEN RETURN ONE TIME PASSWORD
# HOST_ID AND ASSIGNMENT_ID COME FROM THE HOSTQUEUE API, IF BEING USED.
set +x
RESPONSE_DATE=$(curl --write-out "HTTPSTATUS:%{http_code}" --retry 100 --retry-delay 10 --retry-max-time 1800 -X POST -H "X-One-Time-Password: $UPIADD_PASSWORD" \
	-H "Content-Type: application/x-www-form-urlencoded" \
	--data-urlencode worker_ip="$WORKER_IP" \
	--data-urlencode assignment_id="$ASSIGNMENT_ID" \
	--data-urlencode host_id="$HOST_ID" \
	--data-urlencode worker_subnet="$WORKER_SUBNET" \
	--data-urlencode hostname="$HOSTNAME" \
	--data-urlencode worker_id="$WORKER_NAME" \
	--data-urlencode clusterid="$CLUSTERID" \
	--data-urlencode worker_pool_id="$WORKER_POOL" \
	--data-urlencode zone="$ZONE" \
	--data-urlencode instance_group_id="$INSTANCE_GROUP" \
	"${BOOTSTRAP_URL}/upiworker")
set -x
HTTP_BODY=$(echo "$RESPONSE_DATE" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
HTTP_STATUS=$(echo "$RESPONSE_DATE" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')

echo "$HTTP_BODY"
echo "$HTTP_STATUS"
if [ "$HTTP_STATUS" -ne 200 ]; then
 echo "Error [HTTP status: $HTTP_STATUS]"
 exit 1
fi

#STEP 3: Proceed to download all ignition data locally and extract out the machine config daemon binary
function urldecode() { : "${*//+/ }"; echo -e "${_//%/\\x}"; }

function add_data() {
	file_path=$1
	file_name=$(basename "${file_path}")
	jq -r '.storage.files[] | select(.path=="'"$file_path"'")' /tmp/ignition-data-raw.json >/tmp/"${file_name}"
	jq --argjson groupInfo "$(</tmp/"${file_name}")" '.spec.config.storage.files += [$groupInfo]' /tmp/ignition-machine-config-encapsulated.json >/tmp/ignition-machine-config-encapsulated_tmp.json
	mv /tmp/ignition-machine-config-encapsulated_tmp.json /tmp/ignition-machine-config-encapsulated.json
}

echo -e "${CA_CERT}" > /tmp/ca_cert.pem
chmod 0600 /tmp/ca_cert.pem

curl --cacert "/tmp/ca_cert.pem" --retry 100 --retry-delay 10 --retry-max-time 1800 -s -k -H "Authorization: ${IGNITION_TOKEN}" "${IGNITION_URL}" >/tmp/ignition-data-raw.json || exit 1

# machine config content
encoded_value=$(jq -r '.storage.files[] | select(.path=="/etc/mcs-machine-config-content.json") | .contents.source' "/tmp/ignition-data-raw.json" | awk -F, '{print $2}')
urldecode "${encoded_value}" >/tmp/ignition-machine-config-encapsulated.json

encoded_value=$(jq -r '.storage.files[] | select(.path=="/etc/containers/registries.conf") | .contents.source' "/tmp/ignition-data-raw.json" | awk -F, '{print $2}')
urldecode "${encoded_value}" >/tmp/registries.conf

encoded_value=$(jq -r '.storage.files[] | select(.path=="/etc/sysconfig/machineconfigdaemonsha") | .contents.source' "/tmp/ignition-data-raw.json" | awk -F, '{print $2}')
echo "$encoded_value" | base64 -d >/tmp/machineconfigdaemonsha
# will contain sha of machine-config-daemon image in var MACHINE_CONFIG_DAEMON_SHA
source /tmp/machineconfigdaemonsha
MIRRORED_RELEASE_IMAGE_BASE=$(cat /tmp/registries.conf | grep armada-master | awk 'NR==1{print $NF}' | awk -F '"' '{print $2}')
rm -rf /tmp/machineconfigdaemoncontents
mkdir -p /tmp/machineconfigdaemoncontents
oc image extract --only-files=true "${MIRRORED_RELEASE_IMAGE_BASE}@${MACHINE_CONFIG_DAEMON_SHA}" --path /usr/bin/machine-config-daemon:/tmp/machineconfigdaemoncontents
cp -f /tmp/machineconfigdaemoncontents/machine-config-daemon /usr/local/bin/machine-config-daemon
chmod 0700 /usr/local/bin/machine-config-daemon

# need extra content
# need these extra files added by the ignition server: /etc/machine-config-daemon/node-annotations.json, /etc/kubernetes/kubeconfig
add_data /etc/kubernetes/kubeconfig
add_data /etc/machine-config-daemon/node-annotations.json

# copy it to the location it needs to go to
cp -f /tmp/ignition-machine-config-encapsulated.json /etc/ignition-machine-config-encapsulated.json

# set fips to false
jq '.spec.fips=false' /etc/ignition-machine-config-encapsulated.json >/etc/ignition-machine-config-encapsulated_tmp.json
mv /etc/ignition-machine-config-encapsulated_tmp.json /etc/ignition-machine-config-encapsulated.json

# add empty sshAuthorizationKey
jq '.spec.config.passwd.users[0] += {"sshAuthorizedKeys": [ "" ]}' /etc/ignition-machine-config-encapsulated.json >/etc/ignition-machine-config-encapsulated_tmp.json
mv /etc/ignition-machine-config-encapsulated_tmp.json /etc/ignition-machine-config-encapsulated.json

#Step 4: with everything in place proceed to start the machine-config-daemon
cat <<'EOF' >/etc/systemd/system/ibm-firstboot-ignition.service
[Unit]
Description=IBM Firstboot Ignition Service
After=network.target
[Service]
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/usr/local/bin/machine-config-daemon firstboot-complete-machineconfig
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
chmod 0644 /etc/systemd/system/ibm-firstboot-ignition.service
systemctl daemon-reload
systemctl start ibm-firstboot-ignition.service
touch "$HOST_BOOTSTRAP_INITIATED_FLAG"
