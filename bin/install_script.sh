#!/bin/bash

# TODO Remove verbose once verified in stage.
set -xe
printenv

#kube_dir=""
#apikey=""
namespace=schematics
ibm_ks_endpoint=""
is_prod=false
api_endpoint=""
iam_endpoint=""
cloud_name=""

# Catch block, om error
# cleaning up all generated details.
function finish {
    echo "** Removing pod's secret"
    #kubectl delete secret ibm-content-mgmt-script-pod-secret-${JOB_ID} -n ${JOB_NAMESPACE} > /dev/null 2>&1 || true
    echo "deleting KUBECONFIG details..."
    #rm -rf $kube_dir/
    ic iam api-key-delete OC_TEMP -f > /dev/null 2>&1
    #rm -f /tmp/config.json
    #rm -f /tmp/iam_payload.json
    #rm -f /home/appuser/.bluemix/config.json
    #rm -f /home/nobody/.bluemix/config.json
    #rm -f /tmp/kube_conf_dtls.txt
    #rm -rf /tmp/*.*
    
}
trap finish 0 1 2 3 6 15

# Consstructing the config.json from the IAM_TOKEN which is available as env variable.
# 1. Decode jwt json payload details from IAM_TOKEN
# 2. Replace the generaed values into the config.json template.
# 3. Copy the config.json to /home/appuser/.bluemix
# 4. Also put the copy into /home/nobofy/.bluemix (logically this is not required, 
#      but sometime IAM autheication fails as it expects the file in this location)
function 1_build_config_json
{
    #TODO remove echo statements after the testing
    iam_payload=$(echo -n "$IC_IAM_TOKEN" | cut -d "." -f2)
    rm -f /tmp/iam_payload.json
    echo "$iam_payload" | base64 -d  | jq '.' >> /tmp/iam_payload.json
    account_id=$(cat /tmp/iam_payload.json | jq '.account.bss' | tr -d '"')
    echo "account id : $account_id"
    account_name=$(cat /tmp/iam_payload.json | jq '.name'| tr -d '"')
    echo "account_name  : $account_name"
    account_owner=$(cat /tmp/iam_payload.json | jq '.email'| tr -d '"')
    echo "account_owner  : $account_owner"
    iss_api=$(cat /tmp/iam_payload.json | jq '.iss')
    echo "iss_api : $iss_api"
    
    if [[ $iss_api == *test* ]]; then
        echo "It is stage evn."
        is_prod=false
        ibm_ks_endpoint="https://containers.test.cloud.ibm.com"
        api_endpoint="https://test.cloud.ibm.com"
        iam_endpoint="https://iam.test.cloud.ibm.com"
        cloud_name="staging"
    else
        echo "It is prod evn."
        is_prod=true
        ibm_ks_endpoint="https://containers.cloud.ibm.com"
        api_endpoint="https://cloud.ibm.com"
        iam_endpoint="https://iam.cloud.ibm.com"
        cloud_name="bluemix"
        
    fi
    
    echo "ibm_ks_endpoint : $ibm_ks_endpoint"
    echo "api_endpoint : $api_endpoint"
    echo "cloud_name : $cloud_name"
    rm -f /tmp/config.json
    
cat <<'EOF' > /tmp/config.json
{
        "APIEndpoint": "api_endpoint",
        "Account": {
          "GUID": "account_id",
          "Name": "account_name",
          "Owner": "account_owner"
        },
        "CFEEEnvID": "",
        "CFEETargeted": false,
        "CLIInfoEndpoint": "",
        "CheckCLIVersionDisabled": false,
        "CloudName": "cloud_name",
        "CloudType": "public",
        "ColorEnabled": "",
        "ConsoleEndpoint": "api_endpoint",
        "HTTPTimeout": 0,
        "IAMEndpoint": "iam_endpoint",
        "IAMRefreshToken": "IC_IAM_REFRESH_TOKEN",
        "IAMToken": "IC_IAM_TOKEN",
        "Locale": "",
        "PluginRepos": [
          {
            "Name": "IBM Cloud",
            "URL": "https://plugins.cloud.ibm.com"
          }
        ],
        "Region": "",
        "RegionID": "",
        "ResourceGroup": {
          "Default": false,
          "GUID": "",
          "Name": "",
          "QuotaID": "",
          "State": ""
        },
        "SDKVersion": "0.3.0",
        "SSLDisabled": false,
        "Trace": "",
        "UpdateCheckInterval": 0,
        "UpdateNotificationInterval": 0,
        "UpdateRetryCheckInterval": 0,
        "UsageStatsDisabled": false
}
EOF
    
    
    
    sed -i "s%api_endpoint%$api_endpoint%g" /tmp/config.json
    sed -i "s/account_id/$account_id/g" /tmp/config.json
    sed -i "s/account_name/$account_name/g" /tmp/config.json
    sed -i "s/account_owner/$account_owner/g" /tmp/config.json
    sed -i "s/cloud_name/$cloud_name/g" /tmp/config.json
    sed -i "s%iam_endpoint%$iam_endpoint%g" /tmp/config.json
    sed -i "s/IC_IAM_REFRESH_TOKEN/$IC_IAM_REFRESH_TOKEN/g" /tmp/config.json
    sed -i "s/IC_IAM_TOKEN/$IC_IAM_TOKEN/g" /tmp/config.json
    cat /tmp/config.json
    cp /tmp/config.json /home/appuser/.bluemix/
    mkdir -p /home/nobody/.bluemix/
    cp /tmp/config.json /home/nobody/.bluemix/

    
}

