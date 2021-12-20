IPB_IMAGENAME='armada-master/ibm-inplacebootstrapper-oc'

.PHONY: buildipb
buildipb:
	@docker build \
      --build-arg REPO_SOURCE_URL="${REPO_SOURCE_URL}" \
      --build-arg BUILD_URL="${BUILD_URL}" \
      --build-arg ARTIFACTORY_API_KEY="${ARTIFACTORY_API_KEY}" \
      -t ${IPB_IMAGENAME}\:${TRAVIS_COMMIT} -f Dockerfile . \

.PHONY: shellcheck
shellcheck:
	shellcheck inplacebootstrap/injector.sh
	shellcheck inplacebootstrap/ipb.sh

.PHONY: runanalyzedeps
runanalyzedeps:
	@docker build --rm --build-arg ARTIFACTORY_API_KEY="${ARTIFACTORY_API_KEY}"  -t armada/analyze-deps -f Dockerfile.dependencycheck .
	docker run -v `pwd`/dependency-check:/results armada/analyze-deps

.PHONY: analyzedeps
analyzedeps:
	/tmp/dependency-check/bin/dependency-check.sh --enableExperimental --log /results/logfile --out /results --disableAssembly \
 		--suppress /src/dependency-check/suppression-file.xml --format JSON --prettyPrint --failOnCVSS 0 --scan /src \
 		  --cveUrlBase "https://freedumbytes.gitlab.io/setup/nist-nvd-mirror/nvdcve-1.1-%d.json.gz" --cveUrlModified "https://freedumbytes.gitlab.io/setup/nist-nvd-mirror/nvdcve-1.1-modified.json.gz"

