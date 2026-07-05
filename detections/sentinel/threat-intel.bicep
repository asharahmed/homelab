// Sentinel threat intelligence data connectors (WS C.2).
//
// Two connectors:
//  1. Microsoft Defender Threat Intelligence emerging-threat feed. NOTE: on
//     this tenant (no MDTI premium license) the connector reports 'enabled'
//     but ingests nothing — the emerging-threat feed is premium-gated. Kept
//     so it lights up automatically if an MDTI premium license is ever added.
//  2. A generic TAXII 2.x feed (defaults to the free AlienVault OTX server).
//     Deployed only when a TAXII username/API key is supplied.
//
// Indicators land in the ThreatIntelligenceIndicator table.

param workspaceName string

@description('TAXII feed display name.')
param taxiiFriendlyName string = 'AlienVault OTX'

@description('TAXII 2.x API root URL.')
param taxiiServer string = 'https://otx.alienvault.com/taxii/root'

@description('TAXII collection ID.')
param taxiiCollectionId string = 'user_AlienVault'

@description('TAXII username. For OTX this is the account API key. Leave empty to skip the TAXII connector.')
@secure()
param taxiiUserName string = ''

@description('TAXII password. Sentinel requires a non-empty value; for OTX pass the API key again (OTX authenticates on the username and ignores this).')
@secure()
param taxiiPassword string = ''

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource mdtiConnector 'Microsoft.SecurityInsights/dataConnectors@2023-02-01-preview' = {
  scope: workspace
  name: guid(workspace.id, 'mdti-emerging-threat-feed')
  kind: 'MicrosoftThreatIntelligence'
  properties: {
    tenantId: subscription().tenantId
    // Type library expects a deprecated bingSafetyPhishingURL data type; the
    // live API only needs the emerging-threat feed.
    #disable-next-line BCP035
    dataTypes: {
      microsoftEmergingThreatFeed: {
        state: 'enabled'
        lookbackPeriod: '1970-01-01T00:00:00.000Z'
      }
    }
  }
}

resource taxiiConnector 'Microsoft.SecurityInsights/dataConnectors@2023-02-01-preview' = if (!empty(taxiiUserName)) {
  scope: workspace
  name: guid(workspace.id, 'taxii-feed')
  kind: 'ThreatIntelligenceTaxii'
  properties: {
    tenantId: subscription().tenantId
    workspaceId: workspace.properties.customerId
    friendlyName: taxiiFriendlyName
    taxiiServer: taxiiServer
    collectionId: taxiiCollectionId
    userName: taxiiUserName
    password: taxiiPassword
    taxiiLookbackPeriod: '1970-01-01T00:00:00.000Z'
    pollingFrequency: 'OnceADay'
    dataTypes: {
      taxiiClient: {
        state: 'enabled'
      }
    }
  }
}
