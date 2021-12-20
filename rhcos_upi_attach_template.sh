#!/usr/bin/env bash
set -ex
mkdir -p /etc/satelliteflags
HOST_ASSIGN_FLAG="/etc/satelliteflags/hostattachflag"
if [[ -f "$HOST_ASSIGN_FLAG" ]]; then
    echo "host has already been assigned. need to reload before you try the attach again"
    exit 0
fi
set +x
HOST_QUEUE_TOKEN="{{ .HostQueueToken }}"
set -x
ACCOUNT_ID="{{ .AccountID }}"
CONTROLLER_ID="{{ .ControllerID }}"
API_URL="{{ .APIURL }}"
API_TEMP_URL=$(echo "$API_URL" | awk -Fbootstrap '{print $1}')
REGION="{{ .Region }}"
{{ if .SelectorLabels }}
SELECTOR_LABELS='{{ .SelectorLabels }}'
echo "${SELECTOR_LABELS}" > /tmp/providedselectorlabels
{{ end }}
export HOST_QUEUE_TOKEN
export ACCOUNT_ID
export CONTROLLER_ID
export REGION
#shutdown known blacklisted services for Satellite (these will break kube)
set +e
systemctl stop -f iptables.service
systemctl disable iptables.service
systemctl mask iptables.service
systemctl stop -f firewalld.service
systemctl disable firewalld.service
systemctl mask firewalld.service
set -e
mkdir -p /etc/satellitemachineidgeneration
if [[ ! -f /etc/satellitemachineidgeneration/machineidgenerated ]]; then
    rm -f /etc/machine-id
    systemd-machine-id-setup
    touch /etc/satellitemachineidgeneration/machineidgenerated
fi
#STEP 1: GATHER INFORMATION THAT WILL BE USED TO REGISTER THE HOST
MACHINE_ID=$(cat /etc/machine-id)
CPUS=$(nproc)
MEMORY=$(grep MemTotal /proc/meminfo | awk '{print $2}')
HOSTNAME=$(hostname -s)
HOSTNAME=${HOSTNAME,,}
export CPUS
export MEMORY

set +e
if grep -qi "coreos" < /etc/redhat-release; then
  OPERATING_SYSTEM="RHCOS"
elif grep -qi "maipo" < /etc/redhat-release; then
  OPERATING_SYSTEM="RHEL7"
elif grep -qi "ootpa" < /etc/redhat-release; then
  OPERATING_SYSTEM="RHEL8"
else
  echo "Operating System not supported"
  OPERATING_SYSTEM="UNKNOWN"
fi
set -e

export OPERATING_SYSTEM

if [[ "${OPERATING_SYSTEM}" != "RHCOS" ]]; then
  echo "This script is only intended to run with an RHCOS operating system. Current operating system ${OPERATING_SYSTEM}"
  exit 1
fi

SELECTOR_LABELS=$(jq -n --arg CPUS "$CPUS" --arg MEMORY "$MEMORY" --arg OPERATING_SYSTEM "$OPERATING_SYSTEM" '{
  cpu: $CPUS,
  memory: $MEMORY,
  os: $OPERATING_SYSTEM
}')
set +e
export ZONE=""
echo "Probing for AWS metadata"
gather_zone_info() {
    HTTP_RESPONSE=$(curl --write-out "HTTPSTATUS:%{http_code}" --max-time 10 http://169.254.169.254/latest/meta-data/placement/availability-zone)
    HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | awk -F: '/.*HTTPSTATUS:([0-9]{3})$/ { print $2 }')
    HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
    if [[ "$HTTP_STATUS" -ne 200 ]]; then
        echo "bad return code"
        return 1
    fi
    if [[ "$HTTP_BODY" =~ [^a-zA-Z0-9-] ]]; then
        echo "invalid zone format"
        return 1
    fi
    ZONE="$HTTP_BODY"
}
if gather_zone_info; then
    echo "aws metadata detected"
