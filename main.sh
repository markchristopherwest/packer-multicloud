#!/usr/bin/env bash
set -e

meta_name=
azure_client_id=       # Derived from application after creation
azure_client_name=     # Application name
azure_client_secret=   # Application password
azure_group_name=
azure_storage_name=
azure_subscription_id= # Derived from the account after login
azure_tenant_id=       # Derived from the account after login
location=
azure_object_id=
azureversion=
create_sleep=10

function log {
  local -r level="$1"
  local -r message="$2"
  local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  >&2 echo -e "${timestamp} [${level}] [$SCRIPT_NAME] ${message}"
}

function log_info {
  local -r message="$1"
  log "INFO" "$message"
}

function log_warn {
  local -r message="$1"
  log "WARN" "$message"
}

function log_error {
  local -r message="$1"
  log "ERROR" "$message"
}

showhelp() {
    echo "azure-setup"
    echo ""
    echo "  azure-setup helps you generate packer credentials for azure"
    echo ""
    echo "  The script creates a resource group, storage account, application"
    echo "  (client), service principal, and permissions and displays a snippet"
    echo "  for use in your packer templates."
    echo ""
    echo "  For simplicity we make a lot of assumptions and choose reasonable"
    echo "  defaults. If you want more control over what happens, please use"
    echo "  the azure-cli directly."
    echo ""
    echo "  Note that you must already have an Azure account, username,"
    echo "  password, and subscription. You can create those here:"
    echo ""
    echo "  - https://azure.microsoft.com/en-us/account/"
    echo ""
    echo "REQUIREMENTS"
    echo ""
    echo "  - azure-cli"
    echo "  - jq"
    echo ""
    echo "  Use the requirements command (below) for more info."
    echo ""
    echo "USAGE"
    echo ""
    echo "  ./azure-setup.sh requirements"
    echo "  ./azure-setup.sh setup"
    echo ""
}

requirements() {
    found=0

    azureversion=$(az --version)
    if [ $? -eq 0 ]; then
        found=$((found + 1))
        echo "Found azure-cli version: $azureversion"
    else
        echo "azure-cli is missing. Please install azure-cli from"
        echo "https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest"
        echo "Alternatively, you can use the Cloud Shell https://docs.microsoft.com/en-us/azure/cloud-shell/overview right from the Azure Portal or even VS Code."
    fi

    jqversion=$(jq --version)
    if [ $? -eq 0 ]; then
        found=$((found + 1))
        echo "Found jq version: $jqversion"
    else
        echo "jq is missing. Please install jq from"
        echo "https://stedolan.github.io/jq/"
    fi

    if [ $found -lt 2 ]; then
        exit 1
    fi
}

askSubscription() {
    az account list -otable
    echo ""
    echo "Please enter the Id of the account you wish to use. If you do not see"
    echo "a valid account in the list press Ctrl+C to abort and create one."
    echo "If you leave this blank we will use the Current account."
    echo -n "> "
    read azure_subscription_id

    if [ "$azure_subscription_id" != "" ]; then
        az account set --subscription $azure_subscription_id
    else
        azure_subscription_id=$(az account list --output json | jq -r '.[] | select(.isDefault==true) | .id')
    fi
    azure_tenant_id=$(az account list --output json | jq -r '.[] | select(.id=="'$azure_subscription_id'") |  .tenantId')
    echo "Using subscription_id: $azure_subscription_id"
    echo "Using tenant_id: $azure_tenant_id"
}

askName() {
    # echo ""
    # echo "Choose a name for your resource group, storage account and client"
    # echo "client. This is arbitrary, but it must not already be in use by"
    # echo "any of those resources. ALPHANUMERIC ONLY. Ex: mypackerbuild"
    # # echo -n "> "
    # # read meta_name
    meta_name="example$(openssl rand -base64 48 | tr -d "=+/" |sed 's/[A-Z]//g ; s/^\(.\{5\}\).*/\1/')"
}

askSecret() {
    echo ""
    echo "Enter a secret for your application. We recommend generating one with"
    echo "openssl rand -base64 24. If you leave this blank we will attempt to"
    echo "generate one for you using openssl. THIS WILL BE SHOWN IN PLAINTEXT."
    echo "Ex: mypackersecret8734"
    echo -n "> "
    read azure_client_secret
    if [ "$azure_client_secret" = "" ]; then
        azure_client_secret=$(openssl rand -base64 24)
        if [ $? -ne 0 ]; then
            echo "Error generating secret"
            exit 1
        fi
        echo "Generated client_secret: $azure_client_secret"
    fi
}

askLocation() {
    az account list-locations -otable
    echo ""
    echo "Choose which region your resource group and storage account will be created.  example: westus"
    echo -n "> "
    read location
}

