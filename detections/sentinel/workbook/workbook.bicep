// Deploys the "Homelab Security Operations" Sentinel workbook as code.
// The workbook definition lives in workbook-content.json and is embedded at
// compile time, so the deployable artifact is reviewable in Git.

param workspaceName string
param location string = resourceGroup().location
param workbookDisplayName string = 'Homelab Security Operations'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  // Workbook resource name must be a GUID; derive it deterministically so
  // redeploys update in place rather than creating duplicates.
  name: guid(workspace.id, workbookDisplayName)
  location: location
  kind: 'shared'
  properties: {
    displayName: workbookDisplayName
    serializedData: loadTextContent('workbook-content.json')
    version: '1.0'
    sourceId: workspace.id
    category: 'sentinel'
  }
}

output workbookId string = workbook.id
output workbookName string = workbook.properties.displayName
