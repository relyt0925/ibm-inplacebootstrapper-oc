# IN PLACE BOOTSTRAPPER SYSTEM OUTLINE

This doc provides a high level overview of the in place bootstrapping/upgrade system for upgrading RHCOS/RHEL machines for IBM Satellite. There is also a visual diagram at [Hypershift-Coreos-Onprem-pooling.drawio.svg](./Hypershift-Coreos-Onprem-pooling.drawio.svg)

1) A user decides they want to initiate a upgrade of a node in a cluster. The node is cordoned and they will proceed to label the node with.
```
ibm-cloud.kubernetes.io/ipb-schedule=true
```

2) A secret is created that contains the following information based on the OS

RHCOS:
- Ignition url
- Ignition auth token
- CA Cert to validate ignition urls

RHEL:
- Bootstrap payload url (ultimately download bash+ansible payload that will configure node with kubelet/cri-o/etc from here.)
- Bootstrap payload auth token
- WorkerID, ClusterID, Region (payload tied to specific worker and generated on API call)

*Note: IBM Satellite also includes extra data for auth and the URL endpoint for IBM Cloud APIs to report progress of the bootstrapping process


2) The ipb-daemonset will schedule a pod to that node (based off the node selector). The pod will proceed to first validate that all necessary “bootstrapping dependencies” are in place. It references and uses the above secret in the validation process as well. The key dependencies are listed below

RHCOS:
- Ignition endpoint can be contacted and download ignition payload
- Registry can be contacted

RHEL:
- Registry can be contacted
- Red Hat Mirrors can be contacted (yum commands ran)
- Bootstrap payload can be downloaded (calls bootstrap API with auth and ensures payload downloaded)
  
*Note: IBM Satellite also verifies IBM APIs can be called that are used to track “bootstrapping progress”.

3) Once all verification passes: automation is ran that will run the “automation” that configures the machine with kube components (cri-o, kubelet, etc). The key automation steps for each OS is shown below

RHCOS:
- Download ignition data from Ignition server and persist at specific file
- Extracts the machine-config-daemon from the release image (found by analyzing ignition data)
- Adds a couple key files to the ignition-data returned from the ignition server that will allow it to be persisted by the machine-config-daemon firstboot-complete-machineconfig run.
    - /etc/kubernetes/kubeconfig and /etc/machine-config-daemon/node-annotations.json
- Runs machine-config-daemon firstboot-complete-machineconfig which will persist ignition data and reboot node
- Node boots up with new config and is complete

RHEL:
- Download bootstrap payload from bootstrap url
- Execute bash script + ansible payload. Key steps of that are below
    - Configure base image without kube components
        - Yum updates to update packages/kernel
        - Ensure necessary CIS configs applied to node for auditing purposes
        - Ensure logrotate, syslog config files, etc setup on node
        - Other config like sysctls, etc applied for performance
    - Reboots machine to get those to take affect
    - Then runs configuration to kube components. This is mainly the kubelet and cri-o. Includes laying down necessary config to that node like kubeconfigs, kubelet confs, etc.
- Process ends with node a functioning member
  
*Note: In IBM Satellite: progress of this process reported to IBM Cloud APIs throughout the process to track progress.

4) Once nodes complete bootstrapping: automation ensures node labels/taints/etc applied to machines. ipb label is removed BEFORE node boots kubelet to ensure IPB doesn't double schedule.
   
*For IBM Satellite: these configs are stored in internal database and microservice references those, uses admin kubeconfig, and applies on node

