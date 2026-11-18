#!/bin/bash
# mirabelle firewall: apply.
#
# Run by `mirabelle run` and `mirabelle lock`, from the PC, with one privileged
# command:
#     docker exec -i -u root --privileged <container> bash -s < setup/lock/apply.sh
# It is the only privileged command mirabelle ever runs in a container. The
# script itself comes from the PC (it is not stored in the image), and so do
# its inputs, mounted read-only at /lock-run:
#     allowed.txt   domains the filter allows (subdomains included)
#     filter        the same, as the filter's patterns
#     private.txt   "address port" pairs on the local network that may be reached
#     ports.txt     ports the filter may connect to
#     tinyproxy.conf
#
# What it sets up:
#   - kernel rules: only the user "gate" may send anything out; "dev" may only
#     talk to the container itself (the filter listens on 127.0.0.1:3128);
#     the local network and your PC are refused except the listed pairs;
#   - the filter (tinyproxy), running as "gate", with no privileges at all.
# The kernel rules are set first: if the filter then fails to start, the
# container is closed, not open.
set -euo pipefail

say() { printf 'lock: %s\n' "$*"; }
die() { printf 'lock: ERROR: %s\n' "$*" >&2; exit 1; }

R=/lock-run
for f in allowed.txt filter private.txt ports.txt tinyproxy.conf; do
  [[ -r "$R/$f" ]] || die "missing $R/$f"
done

gate_uid=$(id -u gate)

# --- kernel rules -----------------------------------------------------------
ipt=iptables
$ipt -P OUTPUT ACCEPT
$ipt -F OUTPUT

$ipt -A OUTPUT -o lo -j ACCEPT
$ipt -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Name servers the filter uses (from /etc/resolv.conf), for "gate" only.
ns_count=0
while read -r ns; do
  [[ "$ns" =~ ^[0-9.]+$ ]] || continue
  $ipt -A OUTPUT -m owner --uid-owner "$gate_uid" -d "$ns" -p udp --dport 53 -j ACCEPT
  $ipt -A OUTPUT -m owner --uid-owner "$gate_uid" -d "$ns" -p tcp --dport 53 -j ACCEPT
  ns_count=$((ns_count + 1))
done < <(awk '$1=="nameserver"{print $2}' /etc/resolv.conf)

# Listed pairs on the local network, for "gate" only.
priv_count=0
while read -r addr port _; do
  [[ -z "${addr:-}" || "$addr" == \#* ]] && continue
  [[ "$addr" =~ ^[0-9.]+$ && "$port" =~ ^[0-9]+$ ]] || die "bad line in private.txt: $addr $port"
  $ipt -A OUTPUT -m owner --uid-owner "$gate_uid" -d "$addr" -p tcp --dport "$port" -j ACCEPT
  priv_count=$((priv_count + 1))
done < "$R/private.txt"

# Everything else on the local network, the PC, and special ranges: refused.
for net in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 \
           172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 \
           224.0.0.0/4 240.0.0.0/4; do
  $ipt -A OUTPUT -d "$net" -p tcp -j REJECT --reject-with tcp-reset
  $ipt -A OUTPUT -d "$net" -j REJECT
done

# Public addresses: "gate" only, and only on the listed ports.
ports=$(grep -E '^[0-9]+$' "$R/ports.txt" | sort -un | paste -sd, -)
[[ -n "$ports" ]] || die "ports.txt is empty"
$ipt -A OUTPUT -m owner --uid-owner "$gate_uid" -p tcp -m multiport --dports "$ports" -j ACCEPT

# Anything else: refused.
$ipt -A OUTPUT -p tcp -j REJECT --reject-with tcp-reset
$ipt -A OUTPUT -j REJECT
$ipt -P OUTPUT DROP
say "kernel rules set: only gate goes out, ports $ports, $priv_count local pair(s), $ns_count name server(s)"

# --- IPv6 -------------------------------------------------------------------
if [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 1)" == "1" ]]; then
  say "IPv6 disabled in this container"
else
  ip6tables -P OUTPUT ACCEPT
  ip6tables -F OUTPUT
  ip6tables -A OUTPUT -o lo -j ACCEPT
  ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ip6tables -A OUTPUT -j REJECT
  ip6tables -P OUTPUT DROP
  say "IPv6 outgoing refused"
fi

# --- the filter -------------------------------------------------------------
mkdir -p /run/mirabelle/gate
chown gate:gate /run/mirabelle/gate
chmod 0755 /run/mirabelle /run/mirabelle/gate

if pgrep -u gate -x tinyproxy >/dev/null; then
  pkill -u gate -x tinyproxy || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -u gate -x tinyproxy >/dev/null || break; sleep 0.2; done
  say "filter stopped for reload"
fi
: > /run/mirabelle/gate/tinyproxy.log
chown gate:gate /run/mirabelle/gate/tinyproxy.log
chmod 0644 /run/mirabelle/gate/tinyproxy.log

# Start as "gate" from the first instruction, with an empty capability
# bounding set and no way to gain privileges.
setsid -f setpriv --reuid=gate --regid=gate --init-groups \
  --bounding-set=-all --inh-caps=-all --no-new-privs \
  tinyproxy -d -c "$R/tinyproxy.conf" >>/run/mirabelle/gate/tinyproxy.log 2>&1

for _ in $(seq 1 25); do
  pgrep -u gate -x tinyproxy >/dev/null && break
  sleep 0.2
done
pgrep -u gate -x tinyproxy >/dev/null || die "the filter did not start; see /run/mirabelle/gate/tinyproxy.log"
say "filter running as user gate on 127.0.0.1:3128, $(grep -cv '^\s*\(#\|$\)' "$R/allowed.txt") domains allowed"