# export remote cluster config 
#   1. using curl endpoint to download the clsuter_config.zip with IC_IAM_TOKEN, IC_IAM_REFRESH_TOKEN (available in env)
#       with remote cluster details (from payload)
#   2. export the downloaded config.
function 2_export_kube_config()
{
    curl -X GET "${ibm_ks_endpoint}/global/v1/clusters/${NAME}/config" -H "accept: application/json" -H "Authorization: ${IC_IAM_TOKEN}" -H "X-Auth-Refresh-Token: ${IC_IAM_REFRESH_TOKEN}" -o /tmp/kubeconfig.zip
    chmod +x /tmp/kubeconfig.zip
    rm -f /tmp/kube_conf_dtls.txt
    unzip -l /tmp/kubeconfig.zip >> /tmp/kube_conf_dtls.txt
    unzip /tmp/kubeconfig.zip -d /tmp/
    cat /tmp/kube_conf_dtls.txt | grep ".yml" | awk 'FNR == 1 {print $4}'
    kube_dir=/tmp/$(cat /tmp/kube_conf_dtls.txt | awk 'FNR == 4 {print $4}')
    KUBECONFIG=/tmp/$(cat /tmp/kube_conf_dtls.txt | grep ".yml" | awk 'FNR == 1 {print $4}')
    export KUBECONFIG=$KUBECONFIG
}

# TODO handle cluster_type, do this only for openshift
# OpenShift cluster login using temp api_key.
# 1. Generate temp api_key using
# 2. login to OC console, so that job can be executed.
function 3_oc_login_with_apikey()
{
    apikey=$(ibmcloud iam api-key-create OC_TEMP -d "temp api key for OC login" | grep "API Key" | tr -s " " | cut -d" " -f3)
    echo "apiKey : " $apikey
    oc_server=$(cat $KUBECONFIG | grep "server" | awk 'FNR == 1 {print $2}')
    oc login -u apikey -p $apikey --server=$oc_server || true
    #ic iam api-key-delete OC_TEMP -f > /dev/null 2>&1

}

# Creating `schematics` namespace on remote cluster.
# This namespace used for the installation, job execution.
function 4_create_namepsace()
{
    namespace="schematics"
    schematics_namespace=$(kubectl get namespace | grep $namespace | awk 'FNR == 1 {print $1}')
    
    if [[ $schematics_namespace == *$namespace* ]]; then
        kubectl get namespaces
        echo "Debug : schematics namespace available."
    else
        echo "Debug : schematics namespace not available... creating one"
        kubectl create namespace $namespace
        kubectl get namespaces
    fi
    
}

function 5_create_installer_job()
{

#TODO
# JOB name should have workspace id or name.
currnet_timestamp=`date "+%Y%m%d-%H%M%S"`
job_name="installer-"$currnet_timestamp

export NAMESPACE=schematics

cat << EOF | kubectl apply --namespace schematics -f - 
---
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  labels:
    app: ${job_name}
spec:
  backoffLimit: 6
  completions: 1
  parallelism: 1
  template:
    metadata:
      labels:
        app: ${job_name}
    spec:
      restartPolicy: Never
      containers:
      - env:
        - name: NAMESPACE 
          value: ${NAMESPACE}
        - name: TILLER_NAMESPACE
          value: ${TILLER_NAMESPACE}
        - name: INSTALL_TILLER
          value: "${INSTALL_TILLER}"
        - name: TILLER_IMAGE
          value: ${TILLER_IMAGE}
        - name: TILLER_TLS
          value: "${TILLER_TLS}"
        - name: STORAGE_CLASS
          value: ${STORAGE_CLASS}
        - name: DOCKER_REGISTRY
          value: ${DOCKER_REGISTRY}
        - name: DOCKER_USERNAME
          value: ${DOCKER_USERNAME}
        - name: DOCKER_REGISTRY_USER
          value: ${DOCKER_USERNAME}
        - name: DOCKER_REGISTRY_PASS
          value: ${DOCKER_REGISTRY_PASS}
        - name: CONSOLE_ROUTE_PREFIX
          value: ${CONSOLE_ROUTE_PREFIX}
        - name: CP4D_NGINX_RESOLVER
          value: ${CP4D_NGINX_RESOLVER}
        name: schematics-installer
        image: us.icr.io/schemtics/icp4data:1.2
        resources:
          limits:
            memory: "200Mi"
            cpu: 1
      
EOF
[[ $? -ne 0 ]] && exit 1

sleep 10
POD=$(kubectl get pods -n ${NAMESPACE} -l app=${job_name} -o jsonpath="{.items[0].metadata.name}")
echo "Waiting for ${POD} is running"
for ((retry=0;retry<=9999;retry++)); do
  oc get pod ${POD} -n ${NAMESPACE} |grep '1/1'
  [[ $? -eq 0 ]] && break
  
  # 15 min timeout
  if [[ ${retry} -eq 90 ]]; then
    echo "Timeout to wait for installer pod up and running, it could be the image pull failing."
    echo "Please use command 'kubectl get pod ${POD}' to check details"
    exit 1
  fi
  sleep 10
done

echo "Tailing the pod log"
kubectl logs -n ${NAMESPACE} --follow $POD
sleep 10
exit $(oc get pods -n ${NAMESPACE} ${POD} -o jsonpath="{.status.containerStatuses[0].state.terminated.exitCode}")

}


run_remote_job()
{
    1_build_config_json
    # this is weired, as these are already in the image but some it fails 
    ibmcloud plugin install kubernetes-service
    ibmcloud plugin install container-registry
    #chek IBMcloud login is working
    ibmcloud ks clusters
    2_export_kube_config
    3_oc_login_with_apikey
    4_create_namepsace
    5_create_installer_job
}

run_remote_job


