// Deploys the generated Sigma-derived detections as Microsoft Sentinel
// scheduled analytics rules. Consumes analytics-rules.json (produced by
// generate-rules.py) via the `ruleSet` parameter.
//
//   az deployment group create -g <rg> -f main.bicep \
//     --parameters workspaceName=<ws> ruleSet=@analytics-rules.json

@description('Name of the existing Log Analytics workspace onboarded to Microsoft Sentinel.')
param workspaceName string

@description('Object with a "rules" array — pass analytics-rules.json directly.')
param ruleSet object

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource alertRules 'Microsoft.SecurityInsights/alertRules@2024-09-01' = [
  for rule in ruleSet.rules: {
    name: rule.name
    kind: 'Scheduled'
    scope: workspace
    properties: {
      displayName: rule.displayName
      description: rule.description
      severity: rule.severity
      enabled: true
      query: rule.query
      queryFrequency: rule.queryFrequency
      queryPeriod: rule.queryPeriod
      triggerOperator: rule.triggerOperator
      triggerThreshold: rule.triggerThreshold
      suppressionDuration: 'PT1H'
      suppressionEnabled: false
      tactics: rule.tactics
      techniques: rule.techniques
      // Every Defender XDR Device* table exposes DeviceName, so a Host entity
      // mapping is universally valid and lets alerts roll up into incidents.
      entityMappings: [
        {
          entityType: 'Host'
          fieldMappings: [
            {
              identifier: 'HostName'
              columnName: 'DeviceName'
            }
          ]
        }
      ]
      incidentConfiguration: {
        createIncident: true
        groupingConfiguration: {
          enabled: true
          reopenClosedIncident: false
          lookbackDuration: 'PT5H'
          matchingMethod: 'AllEntities'
          groupByEntities: []
          groupByAlertDetails: []
          groupByCustomDetails: []
        }
      }
    }
  }
]
