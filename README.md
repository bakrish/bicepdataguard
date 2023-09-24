## An Oracle Data guard deployment developed in Azure Bicep templates

This is a (partial) adaptation of the Oracle Data guard implementation avavilable here, converted into Bicep/Azure Resource Manager templates:
https://github.com/Azure/Oracle-Workloads-for-Azure/tree/main/oradg 

This template deploys the following resources:

- Primary Oracle Database VM with a data disk
- Secondary Oracle Database VM with a data disk
- Observer VM 
- A storage account to copy oracle pwd file from Primary to Secondary

Bicep Modules:
- Main.bicep : this is the driver script for deploying resources
- Oravm.bicep : this module includes the resources for creating the VM such as Public-IP , Data disk etc, and also creates the VM resource based on Oracle Marketplace image.
- Customscript.bicep : this module wrips custom script execution on the respective VM

Sequence of operations:
- Provisioning of VMs
- Primary DB VM configuration (primary.sh)
    - File system creation
    - Oracle DB creation and configuration
    - Modifying Oracle config files incouding tnsnames.ora and listener.ora
    - Disable VM firewall (such that replication can happen between primary and secondary)
    - Copy Ora pwd file to storage
- Secondary DB VM configuration (secondary.sh)
    - File system creation
    - Create Oracle duplicate DB through DBCA
    - Modifying Oracle config files including tnsnames.ora and listener.ora
    - Copy Ora pwd file from storage to secondary VM
- Observer VM configuration (observer.sh)
    - Data Guard configuration
    - Fast Start failover configuration 
    - Start of Observer component 

How to deploy the template
- At a minimum, the template requires a username for the Oracle VM amd ssh Public key. 
- There are a few other parameters that can be customized, including VM size.


