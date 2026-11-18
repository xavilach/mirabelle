#!/bin/bash
# mirabelle firewall: test.
#
# Run by `mirabelle run` and `mirabelle lock` right after apply.sh, as the
# ordinary user "dev" and WITHOUT privileges:
#     docker exec -i -u dev <container> bash -s < setup/lock/test.sh
# It checks what Claude can actually do. If a check fails, mirabelle stops and
# removes the container.
#
# Must hold (failure = container removed):
#   1. dev cannot reach the internet directly, without the filter;
#   2. dev cannot reach the local network directly;
#   3. the filter refuses a site that is not listed;
#   4. the filter is running, as user gate;
#   5. dev cannot read or change the kernel rules;
#   6. dev cannot stop the filter.
# Reported only (needs the internet, so it cannot decide the result):
#   7. api.anthropic.com (or the first listed site) answers through the filter.
set -uo pipefail

fail=0
ok()  { printf 'test: ok    %s\n' "$*"; }
bad() { printf 'test: FAIL  %s\n' "$*"; fail=1; }
inf() { printf 'test: info  %s\n' "$*"; }

if curl --noproxy '*' -s -o /dev/null -m 5 https://1.1.1.1; then
  bad "1 dev reached the internet directly (https://1.1.1.1)"
else
  ok "1 no direct internet access"
fi

if curl --noproxy '*' -s -o /dev/null -m 5 http://192.168.1.1; then
  bad "2 dev reached the local network directly (http://192.168.1.1)"
else
  ok "2 no direct local network access"
fi

code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' --proxy http://127.0.0.1:3128 https://blocked.mirabelle.invalid 2>/dev/null)
connect=$(curl -s -o /dev/null -m 10 -w '%{http_connect}' --proxy http://127.0.0.1:3128 https://blocked.mirabelle.invalid 2>/dev/null)
if [[ "$connect" == "403" ]]; then
  ok "3 filter refuses a site that is not listed (403)"
else
  bad "3 filter did not refuse an unlisted site (connect=$connect http=$code)"
fi

if pgrep -u gate -x tinyproxy >/dev/null; then
  ok "4 filter running as user gate"
else
  bad "4 filter not running"
fi

if iptables -S OUTPUT >/dev/null 2>&1 || iptables -F OUTPUT >/dev/null 2>&1; then
  bad "5 dev can read or change the kernel rules"
else
  ok "5 dev cannot read or change the kernel rules"
fi

pid=$(pgrep -u gate -x tinyproxy | head -1)
if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
  bad "6 dev can signal the filter process"
else
  ok "6 dev cannot stop the filter"
fi

first=$(grep -Ev '^\s*(#|$)' /lock-run/allowed.txt | grep -x 'api.anthropic.com' || grep -Ev '^\s*(#|$)' /lock-run/allowed.txt | head -1)
if [[ -n "$first" ]]; then
  c=$(curl -s -o /dev/null -m 15 -w '%{http_connect}' --proxy http://127.0.0.1:3128 "https://$first" 2>/dev/null)
  if [[ "$c" == "200" ]]; then
    inf "7 $first answers through the filter"
  else
    inf "7 $first did not answer through the filter (connect=$c): no internet, or the site is down"
  fi
fi

if [[ $fail -ne 0 ]]; then
  echo "test: firewall NOT as expected"
  exit 1
fi
echo "test: firewall as expected"
