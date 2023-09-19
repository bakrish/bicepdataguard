@description('The name of you Virtual Machine.')
param vmName string = 'oravm'

@description('Username for the Virtual Machine.')
param adminUsername string

@description('SSH key for the Virtual Machine.')
param sshKey string

@description('Unique DNS Name for the Public IP used to access the Virtual Machine.')
param dnsLabelPrefix string = toLower('${vmName}-${uniqueString(resourceGroup().id)}')

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The size of the VM')
param vmSize string = 'Standard_D4ds_v5'

@description('Name of the VNET')
param virtualNetworkName string = 'vNet'

@description('Name of the subnet in the virtual network')
param dbSubnetName string = 'Subnet'

@description('Name of the Network Security Group')
param networkSecurityGroupName string = 'SecGroupNet'

var subnetAddressPrefix = '10.1.0.0/24'
var addressPrefix = '10.1.0.0/16'

var primaryvmscript = loadFileAsBase64('primary.sh')
var secondaryvmscript = loadFileAsBase64('secondary.sh')
var observervmscript = loadFileAsBase64('observer.sh')


resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = {
  parent: virtualNetwork
  name: dbSubnetName
  properties: {
    addressPrefix: subnetAddressPrefix
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}
module primary './oravm.bicep' = {
  name: 'primary'
  params: {
    vmName: 'primary'
    location: location
    adminUsername: adminUsername
    sshKey: sshKey
    subnetid: subnet.id
    networksecuritygroupid: networkSecurityGroup.id
    avZone: '1' 
  }
}


module secondary './oravm.bicep' = {
  name: 'secondary'
  params: {
    vmName: 'secondary'
    location: location
    adminUsername: adminUsername
    sshKey: sshKey
    subnetid: subnet.id
    networksecuritygroupid: networkSecurityGroup.id
    avZone: '2'     
  }
}

module observer './oravm.bicep' = {
  name: 'observer'
  params: {
    vmName: 'observer'
    location: location
    adminUsername: adminUsername
    sshKey: sshKey
    subnetid: subnet.id
    networksecuritygroupid: networkSecurityGroup.id
    avZone: '2'     
  }
}

// A storage location to copy oratab from Primary to secondary 
module storage 'store.bicep' = {
  name: 'storage'
  dependsOn: [primary,secondary]
  params: {
    storageAccountName: 'sharedstore1109'
    containerName: 'orashare'
    location: location
    primaryManagedIdentityId: primary.outputs.vmManagedidentity
    secondaryManagedIdentityId: secondary.outputs.vmManagedidentity
  }
} 

//Configure Primary database VM, after all components are provisioned
module vmonescript 'customscript.bicep' = {
  name: 'vmonescript'
  dependsOn: [storage]
  params: {
   scriptName: 'primary1'
   vmName: primary.name
   location: location
   scriptContent: primaryvmscript
  }
}

//Configure secondary database VM, after primary VM is configured successfully
module vmtwoscript 'customscript.bicep' = {
  name: 'vmtwoscript'
  dependsOn: [vmonescript]
  params: {
   scriptName: 'secondary1'
   vmName: secondary.name
   location: location
   scriptContent: secondaryvmscript
  }
}

//Configure observer VM, after primary and secondary VM are configured successfully
module vmthreescript 'customscript.bicep' = {
  name: 'vmthreescript'
  dependsOn: [vmtwoscript]
  params: {
   scriptName: 'observer1'
   vmName: observer.name
   location: location
   scriptContent: observervmscript
  }
}

