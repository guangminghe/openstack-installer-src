#!/usr/bin/env bash

set -x

TEMP_PATH=${TOP_PATH}/../openstack_installer_temp

function create_database()
{
	db_cmd="mysql --user=root --password=${DB_PASS}"
	echo "CREATE DATABASE neutron;" | ${db_cmd}

	echo "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '${NEUTRON_DBPASS}';" | ${db_cmd}
	echo "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '${NEUTRON_DBPASS}';" | ${db_cmd}

	echo "FLUSH PRIVILEGES;" | ${db_cmd}
	echo "quit" | ${db_cmd}
}

function create_neutron_credential()
{
	source ${TEMP_PATH}/admin-openrc

	openstack user create neutron --domain default --password ${NEUTRON_PASS}
	openstack role add --project service --user neutron admin
	openstack service create --name neutron \
	  --description "OpenStack Networking" network

	openstack endpoint create --region RegionOne \
	  network public http://${CONTROLLER_NODE_HOSTNAME}:9696

	openstack endpoint create --region RegionOne \
	  network internal http://${CONTROLLER_NODE_HOSTNAME}:9696

	openstack endpoint create --region RegionOne \
	  network admin http://${CONTROLLER_NODE_HOSTNAME}:9696
}

function provider_networks()
{
	# yum -y install openstack-neutron openstack-neutron-ml2 \
	#   openstack-neutron-linuxbridge ebtables
	# yum -y install ebtables
	yum -y install novnc
	UPPER_PATH=$(dirname ${TOP_PATH})
	OPENSTACK_PATH=${UPPER_PATH}/openstack
	mkdir -p ${OPENSTACK_PATH}
	cd ${OPENSTACK_PATH}
	
	git clone git://git.openstack.org/openstack/neutron-lib
	NEUTRON_LIB_PATH=${OPENSTACK_PATH}/neutron-lib
	cd ${NEUTRON_LIB_PATH}
	git checkout -b ocata remotes/origin/stable/ocata
	python setup.py install
	
	cd ${OPENSTACK_PATH}
	git clone git://git.openstack.org/openstack/neutron
	NEUTRON_PATH=${OPENSTACK_PATH}/neutron
	cd ${NEUTRON_PATH}
	git checkout -b ocata remotes/origin/stable/ocata
	sed -i -e "/neutron-lib/d" requirements.txt
	pip install -r requirements.txt
	pip install psycopg2-binary
	python setup.py install

	tools/generate_config_file_samples.sh

	mkdir /etc/neutron/
	cd etc
	cp api-paste.ini /etc/neutron/
	cp policy.json /etc/neutron/
	cp rootwrap.conf /etc/neutron/
	cp dhcp_agent.ini.sample /etc/neutron/dhcp_agent.ini
	cp l3_agent.ini.sample /etc/neutron/l3_agent.ini
	cp metadata_agent.ini.sample /etc/neutron/metadata_agent.ini
	cp metering_agent.ini.sample /etc/neutron/metering_agent.ini
	cp neutron.conf.sample /etc/neutron/neutron.conf

	cp -a neutron/plugins /etc/neutron/
	cd /etc/neutron/plugins/ml2/
	mv linuxbridge_agent.ini.sample linuxbridge_agent.ini
	mv macvtap_agent.ini.sample macvtap_agent.ini
	mv ml2_conf.ini.sample ml2_conf.ini
	mv openvswitch_agent.ini.sample openvswitch_agent.ini
	mv sriov_agent.ini.sample sriov_agent.ini

	# from rdo
	cp -a ${TOP_PATH}/neutron/etc/neutron/conf.d /etc/neutron/
	cp ${TOP_PATH}/neutron/usr/bin/neutron-enable-bridge-firewall.sh /usr/bin/
	chmod +x /usr/bin/neutron-enable-bridge-firewall.sh
	cp -a ${TOP_PATH}/neutron/usr/share/neutron /usr/share/
	
	cd ${TOP_PATH}

	crudini --set /etc/neutron/neutron.conf database connection mysql+pymysql://neutron:${NEUTRON_DBPASS}@${CONTROLLER_NODE_HOSTNAME}/neutron

	crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
	crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins ""

	crudini --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://openstack:${RABBIT_PASS}@${CONTROLLER_NODE_HOSTNAME}
	crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone

	crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_uri http://${CONTROLLER_NODE_HOSTNAME}:5000
	crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://${CONTROLLER_NODE_HOSTNAME}:35357
	crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers ${CONTROLLER_NODE_HOSTNAME}:11211
	crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
	crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name default
	crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name default
	crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
	crudini --set /etc/neutron/neutron.conf keystone_authtoken username neutron
	crudini --set /etc/neutron/neutron.conf keystone_authtoken password ${NEUTRON_PASS}

	crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes true
	crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes true

	crudini --set /etc/neutron/neutron.conf nova auth_url http://${CONTROLLER_NODE_HOSTNAME}:35357
	crudini --set /etc/neutron/neutron.conf nova auth_type password
	crudini --set /etc/neutron/neutron.conf nova project_domain_name default
	crudini --set /etc/neutron/neutron.conf nova user_domain_name default
	crudini --set /etc/neutron/neutron.conf nova region_name RegionOne
	crudini --set /etc/neutron/neutron.conf nova project_name service
	crudini --set /etc/neutron/neutron.conf nova username nova
	crudini --set /etc/neutron/neutron.conf nova password ${NOVA_PASS}

	crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp

	crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers flat,vlan
	crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types ""
	crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers linuxbridge
	crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security

	crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks provider

	crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset true

	crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini linux_bridge physical_interface_mappings provider:${PROVIDER_INTERFACE_NAME}
	crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan false
	crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup enable_security_group true
	crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

	crudini --set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver linuxbridge
	crudini --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
	crudini --set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata true
}

