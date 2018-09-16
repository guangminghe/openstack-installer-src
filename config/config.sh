#!/usr/bin/env bash

DEFAULT_PASS="456123"

CONTROLLER_NODE_HOSTNAME="controller"
CONTROLLER_NODE_IP="192.168.1.11"

COMPUTE_NODE_HOSTNAME="compute"
COMPUTE_NODE_IP="10.0.0.12"

NTP_SERVERS="0.centos.pool.ntp.org 1.centos.pool.ntp.org 2.centos.pool.ntp.org 3.centos.pool.ntp.org"
SUBNET="192.168.1.0/24"

PROVIDER_INTERFACE_NAME=enp0s8

DB_PASS=$DEFAULT_PASS
RABBIT_PASS=$DEFAULT_PASS
KEYSTONE_DBPASS=$DEFAULT_PASS
ADMIN_PASS=$DEFAULT_PASS
DEMO_PASS=$DEFAULT_PASS
GLANCE_DBPASS=$DEFAULT_PASS
GLANCE_PASS=$DEFAULT_PASS
NOVA_DBPASS=$DEFAULT_PASS
NOVA_PASS=$DEFAULT_PASS
PLACEMENT_PASS=$DEFAULT_PASS
NEUTRON_DBPASS=$DEFAULT_PASS
NEUTRON_PASS=$DEFAULT_PASS
METADATA_SECRET=$DEFAULT_PASS
