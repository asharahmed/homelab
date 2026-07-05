// Sentinel automation rule — runs sentinel-notify-playbook on every new
// High or Medium incident automatically.
//
//   az deployment group create -g rg-sentinel -f automation-rule.bicep \
//     --parameters workspaceName=law-homelab playbookId=<resource-id>

@description('Sentinel workspace name.')
param workspaceName string

@description('Resource ID of the notify playbook Logic App.')
param playbookId string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource automationRule 'Microsoft.SecurityInsights/automationRules@2024-09-01' = {
  name: guid(workspace.id, 'notify-on-incident-creation')
  scope: workspace
  properties: {
    displayName: 'Notify on incident creation'
    order: 1
    triggeringLogic: {
      isEnabled: true
      triggersOn: 'Incidents'
      triggersWhen: 'Created'
      conditions: [
        {
          conditionType: 'Property'
          conditionProperties: {
            propertyName: 'IncidentSeverity'
            operator: 'Equals'
            propertyValues: ['High', 'Medium']
          }
        }
      ]
    }
    actions: [
      {
        order: 1
        actionType: 'RunPlaybook'
        actionConfiguration: {
          logicAppResourceId: playbookId
          tenantId: subscription().tenantId
        }
      }
    ]
  }
}
