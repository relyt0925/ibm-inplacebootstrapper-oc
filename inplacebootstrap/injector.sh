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
REGION=$(echo "${USERDATA}" | jq -r .region)
BOOTSTRAP_URL=$(echo "${USERDATA}" | jq -r .bootstrap_url)
WORKER_ID=$(echo "${USERDATA}" | jq -r .workerid)
CLUSTER_ID=$(echo "${USERDATA}" | jq -r .clusterid)
ONE_TIME_PASSWORD=$(echo "${USERDATA}" | jq -r .bootstrap_secret)
BASE_FILE_TO_CHECK="/tmp/bootstrap/bootstrap_base_openshift_4.sh"
export REGION
export BOOTSTRAP_URL
export WORKER_ID
export CLUSTER_ID
export ONE_TIME_PASSWORD

echo "testing talking to mirrors to ensure mirrors are still functioning"
nsenter -t 1 -m -u -i -n -p -- yum update wget -y
echo "testing bootstrap curl before rebooting"
rm -rf /tmp/bootstrap
mkdir -p /tmp/bootstrap
cd /tmp/bootstrap
curl --retry 100 --retry-delay 10 --retry-max-time 1800 \
	-G "$BOOTSTRAP_URL" \
	-H "Content-Type: application/x-www-form-urlencoded" \
	-H "X-One-Time-Password: $ONE_TIME_PASSWORD" \
	-H "X-Region: $REGION" \
	-H "Cache-Control: no-store" \
	--data-urlencode workerid="$WORKER_ID" \
	--data-urlencode clusterid="$CLUSTER_ID" \
	>bootstrap.tar
if tar -xvf bootstrap.tar; then
	if [[ -f "$BASE_FILE_TO_CHECK" ]]; then
		echo "Fetched and untarred bootstrap.tar successfully"
	else
		echo "Failed to download restarting the in place bootstrapper pod"
		sleep 10
		exit 1
	fi
fi
echo "injecting in place bootstrap script onto host"
cp /usr/local/bin/ipb.sh /host/usr/local/bin/ipb.sh
echo "launching in place bootstrap script on host"
nsenter -t 1 -m -u -i -n -p -- nohup /bin/bash /usr/local/bin/ipb.sh &
sleep 5000
