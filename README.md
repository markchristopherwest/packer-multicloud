# packer-multicloud

Build Windows images on AWS & Azure via HCP Packer.  This script sets up the necessary prerequisites in Azure & generates iteration.pkr.hcl.  You can always refactor to generate tfvars files, etc.  Remember by using HashiCorp, although your technologies might change the workflow remains the same across clouds.  Learn more about HashiCorp can help you unlock The Cloud Operating Model here:

https://www.hashicorp.com/cloud-operating-model

## Getting Started

### WSL

https://docs.microsoft.com/en-us/windows/wsl/install#install-wsl-command

```powershell
wsl --install
```

### SH

```bash
./main.sh setup
```

### and then

https://cloud.hashicorp.com/docs/hcp/admin/service-principals#create-a-service-principal

```bash
export HCP_CLIENT_ID=foo
export HCP_CLIENT_SECRET=bar
export HCP_PACKER_BUILD_FINGERPRINT=$(openssl rand -base64 48 | tr -d "=+/" |sed 's/[A-Z]//g ; s/^\(.\{5\}\).*/\1/')
PACKER_LOG=1 packer build .
```