#!/bin/bash

set -xeuo pipefail

readonly NEXUS_HOST="alm-repos.sogei.it"
readonly NEXUS_PORT="8091"
readonly NEXUS_USERNAME="webo"
readonly OCP4_TEMPLATE="cakephp-mysql-persistent"

# Initial checks ##############
oc whoami 2>& /dev/null
[ $? -ne 0 ] && exit 1
which jq  2>& /dev/null
[ $? -ne 0 ] && exit 1
oc get -n openshift template/${OCP4_TEMPLATE} -o name 2>& /dev/null
################################


while getopts ":p:P:e:" opt; do
  case $opt in
    p)
      OCP4_PROJ="$OPTARG"
      ;;
    e)
      OCP4_ENV="$OPTARG"
      ;;
    P)
      NEXUS_PASSWORD="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

[ -z ${NEXUS_PASSWORD} ]  && exit 1
[ -z ${OCP4_PROJ}      ]  && exit 1
[ -z ${OCP4_ENV}       ]  && exit 1

# OCP4 deve consentire uso del Docker Registry ${OCP4_PROJ}:${OCP4_ENV}
oc get -o json  image.config.openshift.io/cluster | jq  "' .spec.registrySources.allowedRegistries[] | contains(\"${OCP4_PROJ}:${OCP4_ENV}\")'" | egrep -q true
[ $? -ne 0 ] && exit 1

oc -n ${OCP4_PROJ} create secret docker-registry ${NEXUS_HOST} \
  --docker-server=${NEXUS_HOST}:${NEXUS_PORT} \
  --docker-username=${NEXUS_USERNAME} \
  --docker-password=${NEXUS_PASSWORD}

oc -n ${OCP4_PROJ} secrets link builder  ${NEXUS_HOST}
oc -n ${OCP4_PROJ} secrets link deployer ${NEXUS_HOST} --for=pull

#oc -n ${OCP4_PROJ} import-image nexus-cakephp-mysql-persistent \
    --from=${NEXUS_HOST}:${NEXUS_PORT}/ocp/${OCP4_ENV}/${OCP4_PROJ}/cakephp-mysql-persistent  

#oc -n ${OCP4_PROJ} patch  \

#oc -n ${OCP4_PROJ}  rollout latest cakephp-mysql-persistent

#oc -n ${OCP4_PROJ}  logs -f deploymentconfig.apps.openshift.io/cakephp-mysql-persistent


