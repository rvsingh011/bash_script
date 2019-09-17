#!/bin/bash

printenv



# TODO Remove verbose once verified in stage.
set -e
#kube_dir=""
#apikey=""
namespace=schematics

function finish {
    echo "** Removing pod's secret"
    #kubectl delete secret ibm-content-mgmt-script-pod-secret-${JOB_ID} -n ${JOB_NAMESPACE} > /dev/null 2>&1 || true
    #ic iam api-key-delete OC_TEMP -f > /dev/null 2>&1 || true
    echo "deleting KUBECONFIG details..."
    #rm -rf $kube_dir/
    ic iam api-key-delete OC_TEMP -f > /dev/null 2>&1
    
}
trap finish 0 1 2 3 6 15



_init()
{
    printf "%s" "$CONFIG_JSON" > /home/appuser/.bluemix/config.json
    #printf "%s" "$CONFIG_JSON" > /root/.bluemix/config.json
    cat /home/appuser/.bluemix/config.json
    #cat /root/.bluemix/config.json
    export IAM_END_POINT="https://containers.cloud.ibm.com"
    curl -X GET "${IAM_END_POINT}/global/v1/clusters/${NAME}/config" -H "accept: application/json" -H "Authorization: ${IC_IAM_TOKEN}" -H "X-Auth-Refresh-Token: ${IC_IAM_REFRESH_TOKEN}" -o /tmp/kubeconfig.zip
    chmod +x /tmp/kubeconfig.zip
    unzip -l /tmp/kubeconfig.zip >> /tmp/kube_conf_dtls.txt
    unzip /tmp/kubeconfig.zip -d /tmp/
    cat /tmp/kube_conf_dtls.txt | grep ".yml" | awk 'FNR == 1 {print $4}'
    kube_dir=/tmp/$(cat /tmp/kube_conf_dtls.txt | awk 'FNR == 4 {print $4}')
    KUBECONFIG=/tmp/$(cat /tmp/kube_conf_dtls.txt | grep ".yml" | awk 'FNR == 1 {print $4}')
    export KUBECONFIG=$KUBECONFIG
    apikey=$(ibmcloud iam api-key-create OC_TEMP -d "temp api key for OC login" | grep "API Key" | tr -s " " | cut -d" " -f3)

    echo "apiKey : " $apikey
    oc_server=$(cat $KUBECONFIG | grep "server" | awk 'FNR == 1 {print $2}')
    oc login -u apikey -p $apikey --server=$oc_server || true
    #ic iam api-key-delete OC_TEMP -f > /dev/null 2>&1
    create_namepsace
    
}

create_namepsace()
{
    namespace="schematics"
    schematics_namespace=$(kubectl get namespace | grep $namespace | awk 'FNR == 1 {print $1}')
    
    if [[ $schematics_namespace == *$namespace* ]]; then
        echo "Debug : schematics namespace available."
    else
        echo "Debug : schematics namespace not available... creating one"
        kubectl create namespace $namespace
    fi
    
}

_init


sleep 30000
