#!/bin/bash

# Inspired by: https://www.redhat.com/en/blog/pushing-application-images-to-an-external-registry

set -xeuo pipefail

readonly NEXUS_HOST="alm-repos.sogei.it"
readonly NEXUS_PORT="8091"
readonly NEXUS_USERNAME="webo"
readonly OCP4_TEMPLATE="cakephp-mysql-persistent"
readonly NEXUS_IS="nexus-${OCP4_TEMPLATE}"

# Initial checks ##############
oc whoami >/dev/null 2>&1
[ $? -ne 0 ] && exit 1  
which jq  >/dev/null 2>&1
[ $? -ne 0 ] && exit 1
oc get -n openshift template/${OCP4_TEMPLATE} -o name > /dev/null 2>&1
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


# OCP4 deve consentire uso del Docker Registry ${NEXUS_HOST}:${NEXUS_PORT}
# oc get -o json image.config.openshift.io/cluster | jq  ' .spec.registrySources.allowedRegistries[] | contains("alm-repos.sogei.it:8091")' | egrep -q true
oc get -o json   image.config.openshift.io/cluster                                                   | \
  jq  ' .spec.registrySources.allowedRegistries[] | contains(($ENV.NEXUS_HOST+":"+$ENV.NEXUS_PORT))' | \
  egrep -q true
[ $? -ne 0 ] && echo "Il Nexus registry ${NEXUS_HOST}:${NEXUS_PORT} non è esplicitamente abilitato in questo OCP" && exit 1

set +e
oc get project -o name | egrep ${OCP4_PROJ} 2>&1 >/dev/null
[ $? -eq 0 ] && echo "Il proj ${OCP4_PROJ} esiste già" && exit 1 
set -e


### MAIN ###

oc new-project ${OCP4_PROJ}

oc -n ${OCP4_PROJ} new-app --template=${OCP4_TEMPLATE}

# https://docs.openshift.com/container-platform/4.11/openshift_images/image-streams-manage.html#images-allow-pods-to-reference-images-from-secure-registries_image-streams-managing
oc -n ${OCP4_PROJ} create secret docker-registry ${NEXUS_HOST} \
  --docker-server=${NEXUS_HOST}:${NEXUS_PORT} \
  --docker-username=${NEXUS_USERNAME} \
  --docker-password=${NEXUS_PASSWORD}

oc -n ${OCP4_PROJ} logs bc/${OCP4_TEMPLATE} -f

oc -n ${OCP4_PROJ} secrets link builder  ${NEXUS_HOST}

oc -n ${OCP4_PROJ} secrets link deployer ${NEXUS_HOST} --for=pull

# oc patch quota "my-object" -p "{\"spec\":{\"hard\":{\"$OS_OBJECT\":\"$VALUE\"}}}"
oc  patch bc cakephp-mysql-persistent -p "{\"spec\":{\"output\":{\"to\":{\"kind\":\"DockerImage\",\"name\":\"${NEXUS_HOST}:${NEXUS_PORT}/ocp/${OCP4_ENV}/${OCP4_PROJ}/${OCP4_TEMPLATE}:latest\"}}}}"

oc start-build -F ${OCP4_TEMPLATE}

oc -n ${OCP4_PROJ} import-image ${NEXUS_IS} \
    --scheduled=true --confirm                                 \
    --from=${NEXUS_HOST}:${NEXUS_PORT}/ocp/${OCP4_ENV}/${OCP4_PROJ}/${OCP4_TEMPLATE}:latest  
#oc import-image nexus --scheduled=true --confirm --from=alm-repos.sogei.it:8091/ocp/coll/martinellis-cakephp/cakephp-mysql-persistent:latest

#oc -n ${OCP4_PROJ} get dc/cakephp-mysql-persistent -o yaml | yq .spec.triggers[0].imageChangeParams.from.name

# $ oc get dc/cakephp-mysql-persistent -o yaml | yq .spec.triggers[0].imageChangeParams.from.name
# cakephp-mysql-persistent:latest

# https://github.com/kubernetes/kubernetes/issues/63247#issuecomment-419783719
oc -n ${OCP4_PROJ} patch dc/${OCP4_TEMPLATE} --type json -p "
- op: replace
  path: /spec/triggers/0/imageChangeParams/from/name
  value: ${NEXUS_IS}:latest
"

oc logs -f dc/cakephp-mysql-persistent



