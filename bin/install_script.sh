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

function finish {
    echo "** Removing pod's secret"
    #kubectl delete secret ibm-content-mgmt-script-pod-secret-${JOB_ID} -n ${JOB_NAMESPACE} > /dev/null 2>&1 || true
    #ic iam api-key-delete OC_TEMP -f > /dev/null 2>&1 || true
    echo "deleting KUBECONFIG details..."
    #rm -rf $kube_dir/
    ic iam api-key-delete OC_TEMP -f > /dev/null 2>&1
    rm -f /tmp/config.json
    rm -f /tmp/iam_payload.json
    rm -f /home/appuser/.bluemix/config.json
    rm -f /home/nobody/.bluemix/config.json
    rm -f /tmp/kube_conf_dtls.txt
    rm -rf /tmp/*.*
    
}
trap finish 0 1 2 3 6 15

function build_config_json
{
    iam_payload=$(echo -n "$IC_IAM_TOKEN" | cut -d "." -f2)
    rm -f /tmp/iam_payload.json
    echo "$iam_payload" | base64 -d  | jq '.' >> /tmp/iam_payload.json
    account_id=$(cat /tmp/iam_payload.json | jq '.account.bss')
    echo "account id : $account_id"
    account_name=$(cat /tmp/iam_payload.json | jq '.name')
    echo "account_name  : $account_name"
    account_owner=$(cat /tmp/iam_payload.json | jq '.email')
    echo "account_owner  : $account_owner"
    iss_api=$(cat /tmp/iam_payload.json | jq '.iss')
    echo "iss_api : $iss_api"
    
    if [[ $iss_api == *test* ]]; then
        echo "It is stage evn."
        is_prod=false
        ibm_ks_endpoint="https://containers.test.cloud.ibm.com/global"
        api_endpoint="https://test.cloud.ibm.com"
        iam_endpoint="https://iam.test.cloud.ibm.com"
        cloud_name="staging"
    else
        echo "It is prod evn."
        is_prod=true
        ibm_ks_endpoint="https://containers.cloud.ibm.com/global"
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
    cp /tmp/config.json /home/appuser/.bluemix/
    mv /tmp/config.json /home/nobody/.bluemix/
    
    
}


_init()
{
    build_config_json
    bmcloud plugin install kubernetes-service
    ibmcloud plugin install container-registry
    #chek IBMcloud login is working
    ibmcloud ks clusters
    cat /home/appuser/.bluemix/config.json
    cat /home/appuser/.nobody/config.json
    curl -X GET "${ibm_ks_endpoint}/global/v1/clusters/${NAME}/config" -H "accept: application/json" -H "Authorization: ${IC_IAM_TOKEN}" -H "X-Auth-Refresh-Token: ${IC_IAM_REFRESH_TOKEN}" -o /tmp/kubeconfig.zip
    chmod +x /tmp/kubeconfig.zip
    rm -f /tmp/kube_conf_dtls.txt
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
        kubectl get namespaces
        echo "Debug : schematics namespace available."
    else
        echo "Debug : schematics namespace not available... creating one"
        kubectl create namespace $namespace
        kubectl get namespaces
    fi
    
}

_init


sleep 4000


