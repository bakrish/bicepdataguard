@description('Primary VM managed identity')
param primaryManagedIdentityId string

@description('Secondary VM managed identity')
param secondaryManagedIdentityId string

@description('Resource group location')
param location string

@description('Storage account name')
param storageAccountName string

@description('Container name')
param containerName string

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  kind: 'BlobStorage'
  name: storageAccountName
  location: location
  properties:{
    accessTier: 'Hot'
  }
  sku: {
    name: 'Standard_LRS' 
  }
}

resource mycontainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccountName}/default/${containerName}'
  dependsOn: [ storage]
}

resource storageBlobDataOwnerRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
}

resource primaryAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mycontainer.id,primaryManagedIdentityId,storageBlobDataOwnerRoleDefinition.id)
  scope: mycontainer
  properties: {
    principalId: primaryManagedIdentityId
    roleDefinitionId: storageBlobDataOwnerRoleDefinition.id
    principalType: 'ServicePrincipal'
  }
}


resource secondaryAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mycontainer.id,secondaryManagedIdentityId,storageBlobDataOwnerRoleDefinition.id)
  scope: mycontainer
  properties: {
    principalId: secondaryManagedIdentityId
    roleDefinitionId: storageBlobDataOwnerRoleDefinition.id
    principalType: 'ServicePrincipal'
  }
}
