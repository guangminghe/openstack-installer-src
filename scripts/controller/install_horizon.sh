#!/usr/bin/env bash

set -x

function install_configure_horizon()
{
	# yum -y install openstack-dashboard
	UPPER_PATH=$(dirname ${TOP_PATH})
	OPENSTACK_PATH=${UPPER_PATH}/openstack
	cd ${OPENSTACK_PATH}
	git clone git://git.openstack.org/openstack/horizon
	HORIZON_PATH=${OPENSTACK_PATH}/horizon
	cd ${HORIZON_PATH}
	git checkout -b ocata remotes/origin/stable/ocata
	# pip install -r requirements.txt
	pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org -r requirements.txt
	python setup.py install

	cp ${TOP_PATH}/horizon/etc/httpd/conf.d/openstack-dashboard.conf /etc/httpd/conf.d/
	mkdir /etc/openstack-dashboard
	cp openstack_dashboard/local/local_settings.py.example /etc/openstack-dashboard/local_settings

	cp ${TOP_PATH}/horizon/etc/openstack-dashboard/* /etc/openstack-dashboard/
	cd ${TOP_PATH}
	if [[ $? -eq 0 ]]
	then
cat >> /etc/openstack-dashboard/local_settings <<EOF
OPENSTACK_HOST = "${CONTROLLER_NODE_HOSTNAME}"

ALLOWED_HOSTS = ['*', ]

SESSION_ENGINE = 'django.contrib.sessions.backends.cache'

CACHES = {
    'default': {
         'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
         'LOCATION': '${CONTROLLER_NODE_HOSTNAME}:11211',
    }
}

OPENSTACK_KEYSTONE_URL = "http://%s:5000/v3" % OPENSTACK_HOST

OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True

OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 2,
}

OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "Default"

OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"

OPENSTACK_NEUTRON_NETWORK = {
    'enable_router': False,
    'enable_quotas': False,
    'enable_distributed_router': False,
    'enable_ha_router': False,
    'enable_lb': False,
    'enable_firewall': False,
    'enable_vpn': False,
    'enable_fip_topology_check': False,
}

EOF
	
	ln -s  /etc/openstack-dashboard/local_settings /usr/lib/python2.7/site-packages/openstack_dashboard/local/local_settings.py
	sed -i -e "s/^STATIC_ROOT =.*/STATIC_ROOT = '\/usr\/lib\/python2.7\/site-packages\/openstack_dashboard\/static'/g" /usr/lib/python2.7/site-packages/openstack_dashboard/settings.py
	
	
	sed -i -e "s/zh-cn/zh-hans/g" /usr/lib/python2.7/site-packages/openstack_dashboard/settings.py
	mv /usr/lib/python2.7/site-packages/openstack_dashboard/locale/zh-CN /usr/lib/python2.7/site-packages/openstack_dashboard/locale/zh-Hans
	
	sed -i -e "s/^WEBROOT =.*/WEBROOT = '\/dashboard\/'/g" /etc/openstack-dashboard/local_settings
	sed -i -e "s/^#POLICY_FILES_PATH =.*/POLICY_FILES_PATH = '\/etc\/openstack-dashboard'/g" /etc/openstack-dashboard/local_settings

	chown -R apache /usr/lib/python2.7/site-packages/openstack_dashboard
	pip uninstall -y python-novaclient
	cd ${OPENSTACK_PATH}
	git clone git://git.openstack.org/openstack/python-novaclient
	NOVACLIENT_PATH=${OPENSTACK_PATH}/python-novaclient
	cd ${NOVACLIENT_PATH}
	git checkout -b ocata remotes/origin/stable/ocata
	python setup.py install
	else
		echo "Install or configure horizon failed!"
	fi
}

function finalize_installation()
{
	systemctl restart httpd.service memcached.service
}

function set_firewall()
{
	# firewall-cmd --zone=public --add-port=80/tcp --permanen		# for dashboard
	# firewall-cmd --zone=public --add-port=6080/tcp --permanen	# for instance vnc
	# firewall-cmd --reload
	
	systemctl disable firewalld
	systemctl stop firewalld
}

if [[ -f ${TOP_PATH}/scripts/functions.sh ]]
then
        source ${TOP_PATH}/scripts/functions.sh
else
        echo "ERROR: Cann't access ${TOP_PATH}/scripts/functions.sh. Exit..."
        exit 1
fi

install_configure_horizon
finalize_installation
set_firewall

