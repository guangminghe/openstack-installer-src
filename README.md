# openstack-installer-src
支持在双网卡机器上，通过源码安装OpenStack的Ocata版本。<br>
使用Linux Bridge。<br>
<br>
执行以下步骤：<br>
1.安装CentOS 7.2 x86_64或者CentOS 7.3 x86_64，安装过程中选择“Web Server”组件。<br>
2.配置网络。<br>
　　2.1 将管理网口配置成固定IP；<br>
　　2.2 配置另一个网口作为provider interface。修改网口对应的配置文件。假设网口名为INTERFACE_NAME，则修改文件/etc/sysconfig/network-scripts/ifcfg-INTERFACE_NAME，保持HWADDR和UUID不变，确认以下字段修改成对应的值：<br>
　　　　DEVICE=INTERFACE_NAME<br>
　　　　TYPE=Ethernet<br>
　　　　ONBOOT="yes"<br>
　　　　BOOTPROTO="none"<br>
　　2.3 重启网络或者重启机器<br>
4.根据需要修改config/config.sh。<br>
5.执行脚本：<br>
　　./main.sh allinone<br>