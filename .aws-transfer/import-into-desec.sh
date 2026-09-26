#!/bin/bash

TOKEN=deSEC-token
DNSDOMAIN=MyDomain
curl -X PATCH "https://desec.io/api/v1/domains/$DNSDOMAIN/rrsets/" \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  --data @desec.json
