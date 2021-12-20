#!/usr/bin/env bash
set -x
echo "disabling all openshift systemd unit files to allow clean rebootstrapping"
systemctl disable kubelet.service
systemctl stop kubelet.service
rm -f /usr/lib/systemd/system/kubelet.service
systemctl disable crio.service
systemctl stop crio.service
systemctl disable ibm-report-bootid.service
systemctl stop ibm-report-bootid.service
systemctl enable ibm-host-agent.service
systemctl daemon-reload

echo "disabling secondary disk mounts if they exist"
sed -i '/\/var\/data/d' /etc/fstab
echo "disabling sysctl settings that cause errors until kube components start (will get readded in bootstrap)"
sed -i '/net.ipv4.conf.tunl0.rp_filter=2/d' /etc/sysctl.conf
echo "permit root login so users can gather debug info if bootstrap fails"
sed -i 's/PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config

echo "removing stale data that will cause bootstrap to error or not rerun"
rm -rf /var/log/pods
rm -rf /var/lib/kubelet
rm -rf /var/lib/docker
rm -rf /var/lib/dockershim
rm -rf /var/run/containers/storage
rm -rf /var/lib/containers/storage
rm -rf /var/tmp/etc/ignition-machine-config-encapsulated.json
rm -rf /etc/cni
rm -rf /etc/satelliteflags/hostbootstrapinitatedflag
rm -rf /etc/kubernetes/kubeconfig
rm -rf /etc/machine-config-daemon/node-annotations.json
rm -rf /tmp/ignition-machine-config-encapsulated.json
rm -rf /etc/sysconfig/rootdirpermissionlogicexecuted
rm -rf /etc/sysconfig/ibmsecondarystorage/ext4
rm -rf /etc/sysconfig/atdirinitialized
rm -rf /etc/sysconfig/ibmsecondarystorage/setupexecuted
rm -rf /etc/sysconfig/ibmsecondarystorage/ibmsecondarystorageenvfile
rm -rf /etc/sysconfig/ibmsecondarystorage/luks
rm -rf /etc/sysconfig/ibmmachinemetadataenvfile

echo "rebooting to retrigger host agent"
reboot
