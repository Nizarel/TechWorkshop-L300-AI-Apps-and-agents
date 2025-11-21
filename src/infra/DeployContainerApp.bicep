@description('Primary location for container app resources.')
param location string = resourceGroup().location

@description('Container App name.')
param containerAppName string = 'ca-${uniqueString(resourceGroup().id)}'

@description('Container image (e.g. oa2rrdktypnk6cosureg.azurecr.io/techworkshopl300/zava:latest).')
param image string

@description('ACR registry name (without azurecr.io).')
param acrName string

@description('Optional environment variables injected into container as array of { name, value }.')
param envVars array = []

@description('Managed Environment name for Container Apps.')
param managedEnvironmentName string = 'env-${uniqueString(resourceGroup().id)}'

@description('Minimum replicas for the container app.')
param minReplicas int = 1

@description('Maximum replicas for the container app.')
param maxReplicas int = 1


@description('Memory allocation (Gi format).')
param memory string = '1Gi'

resource managedEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: managedEnvironmentName
  location: location
  properties: {}
}

var acrLoginServer = '${acrName}.azurecr.io'

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: managedEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
      }
      registries: [
        {
          server: acrLoginServer
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'app'
          image: image
          resources: {
            cpu: json('0.5')
            memory: memory
          }
          env: envVars
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

// Assign AcrPull role to container app system identity
resource acrRegistry 'Microsoft.ContainerRegistry/registries@2022-12-01' existing = {
  name: acrName
}

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acrRegistry.id, containerApp.name, 'AcrPull')
  scope: acrRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