fi
if [[ -z "$ZONE" ]]; then
    echo "echo Probing for Azure Metadata"
    export LOCATION_INFO=""
    export AZURE_ZONE_NUMBER_INFO=""
    gather_location_info() {
        HTTP_RESPONSE=$(curl -H Metadata:true --noproxy "*" --write-out "HTTPSTATUS:%{http_code}" --max-time 10 "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-01-01&format=text")
        HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | awk -F: '/.*HTTPSTATUS:([0-9]{3})$/ { print $2 }')
        HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
        if [[ "$HTTP_STATUS" -ne 200 ]]; then
            echo "bad return code"
            return 1
        fi
        if [[ "$HTTP_BODY" =~ [^a-zA-Z0-9-] ]]; then
            echo "invalid format"
            return 1
        fi
        LOCATION_INFO="$HTTP_BODY"
    }
    gather_azure_zone_number_info() {
        HTTP_RESPONSE=$(curl -H Metadata:true --noproxy "*" --write-out "HTTPSTATUS:%{http_code}" --max-time 10 "http://169.254.169.254/metadata/instance/compute/zone?api-version=2021-01-01&format=text")
        HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
        HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
        if [[ "$HTTP_STATUS" -ne 200 ]]; then
            echo "bad return code"
            return 1
        fi
        if [[ "$HTTP_BODY" =~ [^a-zA-Z0-9-] ]]; then
            echo "invalid format"
            return 1
        fi
        AZURE_ZONE_NUMBER_INFO="$HTTP_BODY"
    }
    gather_zone_info() {
        if ! gather_location_info; then
            return 1
        fi
        if ! gather_azure_zone_number_info; then
            return 1
        fi
        if [[ -n "$AZURE_ZONE_NUMBER_INFO" ]]; then
          ZONE="${LOCATION_INFO}-${AZURE_ZONE_NUMBER_INFO}"
        else
          ZONE="${LOCATION_INFO}"
        fi
    }
    if gather_zone_info; then
        echo "azure metadata detected"
    fi
fi
if [[ -z "$ZONE" ]]; then
    echo "echo Probing for GCE Metadata"
    gather_zone_info() {
        HTTP_RESPONSE=$(curl --write-out "HTTPSTATUS:%{http_code}" --max-time 10 "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google")
        HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
        HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
        if [[ "$HTTP_STATUS" -ne 200 ]]; then
            echo "bad return code"
            return 1
        fi
        POTENTIAL_ZONE_RESPONSE=$(echo "$HTTP_BODY" | awk -F '/' '{print $NF}')
        if [[ "$POTENTIAL_ZONE_RESPONSE" =~ [^a-zA-Z0-9-] ]]; then
            echo "invalid zone format"
            return 1
        fi
        ZONE="$POTENTIAL_ZONE_RESPONSE"
    }
    if gather_zone_info; then
        echo "gce metadata detected"
    fi
fi
set -e
if [[ -n "$ZONE" ]]; then
  SELECTOR_LABELS=$(jq -n --arg CPUS "$CPUS" --arg MEMORY "$MEMORY" --arg OPERATING_SYSTEM "$OPERATING_SYSTEM" --arg ZONE "$ZONE" '{
  cpu: $CPUS,
  memory: $MEMORY,
  os: $OPERATING_SYSTEM,
  zone: $ZONE
}')
fi
echo "${SELECTOR_LABELS}" > /tmp/detectedselectorlabels

if [ -f "/tmp/providedselectorlabels" ]; then
  SELECTOR_LABELS="$(jq -s '.[0] * .[1]' /tmp/detectedselectorlabels /tmp/providedselectorlabels)"
else
  SELECTOR_LABELS=$(jq . /tmp/detectedselectorlabels)
fi

#Step 2: SETUP METADATA
cat <<EOF >/tmp/register.json
{
"controller": "$CONTROLLER_ID",
"name": "$HOSTNAME",
"identifier": "$MACHINE_ID",
"labels": $SELECTOR_LABELS
}
EOF
set +e
#try to download and run host health check script
set +x
#first try to the satellite-health service is enabled
HTTP_RESPONSE=$(curl --write-out "HTTPSTATUS:%{http_code}" --retry 5 --retry-delay 10 --retry-max-time 60 \
        "${API_URL}satellite-health/api/v1/hello")
