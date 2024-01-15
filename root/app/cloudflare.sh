#!/usr/bin/with-contenv sh

cloudflare() {
  if [ -f "$API_KEY_FILE" ]; then
      API_KEY=$(cat $API_KEY_FILE)
  fi
  
  if [ -z "$EMAIL" ]; then
      curl -sSL \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      "$@"
  else
      curl -sSL \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -H "X-Auth-Email: $EMAIL" \
      -H "X-Auth-Key: $API_KEY" \
      "$@"
  fi
}

getLocalIpAddress() {
  if [ "$RRTYPE" == "A" ]; then
    IP_ADDRESS=$(ip addr show $INTERFACE | awk '$1 == "inet" {gsub(/\/.*$/, "", $2); print $2; exit}')
  elif [ "$RRTYPE" == "AAAA" ]; then
    IP_ADDRESS=$(ip addr show $INTERFACE | awk '$1 == "inet6" {gsub(/\/.*$/, "", $2); print $2; exit}')
  fi

  echo $IP_ADDRESS
}

getCustomIpAddress() {
  IP_ADDRESS=$(sh -c "$CUSTOM_LOOKUP_CMD")
  echo $IP_ADDRESS
}

getPublicIpAddress() {
  if [ "$RRTYPE" == "A" ]; then
    # Use api.ipify.org
    IPIFY=$(curl -sf4 https://api.ipify.org)
    IP_ADDRESS=$([[ "$IPIFY" =~ ^[1-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[1-9][0-9]?[0-9]?$ ]] && echo "$IPIFY" || echo "")

    # Use ipecho.net/plain
    if [ "$IP_ADDRESS" = "" ]; then
      IPECHO=$(curl -sf4 https://ipecho.net/plain)
      IP_ADDRESS=$([[ "$IPECHO" =~ ^[1-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[1-9][0-9]?[0-9]?$ ]] && echo "$IPIFY" || echo "")
    fi

    # Use ipinfo.io
    if [ "$IP_ADDRESS" = "" ]; then
      IPINFO=$(curl -sf4 https://ipinfo.io | jq -r '.ip')
      IP_ADDRESS=$([[ "$IPINFO" =~ ^[1-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[0-9][0-9]?[0-9]?\.[1-9][0-9]?[0-9]?$ ]] && echo "$IPIFY" || echo "")
    fi

    echo $IP_ADDRESS
  elif [ "$RRTYPE" == "AAAA" ]; then
    # if dns method fails, use http method
    IP_ADDRESS=$(curl -sf6 https://ifconfig.co)

    echo $IP_ADDRESS
  fi
}

getDnsRecordName() {
  if [ ! -z "$SUBDOMAIN" ]; then
    echo $SUBDOMAIN.$ZONE
  else
    echo $ZONE
  fi
}

verifyToken() {
  if [ -z "$EMAIL" ]; then
    cloudflare -o /dev/null -w "%{http_code}" "$CF_API"/user/tokens/verify
  else
    cloudflare -o /dev/null -w "%{http_code}" "$CF_API"/user
  fi
}

getZoneId() {
  cloudflare "$CF_API/zones?name=$ZONE" | jq -r '.result[0].id'
}

getDnsRecordId() {
  cloudflare "$CF_API/zones/$1/dns_records?type=$RRTYPE&name=$2" | jq -r '.result[0].id'
}

createDnsRecord() {
  if [[ "$PROXIED" != "true" && "$PROXIED" != "false" ]]; then
    PROXIED="false"
  fi

  cloudflare -X POST -d "{\"type\": \"$RRTYPE\",\"name\":\"$2\",\"content\":\"$3\",\"proxied\":$PROXIED,\"ttl\":1 }" "$CF_API/zones/$1/dns_records" | jq -r '.result.id'
}

updateDnsRecord() {
  if [[ "$PROXIED" != "true" && "$PROXIED" != "false" ]]; then
    PROXIED="false"
  fi

  cloudflare -X PATCH -d "{\"type\": \"$RRTYPE\",\"name\":\"$3\",\"content\":\"$4\",\"proxied\":$PROXIED }" "$CF_API/zones/$1/dns_records/$2" | jq -r '.result.id'
}

deleteDnsRecord() {
  cloudflare -X DELETE "$CF_API/zones/$1/dns_records/$2" | jq -r '.result.id'
}

getDnsRecordIp() {
  cloudflare "$CF_API/zones/$1/dns_records/$2" | jq -r '.result.content'
}
