@description('The region to deploy all the resources')
param location string = resourceGroup().location

@description('The tags to apply to all resources in this application')
param tags object = {}

@description('The name of the application to deploy')
param appName string

@description('The environment where this app will be deployed to')
param environment string

module logAnalytics 'modules/monitoring/log-analytics.bicep' = {
  name: 'law'
  params: {
    name: '${environment}-${appName}-law'
    location: location
    tags: tags
  }
}

module appInsights 'modules/monitoring/app-insights.bicep' = {
  name: 'appins'
  params: {
    name: '${environment}-${appName}-ains'
    location: location
    tags: tags
    logAnalyticsName: logAnalytics.outputs.logAnalyticsName
  }
}

module uai 'modules/identity/user-assigned-identity.bicep' = {
  name: 'uai'
  params: {
    name: '${environment}-${appName}-uai'
    location: location
    tags: tags
  }
}

module appConfig 'modules/security/app-config.bicep' = {
  name: 'app-config'
  params: {
    name: '${environment}-${appName}-config'
    location: location
    tags: tags
    logAnalyticsName: logAnalytics.outputs.logAnalyticsName
    uaiName: uai.outputs.uaiName
  }
}

module keyVault 'modules/security/key-vault.bicep' = {
  name: 'kv'
  params: {
    name: '${environment}-${appName}-kv'
    location: location
    tags: tags
    logAnalyticsName: logAnalytics.outputs.logAnalyticsName
    uaiName: uai.outputs.uaiName
  }
}

module env 'modules/host/container-app-env.bicep' = {
  name: 'env'
  params: {
    name: '${environment}-${appName}-env'
    location: location
    tags: tags
    logAnalyticsName: logAnalytics.outputs.logAnalyticsName
  }
}
module acr 'modules/host/container-registry.bicep' = {
  name: 'acr'
  params: {
    name: '${environment}${appName}acr'
    location: location
    tags: tags
    logAnalyticsName: logAnalytics.outputs.logAnalyticsName
    uaiName: uai.outputs.uaiName
  }
}

module cosmosdb 'modules/database/serverless-cosmos-db.bicep' = {
  name: 'cosmos-db'
  params: {
    location: location
    tags: tags
    accountName: '${environment}-${appName}-db' 
    appConfigName: appConfig.outputs.appConfigName
    containerName: 'items'
    databaseName: 'ndcapp1DB'
    logAnalyticsName: logAnalytics.outputs.logAnalyticsName
    uaiName: uai.outputs.uaiName
  }
}