set -x
HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
echo "$HTTP_STATUS"
if [[ "$HTTP_STATUS" -eq 200 ]]; then
        set +x
        HTTP_RESPONSE=$(curl --write-out "HTTPSTATUS:%{http_code}" --retry 20 --retry-delay 10 --retry-max-time 360 \
                "${API_URL}satellite-health/sat-host-check" -o /usr/local/bin/sat-host-check)
        set -x
        HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
        HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | awk -F: '/.*HTTPSTATUS:([0-9]{3})$/ { print $2 }')
        echo "$HTTP_BODY"
        echo "$HTTP_STATUS"
        if [[ "$HTTP_STATUS" -eq 200 ]]; then
                chmod +x /usr/local/bin/sat-host-check
                set +x
                timeout 5m /usr/local/bin/sat-host-check --region $REGION --endpoint $API_URL
                set -x
        else
                echo "Error downloading host health check script [HTTP status: $HTTP_STATUS]"
        fi
else
        echo "Skipping downloading host health check script [HTTP status: $HTTP_STATUS]"
fi
set -e
set +x
#STEP 3: REGISTER HOST TO THE HOSTQUEUE. NEED TO EVALUATE HTTP STATUS 409 EXISTS, 201 created. ALL OTHERS FAIL.
HTTP_RESPONSE=$(curl --write-out "HTTPSTATUS:%{http_code}" --retry 100 --retry-delay 10 --retry-max-time 1800 -X POST \
    -H "X-Auth-Hostqueue-APIKey: $HOST_QUEUE_TOKEN" \
    -H "X-Auth-Hostqueue-Account: $ACCOUNT_ID" \
    -H "Content-Type: application/json" \
    -d @/tmp/register.json \
    "${API_TEMP_URL}v2/multishift/hostqueue/host/register")
set -x
HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
echo "$HTTP_BODY"
echo "$HTTP_STATUS"
if [[ "$HTTP_STATUS" -ne 201 ]]; then
    echo "Error [HTTP status: $HTTP_STATUS]"
    exit 1
fi
#STEP 4: WAIT FOR MEMBERSHIP TO BE ASSIGNED
HOST_ID=$(echo "$HTTP_BODY" | jq -r '.id')
while true; do
    set +ex
    ASSIGNMENT=$(curl --retry 100 --retry-delay 10 --retry-max-time 1800 \
        -H "X-Auth-Hostqueue-APIKey: $HOST_QUEUE_TOKEN" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode hostid="$HOST_ID" \
        --data-urlencode locationid="$CONTROLLER_ID" \
        --data-urlencode accountid="$ACCOUNT_ID" \
        "${API_URL}/satellite/assign")
    set -ex
    isAssigned=$(echo "$ASSIGNMENT" | jq -r '.isAssigned' | awk '{print tolower($0)}')
    if [[ "$isAssigned" == "true" ]]; then
        break
    fi
    if [[ "$isAssigned" != "false" ]]; then
        echo "unexpected value for assign retrying"
    fi
    sleep 10
done
export HOST_ID
#STEP 5: ASSIGNMENT HAS BEEN MADE. SAVE SCRIPT AND RUN
echo "$ASSIGNMENT" | jq -r '.script' >/usr/local/bin/ibm-host-agent.sh
ASSIGNMENT_ID=$(echo "$ASSIGNMENT" | jq -r '.id')
cat <<EOF >/etc/satelliteflags/ibm-host-agent-vars
export HOST_ID=${HOST_ID}
export ASSIGNMENT_ID=${ASSIGNMENT_ID}
EOF
chmod 0600 /etc/satelliteflags/ibm-host-agent-vars
chmod 0700 /usr/local/bin/ibm-host-agent.sh
cat <<EOF >/etc/systemd/system/ibm-host-agent.service
[Unit]
Description=IBM Host Agent Service
After=network.target
[Service]
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/usr/local/bin/ibm-host-agent.sh
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
chmod 0644 /etc/systemd/system/ibm-host-agent.service
systemctl daemon-reload
systemctl start ibm-host-agent.service
touch "$HOST_ASSIGN_FLAG"
