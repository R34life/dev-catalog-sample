using 'main.bicep'

param appName = 'wvndcapp1'
param environment = 'prod'
param tags = {
  Environment: environment
  Owner: 'willvelida'
}
