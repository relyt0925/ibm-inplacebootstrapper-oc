Key User Stories

As a user: I want to be able to fully control the upgrade process of the nodes of my cluster. I want to have a clear notification when updates are available and the status of the upgrade process on an individual node basis. With this: I will proceed to perform the upgrade of my cluster based on the advance knowledge I have of the applications running in it (some application "stops" and "migrations" aren't as simple as issuing a kubectl drain.). I need to be able to control down to the level or initiating the process for each individual node.


Some key things this enabled:
Some teams (internally at IBM): have to submit for auditing purposes change requests that are approved by a separate SRE team before performing actions. It has to define the entire scope of the change. Without having control over individual node upgrades: this would not be possible.

Allows teams to perform "extra application specific verification" after a node upgrade before moving to the next node upgrade. For example maybe a team wants to run a small set of application level smoke tests after each upgrade to ensure things are still ok functionally. They might also want to schedule a test application to an upgraded node and ensure it still runs appropriately and there are no regressions with the application at the upgraded version.


The key APIs that IBM Customers are used to are

```
Tylers-MacBook-Pro:armada-cruiser-automated-recovery tylerlisowski$ bx cs workers --cluster c707mmi20updvmjlm9v0
OK
ID                                                       Public IP      Private IP       Flavor               State    Status   Zone    Version   
test-c707mmi20updvmjlm9v0-bpvg1640004-default-0000019a   169.63.53.65   10.241.170.18    b3c.4x16.encrypted   normal   Ready    dal12   4.7.40_1544_openshift*   
test-c707mmi20updvmjlm9v0-bpvg1640004-default-000002b7   169.63.53.8    10.241.170.33    b3c.4x16.encrypted   normal   Ready    dal12   4.7.40_1544_openshift*   
test-c707mmi20updvmjlm9v0-bpvg1640004-default-000003a0   169.63.53.54   10.241.170.139   b3c.4x16.encrypted   normal   Ready    dal12   4.7.40_1544_openshift*

* To update to 4.8.24_1539_openshift version, run 'ibmcloud ks worker update'. Review and make any required version changes before you update: 'https://ibm.biz/upworker'

Processing test-c707mmi20updvmjlm9v0-bpvg1640004-default-0000019a...
Processing on test-c707mmi20updvmjlm9v0-bpvg1640004-default-0000019a complete.
OK

Tylers-MacBook-Pro:armada-cruiser-automated-recovery tylerlisowski$ bx cs workers --cluster c707mmi20updvmjlm9v0
OK
ID                                                       Public IP      Private IP       Flavor               State            Status   Zone    Version   
test-c707mmi20updvmjlm9v0-bpvg1640004-default-0000019a   169.63.53.65   10.241.170.18    b3c.4x16.encrypted   reload_pending   -        dal12   4.7.40_1544_openshift --> 4.8.24_1539_openshift (pending)   
test-c707mmi20updvmjlm9v0-bpvg1640004-default-000002b7   169.63.53.8    10.241.170.33    b3c.4x16.encrypted   normal           Ready    dal12   4.7.40_1544_openshift*   
test-c707mmi20updvmjlm9v0-bpvg1640004-default-000003a0   169.63.53.54   10.241.170.139   b3c.4x16.encrypted   normal           Ready    dal12   4.7.40_1544_openshift*   

* To update to 4.8.24_1539_openshift version, run 'ibmcloud ks worker update'. Review and make any required version changes before you update: 'https://ibm.biz/upworker'


Tylers-MacBook-Pro:armada-cruiser-automated-recovery tylerlisowski$ bx cs workers --cluster c707mmi20updvmjlm9v0
OK
ID                                                       Public IP      Private IP       Flavor               State    Status   Zone    Version   
test-c707mmi20updvmjlm9v0-bpvg1640004-default-0000019a   169.63.53.65   10.241.170.18    b3c.4x16.encrypted   normal   Ready    dal12   4.8.24_1539_openshift   
test-c707mmi20updvmjlm9v0-bpvg1640004-default-000002b7   169.63.53.8    10.241.170.33    b3c.4x16.encrypted   normal   Ready    dal12   4.7.40_1544_openshift*   
test-c707mmi20updvmjlm9v0-bpvg1640004-default-000003a0   169.63.53.54   10.241.170.139   b3c.4x16.encrypted   normal   Ready    dal12   4.7.40_1544_openshift*   

* To update to 4.8.24_1539_openshift version, run 'ibmcloud ks worker update'. Review and make any required version changes before you update: 'https://ibm.biz/upworker'
```

These APIs ultimately trigger microservices that automate the high level steps outlined in the SYSTEMOUTLINE.md doc.