function configure_metadata_aggent()
{
	crudini --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_ip ${CONTROLLER_NODE_HOSTNAME}
	crudini --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret ${METADATA_SECRET}
}

function configure_compute_service()
{
	crudini --set /etc/nova/nova.conf neutron url http://${CONTROLLER_NODE_HOSTNAME}:9696
	crudini --set /etc/nova/nova.conf neutron auth_url http://${CONTROLLER_NODE_HOSTNAME}:35357
	crudini --set /etc/nova/nova.conf neutron auth_type password
	crudini --set /etc/nova/nova.conf neutron project_domain_name default
	crudini --set /etc/nova/nova.conf neutron user_domain_name default
	crudini --set /etc/nova/nova.conf neutron region_name RegionOne
	crudini --set /etc/nova/nova.conf neutron project_name service
	crudini --set /etc/nova/nova.conf neutron username neutron
	crudini --set /etc/nova/nova.conf neutron password ${NEUTRON_PASS}
	crudini --set /etc/nova/nova.conf neutron service_metadata_proxy true
	crudini --set /etc/nova/nova.conf neutron metadata_proxy_shared_secret ${METADATA_SECRET}
}

function finalize_installation()
{
	ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
	groupadd neutron
	useradd -g neutron -c "OpenStack Neutron Daemons" -d /var/lib/neutron -s /sbin/nologin neutron
	su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
	  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

	 systemctl restart openstack-nova-api.service

cat > /usr/lib/systemd/system/neutron-server.service <<EOF
[Unit]
Description=OpenStack Neutron Server
After=syslog.target network.target

[Service]
Type=notify
#use root user
#User=neutron
User=root
ExecStart=/usr/bin/neutron-server --config-file /usr/share/neutron/neutron-dist.conf --config-dir /usr/share/neutron/server --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugin.ini --config-dir /etc/neutron/conf.d/common --config-dir /etc/neutron/conf.d/neutron-server --log-file /var/log/neutron/server.log
PrivateTmp=trueNotifyAccess=all
KillMode=process
Restart=on-failure
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target

EOF


cat > /usr/lib/systemd/system/neutron-linuxbridge-agent.service <<EOF
[Unit]
Description=OpenStack Neutron Linux Bridge Agent
After=syslog.target network.target

[Service]
Type=simple
#use root user
#User=neutron
User=root
PermissionsStartOnly=true
ExecStartPre=/usr/bin/neutron-enable-bridge-firewall.sh
ExecStart=/usr/bin/neutron-linuxbridge-agent --config-file /usr/share/neutron/neutron-dist.conf --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/linuxbridge_agent.ini --config-dir /etc/neutron/conf.d/common --config-dir /etc/neutron/conf.d/neutron-linuxbridge-agent --log-file /var/log/neutron/linuxbridge-agent.log
PrivateTmp=true
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target

EOF


cat > /usr/lib/systemd/system/neutron-dhcp-agent.service <<EOF
[Unit]
Description=OpenStack Neutron DHCP Agent
After=syslog.target network.target

[Service]
Type=simple
#use root user
#User=neutron
User=root
ExecStart=/usr/bin/neutron-dhcp-agent --config-file /usr/share/neutron/neutron-dist.conf --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/dhcp_agent.ini --config-dir /etc/neutron/conf.d/common --config-dir /etc/neutron/conf.d/neutron-dhcp-agent --log-file /var/log/neutron/dhcp-agent.log
PrivateTmp=false
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target

EOF

cat > /usr/lib/systemd/system/neutron-metadata-agent.service <<EOF
[Unit]
Description=OpenStack Neutron Metadata Agent
After=syslog.target network.target

[Service]
Type=simple
#use root user
#User=neutron
User=root
ExecStart=/usr/bin/neutron-metadata-agent --config-file /usr/share/neutron/neutron-dist.conf --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/metadata_agent.ini --config-dir /etc/neutron/conf.d/common --config-dir /etc/neutron/conf.d/neutron-metadata-agent --log-file /var/log/neutron/metadata-agent.log
PrivateTmp=falseKillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target

EOF

	mkdir /var/log/neutron
	systemctl daemon-reload
	systemctl enable neutron-server.service \
	neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
	neutron-metadata-agent.service
	
	systemctl start neutron-server.service \
	neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
	neutron-metadata-agent.service


	# systemctl enable neutron-l3-agent.service
	# systemctl start neutron-l3-agent.service
}

if [[ -f ${TOP_PATH}/scripts/functions.sh ]]
then
        source ${TOP_PATH}/scripts/functions.sh
else
        echo "ERROR: Cann't access ${TOP_PATH}/scripts/functions.sh. Exit..."
        exit 1
fi

create_database
create_neutron_credential
provider_networks
configure_metadata_aggent
configure_compute_service
finalize_installation

