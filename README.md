# AzureCaseStudy
Case Study to create API and backend services to serve the Bank

As part of This case study we have requirement of 1 static website and 2 backend application running under private and public subnet.
One Public Backend service will be expose to API over internet to static website (i.e. User whoever are accessing the statice website can send API request to this backend service)
Once Private Backend service willbe expose to API only for Internal Banking application privately and will be able to send response only to Outbound IP (203.0.113.0/24) over internet.

To build this setup we have to build below components -
  Static Website hosted on Blob Storage and publish using content delievery network.
  Network Virtual Network with Public and Private Subnet.
  Backend Service in Public Subnet expose to API with respective DB for applicaiton. Backend application are running on container and exposed to API via backend URL.
  Backend Service in Private Subnet expose to Private API with respective DB for application. private endpoint to allow access to api privately and firewall rule to allow only outboudn IP traffic as requested. Inbound rules allowing only traffic with in subnet resources, API is integrated with Endpoints and can be controlled with firewall rules to restric traffic from allowed sources only.


This Case study is build using Terraform and can be build on Azure using Various way either Jenkins or Gitlab file can be added if we have those tools available or this case study file can be deployed
to Azure using Terraform and Azure CLI also as mentioned below -

PreRequisitics -
Install Azure CLI
Install Terraform
Create Storage Account in Blob Storage to store the State of Terraform -  'statestoragecase' 

Authentication to Azure -
az login (Make sure you have needed subscription with credentials to build resources)

Clone the Code  -
git clone https://github.com/paliwalnitesh/AzureCaseStudy.git

Initiate Terraform to see the plan -
terraform init
terraform plan -out=tfplan
terraform apply tfplan

