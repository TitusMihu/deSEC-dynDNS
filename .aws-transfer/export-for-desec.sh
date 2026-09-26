#!/bin/bash

AWSHZ=AWS-Zone-ID-Route53
DNSDOMAIN=My-Domain
aws route53 list-resource-record-sets --hosted-zone-id "$AWSHZ" --output json > r53.json && \
jq --arg d "$DNSDOMAIN." '
[ .ResourceRecordSets[]
  | select(.ResourceRecords)                                   # skip alias records
  | select(((.Type=="NS" or .Type=="SOA") and .Name==$d) | not) # deSEC manages apex NS/SOA
  | {
      subname: (.Name | gsub("\\\\052"; "*")
                      | if . == $d then "" else rtrimstr("." + $d) end),
      type: .Type,
      ttl: ([.TTL, 3600] | max),                               # deSEC minimum TTL
      records: [ .ResourceRecords[].Value ]
    }
]' r53.json > desec.json
