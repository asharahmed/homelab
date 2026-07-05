// Subscription-scoped cost guardrail. Deploy BEFORE connecting any data source.
// The #1 homelab Sentinel failure mode is unfiltered ingestion → surprise bill;
// this alerts at 80%/100% actual and 100% forecasted spend.
//
//   az deployment sub create -l canadacentral -f budget.bicep \
//     --parameters contactEmail=you@example.com
targetScope = 'subscription'

@description('Budget name.')
param budgetName string = 'homelab-monthly'

@description('Monthly budget amount in the billing currency.')
param amount int = 20

@description('Email address to notify when thresholds are crossed.')
param contactEmail string

@description('Budget start date — must be the first of a month (ISO 8601).')
param startDate string = '2026-06-01'

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: budgetName
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
    }
    notifications: {
      Actual_GreaterThan_80_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: [ contactEmail ]
        thresholdType: 'Actual'
      }
      Actual_GreaterThan_100_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: [ contactEmail ]
        thresholdType: 'Actual'
      }
      Forecasted_GreaterThan_100_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: [ contactEmail ]
        thresholdType: 'Forecasted'
      }
    }
  }
}
