// Stands up a Log Analytics workspace and onboards it to Microsoft Sentinel.
// Run this once (or point the deploy at an existing workspace and skip it).

@description('Name of the Log Analytics workspace to create.')
param workspaceName string

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Log retention in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('Hard daily ingestion cap in GB. Azure physically drops ingestion once hit — budgets only alert. Conservative default protects the Azure for Students credit.')
@minValue(1)
param dailyQuotaGb int = 1

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
  }
}

// Onboard the workspace to Microsoft Sentinel (SecurityInsights solution).
resource sentinelOnboarding 'Microsoft.SecurityInsights/onboardingStates@2024-09-01' = {
  scope: workspace
  name: 'default'
  properties: {}
}

output workspaceName string = workspace.name
output workspaceId string = workspace.id
