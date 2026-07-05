// Sentinel scheduled analytics rule(s) over router syslog (native Syslog table,
// fed by detections/sentinel/router-telemetry/). Source of truth is the Sigma
// rule detections/rules/custom/router_ssh_bruteforce.yml (ported from Wazuh
// 100661); the KQL below is its Syslog-table implementation.

@description('Name of the Log Analytics workspace onboarded to Microsoft Sentinel.')
param workspaceName string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource routerSshBruteForce 'Microsoft.SecurityInsights/alertRules@2024-09-01' = {
  // Stable GUID (matches the Sigma rule id) so redeploys update in place.
  name: 'a1f3c0de-2007-4b07-bb07-0d2e4f6a8d0a'
  kind: 'Scheduled'
  scope: workspace
  properties: {
    displayName: 'Router SSH Brute Force (Dropbear)'
    description: 'Five or more failed SSH logins from the same source IP within the lookback window on the GL-BE9300 router Dropbear daemon - brute force against the network edge device. Source: rules/custom/router_ssh_bruteforce.yml (T1110.001).'
    severity: 'High'
    enabled: true
    // Dropbear splits a failed attempt across lines: "Login attempt for
    // nonexistent user" / "Bad password attempt for ..." carry the auth
    // outcome, while the source IP appears on "Exit before auth from <IP:port>"
    // (angle brackets) or inline on "Bad password ... from IP:port". Key off
    // the IP-bearing failure lines so every attempt is attributable.
    query: '''
Syslog
| where HostName == "GL-BE9300" and ProcessName == "dropbear"
| where SyslogMessage has_any ("Bad password", "Exit before auth", "nonexistent")
| extend SourceIP = extract(@"from <?([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})", 1, SyslogMessage)
| where isnotempty(SourceIP)
| summarize FailedAttempts = count(), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) by SourceIP, HostName
| where FailedAttempts >= 5
'''
    queryFrequency: 'PT10M'
    queryPeriod: 'PT10M'
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionDuration: 'PT1H'
    suppressionEnabled: false
    tactics: [ 'CredentialAccess' ]
    techniques: [ 'T1110' ]
    entityMappings: [
      {
        entityType: 'Host'
        fieldMappings: [
          { identifier: 'HostName', columnName: 'HostName' }
        ]
      }
      {
        entityType: 'IP'
        fieldMappings: [
          { identifier: 'Address', columnName: 'SourceIP' }
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

output ruleId string = routerSshBruteForce.id
