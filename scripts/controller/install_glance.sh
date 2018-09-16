#!/usr/bin/env bash

set -x

TEMP_PATH=${TOP_PATH}/../openstack_installer_temp

function create_database()
{
	db_cmd="mysql --user=root --password=${DB_PASS}"
	echo "CREATE DATABASE glance;" | ${db_cmd}
	echo "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '${GLANCE_DBPASS}';" | ${db_cmd}
	echo "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '${GLANCE_DBPASS}';" | ${db_cmd}
	echo "FLUSH PRIVILEGES;" | ${db_cmd}
	echo "quit" | ${db_cmd}
}

function create_glance_credential()
{
	source ${TEMP_PATH}/admin-openrc

	openstack user create glance --domain default --password ${GLANCE_PASS}

	openstack role add --project service --user glance admin

	openstack service create --name glance \
	  --description "OpenStack Image" image

	openstack endpoint create --region RegionOne \
	  image public http://${CONTROLLER_NODE_HOSTNAME}:9292

	openstack endpoint create --region RegionOne \
	  image internal http://${CONTROLLER_NODE_HOSTNAME}:9292

	openstack endpoint create --region RegionOne \
	  image admin http://${CONTROLLER_NODE_HOSTNAME}:9292
}

function install_configure_glance()
{
	# yum -y install openstack-glance
	UPPER_PATH=$(dirname ${TOP_PATH})
	OPENSTACK_PATH=${UPPER_PATH}/openstack
	mkdir -p ${OPENSTACK_PATH}
	cd ${OPENSTACK_PATH}
	git clone git://git.openstack.org/openstack/glance
	GLANCE_PATH=${OPENSTACK_PATH}/glance
	cd ${GLANCE_PATH}
	git checkout -b ocata remotes/origin/stable/ocata
	pip install -r requirements.txt
	python setup.py install

	mkdir -p /etc/glance
	cd etc
	cp -a * /etc/glance/
	cd /etc/glance/
	mv glance-swift.conf.sample glance-swift.conf
	mv ovf-metadata.json.sample ovf-metadata.json
	mv property-protections-policies.conf.sample property-protections-policies.conf
	mv property-protections-roles.conf.sample property-protections-roles.conf
	
	cd ${TOP_PATH}

	if [[ $? -eq 0 ]]
	then
		crudini --set /etc/glance/glance-api.conf database connection mysql+pymysql://glance:${GLANCE_DBPASS}@${CONTROLLER_NODE_HOSTNAME}/glance
		crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_uri http://${CONTROLLER_NODE_HOSTNAME}:5000
		crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_url http://${CONTROLLER_NODE_HOSTNAME}:35357
		crudini --set /etc/glance/glance-api.conf keystone_authtoken memcached_servers ${CONTROLLER_NODE_HOSTNAME}:11211
		crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_type password
		crudini --set /etc/glance/glance-api.conf keystone_authtoken project_domain_name default
		crudini --set /etc/glance/glance-api.conf keystone_authtoken user_domain_name default
		crudini --set /etc/glance/glance-api.conf keystone_authtoken project_name service
		crudini --set /etc/glance/glance-api.conf keystone_authtoken username glance
		crudini --set /etc/glance/glance-api.conf keystone_authtoken password ${GLANCE_PASS}


		crudini --set /etc/glance/glance-api.conf paste_deploy flavor keystone

		crudini --set /etc/glance/glance-api.conf glance_store stores file,http
		crudini --set /etc/glance/glance-api.conf glance_store default_store file
		crudini --set /etc/glance/glance-api.conf glance_store filesystem_store_datadir /var/lib/glance/images/

		crudini --set /etc/glance/glance-registry.conf database connection mysql+pymysql://glance:${GLANCE_DBPASS}@${CONTROLLER_NODE_HOSTNAME}/glance
		crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_uri http://${CONTROLLER_NODE_HOSTNAME}:5000
		crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_url http://${CONTROLLER_NODE_HOSTNAME}:35357
		crudini --set /etc/glance/glance-registry.conf keystone_authtoken memcached_servers ${CONTROLLER_NODE_HOSTNAME}:11211
		crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_type password
		crudini --set /etc/glance/glance-registry.conf keystone_authtoken project_domain_name default
		crudini --set /etc/glance/glance-registry.conf keystone_authtoken user_domain_name default
		crudini --set /etc/glance/glance-registry.conf keystone_authtoken project_name service
		crudini --set /etc/glance/glance-registry.conf keystone_authtoken username glance
		crudini --set /etc/glance/glance-registry.conf keystone_authtoken password ${GLANCE_PASS}

		crudini --set /etc/glance/glance-registry.conf paste_deploy flavor keystone

		groupadd glance
		useradd -g glance -c "OpenStack glance Daemons" -d /var/lib/glance -s /sbin/nologin glance
		sed -i -e "s/, enforce_type=True//g" /usr/lib/python2.7/site-packages/glance/cmd/manage.py
		su -s /bin/sh -c "glance-manage db_sync" glance

cat > /usr/lib/systemd/system/openstack-glance-api.service <<EOF
[Unit]
Description=OpenStack Image Service (code-named Glance) API server
After=syslog.target network.target

[Service]
LimitNOFILE=131072
LimitNPROC=131072
Type=simple
#use root user
#User=glance
User=root
ExecStart=/usr/bin/glance-api
PrivateTmp=true
Restart=on-failure

[Install]
WantedBy=multi-user.target


EOF

cat > /usr/lib/systemd/system/openstack-glance-registry.service <<EOF
[Unit]
Description=OpenStack Image Service (code-named Glance) Registry server
After=syslog.target network.target

[Service]
Type=simple
#use root user
#User=glance
User=root
ExecStart=/usr/bin/glance-registry
PrivateTmp=true
Restart=on-failure

[Install]
WantedBy=multi-user.target


EOF

		systemctl enable openstack-glance-api.service \
		  openstack-glance-registry.service

		systemctl start openstack-glance-api.service \
		  openstack-glance-registry.service
	else
		echo "Install or configure glance failed!"
	fi
}

function verify_glance()
{
	source ${TEMP_PATH}/admin-openrc

	wget -P ${TOP_PATH} http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img

	openstack image create "cirros" \
	  --file ${TOP_PATH}/cirros-0.3.5-x86_64-disk.img \
	  --disk-format qcow2 --container-format bare \
	  --public
	if [[ $? -ne 0 ]]
	then
		echo "sleep 5 ..."
		sleep 5
		openstack image create "cirros" \
		  --file ${TOP_PATH}/cirros-0.3.5-x86_64-disk.img \
		  --disk-format qcow2 --container-format bare \
		  --public
	fi

	openstack image list
}

if [[ -f ${TOP_PATH}/scripts/functions.sh ]]
then
        source ${TOP_PATH}/scripts/functions.sh
else
        echo "ERROR: Cann't access ${TOP_PATH}/scripts/functions.sh. Exit..."
        exit 1
fi

create_database
create_glance_credential
install_configure_glance
verify_glance

