#!/bin/bash

echo
echo "Check AWS DNS filezone against DNS filezone set on ns1.desec.io"
echo

D=gabriel-mihu.ro
AWS=ns-1744.awsdns-26.co.uk
for q in "$D MX" "$D TXT" "_dmarc.$D TXT" \
         "protonmail._domainkey.$D CNAME" "protonmail2._domainkey.$D CNAME" \
         "protonmail3._domainkey.$D CNAME" "zee.$D CNAME"; do
  if diff <(dig +short "$q" "@$AWS" | sort) <(dig +short "$q" @ns1.desec.io | sort) >/dev/null
  then echo "OK   $q"; else echo "DIFF $q"; fi
done

echo
