#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_DIR="$SCRIPT_DIR/logs"
USER_LIST_DIR="$SCRIPT_DIR/user_list"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
ROUTING_DIR="$SCRIPT_DIR/routing"

REDSOCKS_LOG_DIR="$LOG_DIR/redsocks"

REDSOCKS_CONFIG="$SCRIPT_DIR/redsocks.conf"
IPSET_NAME="proxy_domains" # address set name for ipset
IPSET_MAX_ELEMENTS=1000000 # max number of elements in ipset
DNS_SERVER_PARSE="9.9.9.9" # DNS for parse domains
DNS_SERVER_LAN="10.0.0.1, 8.8.4.4" # DNS that will be issued on the LAN interface
