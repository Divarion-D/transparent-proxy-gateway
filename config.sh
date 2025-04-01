#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_DIR="$SCRIPT_DIR/logs"
REDSOCKS_LOG_DIR="$LOG_DIR/redsocks"

CONFIG_DIR="$SCRIPT_DIR/config"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
ROUTING_DIR="$SCRIPT_DIR/routing"

DOMAIN_LIST="$CONFIG_DIR/domains.txt"
IPS_LIST="$CONFIG_DIR/ips.txt"
REDSOCKS_CONFIG="$CONFIG_DIR/redsocks.conf"
CACHE_FILE_V4="$CONFIG_DIR/cache_v4.txt"
CACHE_FILE_V6="$CONFIG_DIR/cache_v6.txt"

IPSET_NAME="proxy_domains" # address set name for ipset
DNS_SERVER_PARSE="9.9.9.9" # DNS for parse domains
DNS_SERVER_LAN="8.8.8.8, 8.8.4.4" # DNS that will be issued on the LAN interface
