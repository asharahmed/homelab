# Network Zones

## Zones

### management
- Admin workstations
- `AsharPC` management surfaces
- Hypervisor/host admin endpoints

### servers
- Docker-hosted applications and internal service-to-service traffic

### trusted-clients
- Personal laptops, phones, tablets

### iot
- Smart home devices, TVs, appliances, low-trust endpoints

### guest
- Internet-only guest clients

### tailscale
- Remote operator/admin access over the mesh network

## Default Policy

- Deny inter-zone traffic by default.
- Allow only documented flows.
- Internet exposure only through `Caddy`.
- Monitoring and syslog listeners accept traffic only from explicit trusted senders.

## Required Allows

1. `trusted-clients` -> `public ingress`
- HTTPS to public services

2. `management` / `tailscale` -> `management`
- Admin ports and dashboards

3. `servers` -> Internet
- Limited outbound access for updates, DNS, upstream APIs, VPN, and package fetches

4. `iot` -> Internet
- No initiation to management or internal server admin ports

5. `guest` -> Internet
- No access to internal zones

## Current Trusted Sources

- Router / infrastructure: `192.168.1.1`
- Tailscale admin/collector path: `100.64.0.10`

## Exposure Classes

- `public`: internet reachable through `Caddy` and documented DNS
- `management-only`: reachable from LAN/Tailscale or protected admin path
- `tailscale-only`: available solely through Tailscale
- `internal`: no direct ingress outside the compose network
