// Router syslog -> Sentinel native Syslog table, via the Logs Ingestion API.
// Deploys a Data Collection Endpoint + Data Collection Rule that accepts a
// custom stream (Custom-RouterSyslog) and writes it to Microsoft-Syslog, so
// built-in Sentinel Syslog content (parsers, SSH brute-force rules) applies.
// The on-prem forwarder (tools/monitoring/sentinel-syslog/) authenticates as
// a service principal that this template grants Monitoring Metrics Publisher
// on the DCR.

param workspaceName string
param location string = resourceGroup().location

@description('Object ID of the service principal that pushes logs (Monitoring Metrics Publisher on the DCR)')
param ingestPrincipalId string

// Monitoring Metrics Publisher built-in role
var metricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: 'dce-homelab'
  location: location
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-router-syslog'
  location: location
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      'Custom-RouterSyslog': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'EventTime', type: 'datetime' }
          { name: 'Computer', type: 'string' }
          { name: 'HostName', type: 'string' }
          { name: 'HostIP', type: 'string' }
          { name: 'Facility', type: 'string' }
          { name: 'SeverityLevel', type: 'string' }
          { name: 'ProcessName', type: 'string' }
          { name: 'ProcessID', type: 'int' }
          { name: 'SyslogMessage', type: 'string' }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspace.id
          name: 'law'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-RouterSyslog' ]
        destinations: [ 'law' ]
        transformKql: 'source'
        outputStream: 'Microsoft-Syslog'
      }
    ]
  }
}

resource ingestRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcr.id, ingestPrincipalId, metricsPublisherRoleId)
  scope: dcr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', metricsPublisherRoleId)
    principalId: ingestPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output dceIngestEndpoint string = dce.properties.logsIngestion.endpoint
output dcrImmutableId string = dcr.properties.immutableId
