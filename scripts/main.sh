#!/bin/bash

set -xeuo pipefail

readonly NEXUS_HOST="alm-repos.sogei.it"
readonly NEXUS_PORT="8091"
readonly NEXUS_USERNAME="webo"

[ ! -s ${NEXUS_PASSWORD} ]  && exit 1
[ ! -s ${OCP4_PROJ}      ]  && exit 1
[ ! -s ${OCP4_ENV}       ]  && exit 1

oc -n ${OCP4_PROJ} create secret docker-registry ${NEXUS_HOST} \
  --docker-server=${NEXUS_PORT}:${NEXUS_HOST} \
  --docker-username=${NEXUS_USERNAME} \
  --docker-password=${NEXUS_PASSWORD}

oc -n ${OCP4_PROJ} secrets link builder  alm-repos.sogei.it
oc -n ${OCP4_PROJ} secrets link deployer alm-repos.sogei.it --for=pull

oc -n ${OCP4_PROJ} import-image nexus-cakephp-mysql-persistent \
    --from=alm-repos.sogei.it:8091/ocp/${OCP4_ENV}/${OCP4_PROJ}/cakephp-mysql-persistent  \

oc -n ${OCP4_PROJ} patch  \

oc -n ${OCP4_PROJ}  rollout latest cakephp-mysql-persistent

oc -n ${OCP4_PROJ}  logs -f deploymentconfig.apps.openshift.io/cakephp-mysql-persistent


