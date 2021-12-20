#!/usr/bin/env bash

if grep -qi "coreos" </host/etc/redhat-release; then
	/usr/local/bin/rhcos-injector.sh
elif grep -qi "maipo" </host/etc/redhat-release; then
	/usr/local/bin/injector.sh
elif grep -qi "ootpa" </host/etc/redhat-release; then
	/usr/local/bin/injector.sh
else
	echo "Operating System not detected. Assuming default behavior for backward compatibility"
	/usr/local/bin/injector.sh
fi
