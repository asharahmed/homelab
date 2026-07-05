# Intune egress allow-list (OpenWrt)

Applies the Microsoft Intune (MEM) network endpoints as a router egress
allow-set, so the `management` zone (AsharPC) can reach Entra join, MDM
enrollment, compliance check-in, policy/app delivery, and device attestation
if/when management-zone egress is tightened past the current "limited
outbound" allow.

**Source of truth:** `tools/intune-vm/get-intune-endpoints.ps1` regenerates
the lists from Microsoft's live endpoints service. Ports: **TCP 443/80, UDP
123** (NTP). Re-run monthly (Microsoft updates the feed ~monthly) and re-apply.

> **Current state (2026-07-03):** management-zone egress to these endpoints is
> already permitted — `manage.microsoft.com`, `enterpriseregistration.windows.net`,
> and `login.microsoftonline.com` are reachable on 443 from AsharPC, and the
> host's Windows Defender Firewall default outbound action is Allow. This
> allow-set is a **pin/future-proof** for a tighter egress policy, not a fix for
> a current block. (The open Intune enrollment issue is a license
> `PendingInput`, unrelated to networking.)

## Apply as an nftables set (OpenWrt 22.03+ / fw4)

Copy `tools/intune-vm/intune-allowlist-ipv4.txt` and `intune-allowlist-ipv6.txt`
to the router, then:

```sh
# /etc/nftables.d/20-intune-allow.nft  (included by fw4)
table inet fw4 {
    set intune_v4 {
        type ipv4_addr; flags interval;
        elements = { $(paste -sd, /tmp/intune-allowlist-ipv4.txt) }
    }
    set intune_v6 {
        type ipv6_addr; flags interval;
        elements = { $(paste -sd, /tmp/intune-allowlist-ipv6.txt) }
    }
    chain mgmt_egress {
        ip  daddr @intune_v4 tcp dport { 80, 443 } accept
        ip6 daddr @intune_v6 tcp dport { 80, 443 } accept
        ip  daddr @intune_v4 udp dport 123 accept   # NTP time sync
    }
}
```

Hook `mgmt_egress` from the management zone's forward chain (or reference the
sets directly in a `config rule` in `/etc/config/firewall`). `flags interval`
lets a single set hold CIDR ranges.

## FQDN allow-listing (proxy / dnsmasq-nftset)

Windows Defender Firewall cannot do FQDN-based outbound rules, and the IP set
above can drift between Microsoft's monthly publishes. For DNS-based control,
feed the required FQDNs from `intune-network-endpoints.md` into a dnsmasq
`nftset` so resolved answers populate the allow set automatically:

```
# /etc/dnsmasq.d/intune.conf  (one line per apex; wildcards match subdomains)
nftset=/manage.microsoft.com/4#inet#fw4#intune_v4
nftset=/enterpriseregistration.windows.net/4#inet#fw4#intune_v4
nftset=/login.microsoftonline.com/4#inet#fw4#intune_v4
# ...remaining required apexes from intune-network-endpoints.md
```

This keeps the set current as Microsoft rotates IPs, without re-running the
generator. Prefer this over the static IP set if the router does DNS for the
management zone.

## Refresh workflow

```powershell
# on the host — regenerate from Microsoft, then copy the .txt files to the router
./tools/intune-vm/get-intune-endpoints.ps1
```

Diff the committed `.txt` files; if IPs changed, re-copy and `fw4 reload`.
