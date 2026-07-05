// Sentinel SOAR notification playbook — Logic App (Consumption) triggered on
// incident creation, posts to Telegram and ntfy, and comments on the incident.
// The workflow definition lives in notify-playbook-definition.json to avoid
// Bicep string-escaping issues with Logic App @{...} expressions.
//
//   az deployment group create -g rg-sentinel -f notify-playbook.bicep \
//     --parameters telegramBotToken=<token> \
//                  telegramChatId=<chat_id> \
//                  ntfyTopicUrl=https://ntfy.sh/<topic>

@description('Azure region for the Logic App.')
param location string = resourceGroup().location

@description('Telegram Bot API token.')
@secure()
param telegramBotToken string

@description('Telegram chat ID to receive alerts.')
param telegramChatId string

@description('Full ntfy topic URL, e.g. https://ntfy.sh/my-topic.')
param ntfyTopicUrl string

var playbookName = 'sentinel-notify-playbook'
var connectionName = 'azuresentinel-${playbookName}'

// API connection — parameterValueType 'Alternative' enables managed-identity auth
// so no OAuth consent dialog is needed.
resource sentinelConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: connectionName
  location: location
  properties: {
    displayName: 'azuresentinel'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
    }
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
  }
}

resource playbook 'Microsoft.Logic/workflows@2019-05-01' = {
  name: playbookName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: json(loadTextContent('notify-playbook-definition.json'))
    parameters: {
      '$connections': {
        value: {
          azuresentinel: {
            connectionId: sentinelConnection.id
            connectionName: connectionName
            connectionProperties: {
              authentication: { type: 'ManagedServiceIdentity' }
            }
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
          }
        }
      }
      telegramBotToken: { value: telegramBotToken }
      telegramChatId:   { value: telegramChatId }
      ntfyTopicUrl:     { value: ntfyTopicUrl }
    }
  }
}

// Grant the playbook's managed identity Microsoft Sentinel Responder on this RG
// so it can add comments to incidents.
resource sentinelResponder 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(playbook.id, '3e150937-b8fe-4cfb-8069-0eaf05ecd056')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '3e150937-b8fe-4cfb-8069-0eaf05ecd056' // Microsoft Sentinel Responder
    )
    principalId: playbook.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output playbookId string = playbook.id
output playbookName string = playbook.name
output principalId string = playbook.identity.principalId
