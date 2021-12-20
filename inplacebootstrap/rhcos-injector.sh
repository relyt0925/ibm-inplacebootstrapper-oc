#!/usr/bin/env bash
set -ex
_term() {
	echo "Caught SIGTERM signal! Proceeding to exit process"
	exit 0
}
trap _term SIGTERM
#Step 1: fetch bootstrap metadata from cluster

echo "creating bootstrap metadata file on host"
kubectl get secret -n kube-system "ibm-ipb-${NODE_NAME}" -o jsonpath='{.data.bootstrap}' >/tmp/bootstrapdata64
# shellcheck disable=SC2002
cat /tmp/bootstrapdata64 | base64 -d >/tmp/bootstrapdata
mkdir -p /host/etc/armada/
cp -f /tmp/bootstrapdata /host/etc/armada/bootstrap.json
echo "validating that bootstrap can occur before rebooting"
USERDATA=$(cat /host/etc/armada/bootstrap.json)
#Step 2: test that the secret results in the proper curl
BOOTSTRAP_URL=$(echo "${USERDATA}" | jq -r .bootstrap_url)
IGNITION_URL=$(echo "${USERDATA}" | jq -r .ignition_url)
IGNITION_TOKEN=$(echo "${USERDATA}" | jq -r .ignition_token)
CA_CERT=$(echo "${USERDATA}" | jq -r .ca_cert)
UPIADD_PASSWORD=$(echo "${USERDATA}" | jq -r .bootstrap_secret)
export BOOTSTRAP_URL
export IGNITION_URL
export IGNITION_TOKEN
export UPIADD_PASSWORD

#Step 3: test that the ignition server is reachable
echo "testing ignition is reachable before rebooting"
echo -e "${CA_CERT}" >/tmp/ca_cert.pem
chmod 0600 /tmp/ca_cert.pem
HTTP_RESPONSE=$(curl --write-out "HTTPSTATUS:%{http_code}" --cacert "/tmp/ca_cert.pem" --retry 100 --retry-delay 10 --retry-max-time 1800 -s -k -H "Authorization: ${IGNITION_TOKEN}" "${IGNITION_URL}")
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | awk -F: '/.*HTTPSTATUS:([0-9]{3})$/ { print $2 }')
if [[ "$HTTP_STATUS" -eq 000 ]]; then
	echo "ignition unreachable"
	exit 1
elif [[ "$HTTP_STATUS" -ne 200 ]]; then
	echo "ignition bad return code"
	exit 1
fi

#Step 4: test that armada-bootstrap is reachable
echo "testing bootstrap is reachable before rebooting"
HTTP_RESPONSE=$(curl --write-out "HTTPSTATUS:%{http_code}" --retry 100 --retry-delay 10 --retry-max-time 1800 "$BOOTSTRAP_URL")
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | awk -F: '/.*HTTPSTATUS:([0-9]{3})$/ { print $2 }')
if [[ "$HTTP_STATUS" -eq 000 ]]; then
	echo "bootstrap unreachable"
	exit 1
fi

echo "replacing OTPs in assign script"
sed -i "s/UPIADD_PASSWORD=.*/UPIADD_PASSWORD=\"$UPIADD_PASSWORD\"/g" /host/usr/local/bin/ibm-host-agent.sh
sed -i "s/IGNITION_TOKEN=.*/IGNITION_TOKEN=\"$IGNITION_TOKEN\"/g" /host/usr/local/bin/ibm-host-agent.sh
# Using '~' as delimiter to avoid issues with '/' characters
sed -i "s~IGNITION_URL=.*~IGNITION_URL=\"$IGNITION_URL\"~g" /host/usr/local/bin/ibm-host-agent.sh
# Replace CA_CERT multiline variable
echo -n "CA_CERT=\"${CA_CERT}" >/tmp/temp.txt
sed -i '/CA_CERT=/,/\"/{//!d}' /host/usr/local/bin/ibm-host-agent.sh
sed -i -e "/CA_CERT=.*/r /tmp/temp.txt" -e "//d" /host/usr/local/bin/ibm-host-agent.sh

echo "injecting in place bootstrap script onto host"
cp /usr/local/bin/rhcos-ipb.sh /host/usr/local/bin/rhcos-ipb.sh
echo "launching in place bootstrap script on host"
nsenter -t 1 -m -u -i -n -p -- nohup /bin/bash /usr/local/bin/rhcos-ipb.sh &
sleep 5000