createThings() {


    echo "==> Creating resource group"
    az group create -n $meta_name -l $location
    if [ $? -eq 0 ]; then
        azure_group_name=$meta_name
    else
        echo "Error creating resource group: $meta_name"
        return 1
    fi
    echo "created resource group: $azure_group_name"
    # sleep 10
    echo "==> Creating storage account"
    az storage account create --name $meta_name --resource-group $azure_group_name --location $location --kind Storage --sku Standard_LRS
    if [ $? -eq 0 ]; then
        azure_storage_name=$meta_name
    else
        echo "Error creating storage account: $meta_name"
        return 1
    fi

    echo "created storage account: $azure_storage_name"
    echo "==> Creating application"
    echo "==> Does application exist?"
    azure_client_id=$(az ad app list --output json | jq -r '.[] | select(.displayName | contains("'$azure_storage_name'")) ')
    
    
    if [ "$azure_client_id" != "" ]; then
        echo "==> application already exist, grab appId"
        azure_client_id=$(az ad app list --output json | jq -r '.[] | select(.displayName | contains("'$meta_name'")) .appId')
    else
        echo "==> application does not exist"
        # azure_client_id=$(az ad app create --display-name $meta_name --identifier-uris http://$meta_name --homepage http://$meta_name --password $azure_client_secret --output json | jq -r .appId)
        azure_client_id=$(az ad app create --display-name "$meta_name" --output json | jq -r .appId)
    fi

    echo "target azure app: $azure_client_id"
    

    if [ $? -ne 0 ]; then
        echo "Error creating application: $meta_name @ http://$meta_name"
        return 1
    fi

    echo "==> Creating secret"

    clientsecret=$(az ad app credential reset --id $azure_client_id --years 1 --query password --output tsv)
    echo $clientsecret
       if [ $? -ne 0 ]; then
        echo "Error creating secret: az ad app credential reset --id $azure_client_id --append --credential-description $meta_name --years 1 --query password --output tsv"
        return 1
    fi


    echo "==> Creating service principal"
    azure_object_id=$(az ad sp create --id $azure_client_id --output json | jq -r .objectId)
    if [ $? -ne 0 ]; then
        echo "Error creating Service Principal: az ad sp create --id $azure_client_id --output json | jq -r .objectId"
        return 1
    fi

    echo "created service principal: $azure_client_id"
    if [ $? -ne 0 ]; then
        echo "Error creating service principal: $azure_client_id"
        return 1
    fi
    echo "==> Creating permissions"
    az role assignment create --assignee "${azure_client_id}" --role "Owner" --scope /subscriptions/$azure_subscription_id --output json

    # az role assignment create --assignee $azure_object_id --role "Storage Account Key Operator Service Role" --scope /subscriptions/$azure_subscription_id --output json
    # If the user wants to use a more conservative scope, she can.  She must
    # configure the Azure builder to use build_resource_group_name.  The
    # easiest solution is subscription wide permission.
    # az role assignment create --spn http://$meta_name -g $azure_group_name -o "API Management Service Contributor"
    if [ $? -ne 0 ]; then
        echo "Error creating permissions for: http://$meta_name"
        echo "az role assignment create --assignee "${azure_object_id}" --role "Owner" --scope /subscriptions/$azure_subscription_id"
        return 1
    fi

    aws_region="us-west-1"
    product_name="ws"
    product_user="Bob Loblaw"
    product_vendor="msft"
    product_version="2019-datacenter"
    timestamp=`date "+%Y%m%d-%H%M%S"`
stanza_product=$(cat <<EOF

# https://www.packer.io/docs/templates/legacy_json_templates/user-variables#from-a-file

variable "AWS_ACCESS_KEY_ID" {
  type    = string
  default = env("AWS_ACCESS_KEY_ID")
}

variable "AWS_SECRET_ACCESS_KEY" {
  type    = string
  default = env("AWS_SECRET_ACCESS_KEY")
}

variable "AWS_SESSION_TOKEN" {
  type    = string
  default = env("AWS_SESSION_TOKEN")
}

source "amazon-ebs" "windows" {
  ami_name = "${product_vendor}-${product_name}-${product_version}-amd64-${timestamp}"
  instance_type = "t3.medium"
  region = "${aws_region}"
  source_ami_filter {
    filters = {
      name = "Windows_Server-2019-English-Full-Base-*"
      root-device-type = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners = ["amazon"]
  }
  communicator = "winrm"
  winrm_username = "Administrator"
  winrm_use_ssl = true
  winrm_insecure = true

  # This user data file sets up winrm and configures it so that the connection
  # from Packer is allowed. Without this file being set, Packer will not
  # connect to the instance.
  user_data_file = "my-user-data.txt"
}

source "azure-arm" "windows" {
  azure_tags = {
    dept = "Engineering"
    task = "Image deployment"
  }
  build_resource_group_name         = "${azure_group_name}"
  client_id                         = "${azure_client_id}"
  client_secret                     = "${clientsecret}"
  communicator                      = "winrm"
  image_offer                       = "WindowsServer"
  image_publisher                   = "MicrosoftWindowsServer"
  image_sku                         = "${product_version}"
  managed_image_name                = "${product_vendor}-${product_name}-${product_version}-amd64-${timestamp}"
  managed_image_resource_group_name               = "${azure_group_name}"
  os_type                           = "Windows"
  # storage_account                   = "${azure_storage_name}"
  subscription_id                   = "${azure_subscription_id}"
  tenant_id                         = "${azure_tenant_id}"
  vm_size                           = "Standard_D2_v2"
  winrm_insecure                    = true
  winrm_timeout                     = "5m"
  winrm_use_ssl                     = true
  winrm_username                    = "packer"
}

build {
  hcp_packer_registry {
    bucket_name = "${product_vendor}-${product_name}"
    description = <<EOT
  Windows: From Redmond with Love
      EOT
    # https://www.packer.io/docs/templates/hcl_templates/blocks/build/hcp_packer_registry#bucket_labels
    bucket_labels = {
      "bucket_manufacturer" = "${product_vendor}",
      "bucket_product"      = "${product_name}",
    }
    # https://www.packer.io/docs/templates/hcl_templates/blocks/build/hcp_packer_registry#build_labels
    build_labels = {
      "build_age_birth"   = formatdate("YYYY-MM-DD'T'hh:mm:ssZ", timestamp()),
      "build_age_death"   = formatdate("YYYY-MM-DD'T'hh:mm:ssZ", timeadd(formatdate("YYYY-MM-DD'T'hh:mm:ssZ", timestamp()), "2160h")),
      "build_git_repo"    = "https://github.com/markchristopherwest/packer-multicloud",
      "build_git_tag"     = "${product_name}",
      "build_image_score" = "5",
      "build_image_wiki"  = "https://${product_vendor}/${product_name}"
      "build_owner_group" = "foo",
      "build_owner_user"  = "${product_user}",
      "build_version"     = "${product_version}"
    }
  }
  sources = ["source.amazon-ebs.windows", "source.azure-arm.windows"]
  provisioner "powershell" {
    script = "my-install-script.ps1"
  }
  #provisioner "powershell" {
  #  inline = ["Add-WindowsFeature Web-Server", "while ((Get-Service RdAgent).Status -ne 'Running') { Start-Sleep -s 5 }", "while ((Get-Service WindowsAzureGuestAgent).Status -ne 'Running') { Start-Sleep -s 5 }", "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit", "while($true) { $imageState = Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State | Select ImageState; if($imageState.ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { Write-Output $imageState.ImageState; Start-Sleep -s 10  } else { break } }"]
  #}
  provisioner "powershell" {
    inline = [
      # Re-initialise the AWS instance on startup
      "C:/ProgramData/Amazon/EC2-Windows/Launch/Scripts/InitializeInstance.ps1 -Schedule",
      # Remove system specific information from this image
      "C:/ProgramData/Amazon/EC2-Windows/Launch/Scripts/SysprepInstance.ps1 -NoShutdown"
    ]
    only = [
      "amazon-ebs.windows"
    ]
  }


}
  

EOF
)



    echo "Generating ${meta_name}.pkr.hcl for Packer..."
    echo "$stanza_product" > "${meta_name}.pkr.hcl"


    echo "Showing ${meta_name}.pkr.hcl for Packer..."
    cat "${meta_name}.pkr.hcl"

    # echo ""
    # echo "Use the following configuration for your packer template:"
    # echo ""
    # echo "{"
    # echo "      \"client_id\": \"$azure_client_id\","
    # echo "      \"client_secret\": \"$azure_client_secret\","
    # echo "      \"object_id\": \"$azure_object_id\","
    # echo "      \"subscription_id\": \"$azure_subscription_id\","
    # echo "      \"tenant_id\": \"$azure_tenant_id\","
    # echo "      \"resource_group_name\": \"$azure_group_name\","
    # echo "      \"storage_account\": \"$azure_storage_name\","
    # echo "}"
    # echo ""
}

doSleep() {
    local sleep_time=${PACKER_SLEEP_TIME-$create_sleep}
    echo ""
    echo "Sleeping for ${sleep_time} seconds to wait for resources to be "
    echo "created. If you get an error about a resource not existing, you can "
    echo "try increasing the amount of time we wait after creating resources "
    echo "by setting PACKER_SLEEP_TIME to something higher than the default."
    echo ""
    sleep $sleep_time
}

retryable() {
    n=0
    until [ $n -ge $1 ]
    do
        $2 && return 0
        echo "$2 failed. Retrying..."
        n=$[$n+1]
        doSleep
    done
    echo "$2 failed after $1 tries. Exiting."
    exit 1
}


setup() {
    requirements


        log_error "The binary doormat is not installed so we'll login with Azure UI."
        az login

    # Ask Which Azure Subscription to Use
    askSubscription
    # Ask Which Name to Call the App, SPN & Resource Group.
    askName
    # Ask What Secret to Create
    askSecret
    # Ask What Target Region
    askLocation
    # Autoate All of the Things
    createThings

}

case "$1" in
    requirements)
        requirements
        ;;
    setup)
        setup
        ;;
    *)
        showhelp
        ;;
esac