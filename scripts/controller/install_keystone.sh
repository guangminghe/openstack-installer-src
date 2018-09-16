#!/usr/bin/env bash

set -x

TEMP_PATH=${TOP_PATH}/../openstack_installer_temp

function create_database()
{
	db_cmd="mysql --user=root --password=${DB_PASS}"
	echo "CREATE DATABASE keystone;" | ${db_cmd}
	echo "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '${KEYSTONE_DBPASS}';" | ${db_cmd}
	echo "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}';" | ${db_cmd}
	echo "FLUSH PRIVILEGES;" | ${db_cmd}
	echo "quit" | ${db_cmd}
}

function install_configure_keystone()
{
	# yum -y install openstack-keystone httpd mod_wsgi
	yum -y install httpd mod_wsgi

	UPPER_PATH=$(dirname ${TOP_PATH})
	OPENSTACK_PATH=${UPPER_PATH}/openstack
	mkdir -p ${OPENSTACK_PATH}
	cd ${OPENSTACK_PATH}
	yum -y install git
	git clone git://git.openstack.org/openstack/keystone
	KEYSTONE_PATH=${OPENSTACK_PATH}/keystone
	cd ${KEYSTONE_PATH}
	git checkout -b ocata remotes/origin/stable/ocata
	yum -y install python-pip
	yum -y install gcc
	yum -y install python-devel
	pip install -r requirements.txt
	python setup.py install

	mkdir -p /etc/keystone
	cd etc
	cp keystone-paste.ini /etc/keystone/
	cp keystone.conf.sample /etc/keystone/keystone.conf

	cp logging.conf.sample /etc/keystone/logging.conf
	cp default_catalog.templates policy.json policy.v3cloudsample.json sso_callback_template.html /etc/keystone/
	cd ..

	cd ${TOP_PATH}

	if [[ $? -eq 0 ]]
	then
		crudini --set /etc/keystone/keystone.conf database connection "mysql+pymysql://keystone:${KEYSTONE_DBPASS}@${CONTROLLER_NODE_HOSTNAME}/keystone"
		crudini --set /etc/keystone/keystone.conf token provider fernet

		groupadd keystone
		useradd -g keystone -c "OpenStack Keystone Daemons" -d /var/lib/keystone -s /sbin/nologin keystone
		su -s /bin/sh -c "keystone-manage db_sync" keystone

		keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
		keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

		keystone-manage bootstrap --bootstrap-password ${ADMIN_PASS} \
		  --bootstrap-admin-url http://${CONTROLLER_NODE_HOSTNAME}:35357/v3/ \
		  --bootstrap-internal-url http://${CONTROLLER_NODE_HOSTNAME}:5000/v3/ \
		  --bootstrap-public-url http://${CONTROLLER_NODE_HOSTNAME}:5000/v3/ \
		  --bootstrap-region-id RegionOne

		sed -i -e "s/^#ServerName.*/ServerName ${CONTROLLER_NODE_HOSTNAME}/g" /etc/httpd/conf/httpd.conf

		cd ${KEYSTONE_PATH}
		mkdir -p /usr/share/keystone
		cp httpd/wsgi-keystone.conf /usr/share/keystone
		# cp ${KEYSTONE_PATH}/httpd/* /usr/share/keystone/
		ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
		cd ${TOP_PATH}

		systemctl enable httpd.service

		mkdir -p /var/log/keystone
		sed -i -e "s/apache2/keystone/g" /usr/share/keystone/wsgi-keystone.conf
		ln -s /usr/bin/keystone-wsgi-admin /usr/local/bin/keystone-wsgi-admin
		ln -s /usr/bin/keystone-wsgi-public /usr/local/bin/keystone-wsgi-public
		ln -s /usr/bin/keystone-manage /usr/local/bin/keystone-manage
		getenforce
		setenforce 0
		sed -i -e "s/^SELINUX=.*/SELINUX=disabled/g" /etc/sysconfig/selinux
		sed -i -e "s/^SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config
		getenforce
		systemctl start httpd.service

		admin_rcfile="admin-openrc-temp"
cat > ${TEMP_PATH}/${admin_rcfile} <<EOF
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PASS}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://${CONTROLLER_NODE_HOSTNAME}:35357/v3
export OS_IDENTITY_API_VERSION=3
EOF
		source ${TEMP_PATH}/${admin_rcfile}
		# rm -f ${admin_rcfile}
	else
		echo "install or configure keystone failed!"
	fi
}

function install_configure_openstackclient()
{
        UPPER_PATH=$(dirname ${TOP_PATH})
        OPENSTACK_PATH=${UPPER_PATH}/openstack
        mkdir -p ${OPENSTACK_PATH}
        cd ${OPENSTACK_PATH}
        git clone git://git.openstack.org/openstack/openstackclient
        OPENSTACKCLIENT_PATH=${OPENSTACK_PATH}/openstackclient
        cd ${OPENSTACKCLIENT_PATH}
	pip install -U setuptools
        pip install -r requirements.txt
        python setup.py install

        cd ${TOP_PATH}
}

function create_domain_projects_users_roles()
{
	pip install -U six
	openstack project create --domain default \
	  --description "Service Project" service

	openstack project create --domain default \
	  --description "Demo Project" demo

	openstack user create demo --domain default \
	  --password ${DEMO_PASS}

	openstack role create user

	openstack role add --project demo --user demo user
}

function keystone_verify()
{
	# Todo
	# https://docs.openstack.org/ocata/install-guide-rdo/keystone-verify.html
	# 修改文件/etc/keystone/keystone-paste.ini

	unset OS_AUTH_URL OS_PASSWORD

	openstack --os-auth-url http://controller:35357/v3 \
	  --os-project-domain-name default --os-user-domain-name default \
	  --os-project-name admin --os-username admin --os-password ${ADMIN_PASS} token issue

	openstack --os-auth-url http://controller:5000/v3 \
	  --os-project-domain-name default --os-user-domain-name default \
	  --os-project-name demo --os-username demo --os-password ${DEMO_PASS} token issue
}

function create_openrc()
{
cat > ${TEMP_PATH}/admin-openrc <<EOF
export OS_USERNAME=admin
export OS_PASSWORD=${ADMIN_PASS}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://${CONTROLLER_NODE_HOSTNAME}:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

cat > ${TEMP_PATH}/demo-openrc <<EOF
export OS_USERNAME=demo
export OS_PASSWORD=${DEMO_PASS}
export OS_PROJECT_NAME=demo
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://${CONTROLLER_NODE_HOSTNAME}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
}

function use_scripts()
{
	source ${TEMP_PATH}/demo-openrc
	openstack token issue

	source ${TEMP_PATH}/admin-openrc
	openstack token issue
}

if [[ -f ${TOP_PATH}/scripts/functions.sh ]]
then
        source ${TOP_PATH}/scripts/functions.sh
else
        echo "ERROR: Cann't access ${TOP_PATH}/scripts/functions.sh. Exit..."
        exit 1
fi

create_database
install_configure_keystone
install_configure_openstackclient
create_domain_projects_users_roles
keystone_verify
create_openrc
use_scripts

