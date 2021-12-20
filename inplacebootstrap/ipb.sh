#!/usr/bin/env bash
set -x
echo "disabling all openshift systemd unit files to allow clean rebootstrapping"
systemctl disable kubelet.service
systemctl stop kubelet.service
rm -f /usr/lib/systemd/system/kubelet.service
systemctl disable crio.service
systemctl stop crio.service
systemctl disable decrypt-docker.service
systemctl stop decrypt-docker.service
rm -f /etc/systemd/system/decrypt-docker.service
systemctl disable pull-dependencies.service
systemctl stop pull-dependencies.service
rm -f /etc/systemd/system/pull-dependencies.service
systemctl disable cleanup-keys.service
systemctl stop cleanup-keys.service
rm -f /etc/systemd/system/cleanup-keys.service
systemctl daemon-reload
echo "disabling secondary disk mounts if they exist"
sed -i '/\/var\/data/d' /etc/fstab
echo "disabling sysctl settings that cause errors until kube components start (will get readded in bootstrap)"
sed -i '/net.ipv4.conf.tunl0.rp_filter=2/d' /etc/sysctl.conf
echo "permit root login so users can gather debug info if bootstrap fails"
sed -i 's/PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
echo "removing stale data that will cause bootstrap to error or not rerun"
rm -f /etc/armadabootstrap/imaging.flag
rm -f /var/log/firstboot.flag
rm -f /var/log/bootstrap_base.flag
rm -f /var/log/pods
rm -f /var/lib/kubelet
rm -f /var/lib/docker
rm -f /var/lib/dockershim
rm -f /var/run/containers/storage
rm -f /var/lib/containers/storage
rm -f /var/tmp
rm -rf /etc/cni
echo "rebooting to retrigger bootstrap"
reboot
