#!/bin/bash
########################################################################################
# BuildVPN.sh
########################################################################################
# [Description]: Script to automate the buildout of OpenVPN servers and clients.
########################################################################################

# Global Variables
openvpn_dir='/etc/openvpn'
easyrsa_tmp='/usr/share/doc/openvpn/examples/easy-rsa/2.0'
easyrsa_dir='/etc/openvpn/easy-rsa'
ovpnkey_dir='/etc/openvpn/easy-rsa/keys'
ovpnsvr_cnf='/etc/openvpn/server.conf'

# Title Function
func_title(){
  # Clear (For Prettyness)
  clear

  # Print Title
  echo '============================================================================'
  echo ' BuildVPN.sh | [Version]: 1.4.0 | [Updated]: 08.28.2013'
  echo '============================================================================'
  echo ' [By]: Michael Wright | [GitHub]: https://github.com/themightyshiv'
  echo '============================================================================'
  echo
}

# Server Install Function
func_install(){
  # Install Packages Through Apt-Get
  apt-get -y install openvpn openssl
  echo
}

# Server Buildout Function
func_build_server(){
  # Get User Input
  echo '[ Supported Operating Systems ]'
  echo
  echo ' 1 = Debian (5/6/7)'
  echo ' 2 = Ubuntu (12.04)'
  echo
  read -p 'Enter Operating System..........................: ' os
  # Retry For People Who Don't Read Well
  if [ "${os}" != '1' ] && [ "${os}" != '2' ]
  then
    clear
    func_title
    func_build_server
  fi
  read -p 'Enter Server Hostname...........................: ' host
  echo
  echo '+----------------------+'
  echo '| Available Interfaces |'
  echo '+----------------------+'
  ifconfig |awk "/Link|inet/"|tr -s '[:space:]'|sed 's/ Link.*//g'|sed -e ':a;N;$!ba;s/\n inet//g' -e 's/addr://g'|cut -d" " -f 1,2|sed 's/ /\t/g'
  echo
  read -p 'Enter IP OpenVPN Server Will Bind To............: ' ip
  read -p 'Enter Subnet For VPN (ex: 192.168.100.0)........: ' vpnnet
  read -p 'Enter Subnet Netmask (ex: 255.255.255.0)........: ' netmsk
  read -p 'Enter Preferred DNS Server (ex: 208.67.222.222).: ' dns
  read -p 'Enter Max Clients Threshold.....................: ' maxconn
  read -p 'Increase Encryption Key Size To 2048 (y/n)......: ' incbits
  read -p 'Route All Traffic Through This VPN (y/n)........: ' routeall
  read -p 'Allow Certificates With Same Subject (y/n)......: ' unique
  read -p 'Enable IP Forwarding (y/n)......................: ' forward
  # Determine What IP Protocols To Forward For
  if [[ "${forward}" == [yY] ]]
  then
    read -p 'Forward IPv4 (y/n)..............................: ' forward4
    read -p 'Forward IPv6 (y/n)..............................: ' forward6
  fi
  read -p 'Enable IPTables Masquerading (y/n)..............: ' enablenat
  # Determine What Interface To Use For Masquerading
  if [[ "${enablenat}" == [yY] ]]
  then
    read -p 'Enter Interface To Use For NAT..................: ' natif
  fi

  # Build Certificate Authority
  func_title
  echo '[*] Preparing Directories'
  cp -R ${easyrsa_tmp} ${easyrsa_dir}
  cd ${easyrsa_dir}
  # Modify OpenSSL Variables For 2048 Bit Encryption
  if [[ "${incbits}" == [yY] ]]
  then
    sed -i 's/KEY_SIZE=1024/KEY_SIZE=2048/g' vars
  fi
  # Workaround For Ubuntu 12.x
  if [ "${os}" == '2' ]
  then
    echo '[*] Preparing Ubuntu Config File'
    cp openssl-1.0.0.cnf openssl.cnf
  fi
  echo '[*] Resetting Variables'
  . ./vars >> /dev/null
  echo '[*] Preparing Build Configurations'
  ./clean-all >> /dev/null
  echo '[*] Building Certificate Authority'
  ./build-ca
  func_title
  echo '[*] Building Key Server'
  ./build-key-server ${host}
  func_title
  echo '[*] Generating Diffie Hellman Key'
  ./build-dh
  func_title
  cd ${ovpnkey_dir}
  echo '[*] Generating TLS-Auth Key'
  openvpn --genkey --secret ta.key

  # Build Server Configuration
  echo "[*] Creating server.conf In ${openvpn_dir}"
  echo "local ${ip}" > ${ovpnsvr_cnf}
  echo 'port 1194' >> ${ovpnsvr_cnf}
  echo 'proto udp' >> ${ovpnsvr_cnf}
  echo 'dev tun' >> ${ovpnsvr_cnf}
  echo "ca ${ovpnkey_dir}/ca.crt" >> ${ovpnsvr_cnf}
  echo "cert ${ovpnkey_dir}/${host}.crt" >> ${ovpnsvr_cnf}
  echo "key ${ovpnkey_dir}/${host}.key" >> ${ovpnsvr_cnf}
  # Determine If Increased Key Size Option Was Chosen
  if [[ "${incbits}" == [yY] ]]
  then
    echo "dh ${ovpnkey_dir}/dh2048.pem" >> ${ovpnsvr_cnf}
  else
    echo "dh ${ovpnkey_dir}/dh1024.pem" >> ${ovpnsvr_cnf}
  fi
  echo "server ${vpnnet} ${netmsk}" >> ${ovpnsvr_cnf}
  echo 'ifconfig-pool-persist ipp.txt' >> ${ovpnsvr_cnf}
  # Determine If Route All Traffic Option Was Chosen
  if [[ "${routeall}" == [yY] ]]
  then
    echo 'push "redirect-gateway def1"' >> ${ovpnsvr_cnf}
  fi
  # Determine If Unique Subjects Option Was Chosen
  if [[ "${unique}" == [yY] ]]
  then
    echo 'unique_subject = no' >> ${openvpn_dir}/easy-rsa/keys/index.txt.attr
  fi
  echo "push "dhcp-option DNS ${dns}"" >> ${ovpnsvr_cnf}
  echo 'keepalive 10 120' >> ${ovpnsvr_cnf}
  echo "tls-auth ${ovpnkey_dir}/ta.key 0" >> ${ovpnsvr_cnf}
  echo 'comp-lzo' >> ${ovpnsvr_cnf}
  echo "max-clients ${maxconn}" >> ${ovpnsvr_cnf}
  echo 'user nobody' >> ${ovpnsvr_cnf}
  echo 'group nogroup' >> ${ovpnsvr_cnf}
  echo 'persist-key' >> ${ovpnsvr_cnf}
  echo 'persist-tun' >> ${ovpnsvr_cnf}
  echo "status ${openvpn_dir}/status.log" >> ${ovpnsvr_cnf}
  echo "log ${openvpn_dir}/openvpn.log" >> ${ovpnsvr_cnf}
  echo 'verb 3' >> ${ovpnsvr_cnf}
  echo 'mute 20' >> ${ovpnsvr_cnf}

  # Determine If IPv4 Forwarding Option Was Chosen
  if [[ "${forward4}" == [yY] ]]
  then
    echo '[*] Enabling IPv4 Forwarding In /etc/sysctl.conf'
    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    echo '[*] Reloading sysctl Configuration'
    /sbin/sysctl -p >> /dev/null 2>&1
  fi

  # Determine If IPv6 Forwarding Option Was Chosen
  if [[ "${forward6}" == [yY] ]]
  then
    echo '[*] Enabling IPv6 Forwarding In /etc/sysctl.conf'
    sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
    echo '[*] Reloading sysctl Configuration'
    /sbin/sysctl -p >> /dev/null 2>&1
  fi

  # Determine If IPTables NAT Option Was Chosen
  if [[ "${enablenat}" == [yY] ]]
  then
    echo '[*] Loading IPTables Masquerading Rule Into Current Ruleset'
    /sbin/iptables -t nat -A POSTROUTING -o ${natif} -j MASQUERADE
    echo '[*] Adding IPTables Masquerading Rule To /etc/rc.local'
    sed -i "s:exit 0:/sbin/iptables -t nat -A POSTROUTING -o ${natif} -j MASQUERADE:" /etc/rc.local
    echo "exit 0" >> /etc/rc.local
  fi

  # Finish Message
  echo '[*] Server Buildout Complete'
  echo
  exit 0
}

# Build Client Certificates Function
func_build_client(){
  # Get User Input
  read -p 'Enter Username (No Spaces)......................: ' user
  read -p 'Enter Name For Configuration File (No Spaces)...: ' confname
  echo
  echo '+------------------------+'
  echo '| Available IP Addresses |'
  echo '+------------------------+'
  ifconfig |awk "/Link|inet/"|tr -s '[:space:]'|sed 's/ Link.*//g'|sed -e ':a;N;$!ba;s/\n inet//g' -e 's/addr://g'|cut -d" " -f 1,2|sed 's/ /\t/g'
  echo
  read -p 'Enter IP/Hostname OpenVPN Server Binds To.......: ' ip
  read -p 'Will This Client Run Under Windows (y/n)........: ' windows
  # Additional Configuration For Windows Clients
  if [[ "${windows}" == [yY] ]]
  then
    read -p 'Enter Node Name (Required For Windows Clients)..: ' node
  fi
  
  # Build Certificate
  func_title
  echo "[*] Generating Client Certificate For: ${user}"
  cd ${easyrsa_dir}
  . ./vars
  ./build-key ${user}
  
  # Prepare Client Build Directory
  cd ${openvpn_dir} && mkdir ${user}
  
  # Build Client Configuration
  func_title
  echo '[*] Creating Client Configuration'
  echo 'client' > ${user}/${confname}.ovpn
  echo 'dev tun' >> ${user}/${confname}.ovpn
  # Determine If Windows Options Were Chosen
  if [[ "${windows}" == [yY] ]]
  then
    echo "dev-node ${node}" >> ${user}/${confname}.ovpn
  fi
  echo 'proto udp' >> ${user}/${confname}.ovpn
  echo "remote ${ip} 1194" >> ${user}/${confname}.ovpn
  echo 'resolv-retry infinite' >> ${user}/${confname}.ovpn
  echo 'nobind' >> ${user}/${confname}.ovpn
  # Set Unprivileged User And Group For Linux Clients
  if [[ "${windows}" != [yY] ]]
  then
    echo 'user nobody' >> ${user}/${confname}.ovpn
    echo 'group nogroup' >> ${user}/${confname}.ovpn
  fi
  echo 'persist-key' >> ${user}/${confname}.ovpn
  echo 'persist-tun' >> ${user}/${confname}.ovpn
  echo 'mute-replay-warnings' >> ${user}/${confname}.ovpn
  echo '<ca>' >> ${user}/${confname}.ovpn
  cat ${ovpnkey_dir}/ca.crt >> ${user}/${confname}.ovpn
  echo '</ca>' >> ${user}/${confname}.ovpn
  echo '<cert>' >> ${user}/${confname}.ovpn
  cat ${ovpnkey_dir}/${user}.crt|awk '!/^ |Certificate:/'|sed '/^$/d' >> ${user}/${confname}.ovpn
  echo '</cert>' >> ${user}/${confname}.ovpn
  echo '<key>' >> ${user}/${confname}.ovpn
  cat ${ovpnkey_dir}/${user}.key >> ${user}/${confname}.ovpn
  echo '</key>' >> ${user}/${confname}.ovpn
  echo 'ns-cert-type server' >> ${user}/${confname}.ovpn
  echo 'key-direction 1' >> ${user}/${confname}.ovpn
  echo '<tls-auth>' >> ${user}/${confname}.ovpn
  cat ${ovpnkey_dir}/ta.key|awk '!/#/' >> ${user}/${confname}.ovpn
  echo '</tls-auth>' >> ${user}/${confname}.ovpn
  echo 'comp-lzo' >> ${user}/${confname}.ovpn
  echo 'verb 3' >> ${user}/${confname}.ovpn
  echo 'mute 20' >> ${user}/${confname}.ovpn

  # Build Client Tarball
  echo "[*] Creating ${user}.tar Configuration Package In: ${openvpn_dir}"
  tar -cf ${user}-${confname}.tar ${user}

  # Clean Up Temp Files
  echo '[*] Removing Temporary Files'
  rm -rf ${user}

  # Finish Message
  echo "[*] Client ${user} Buildout Complete"
  echo
  exit 0
}

# Update BuildVPN Script Function
func_update(){
  echo '[*] Preparing Update'
  # Determine BuildVPN Directory
  scriptdir=`dirname ${0}`
  # Determine Git Binary Location
  gitcmd=`which git`
  cd "${scriptdir}"
  # Initialize Git Update
  echo '[*] Starting BuildVPN Update'
  ${gitcmd} pull
  echo
}

# Check Permissions
if [ `whoami` != 'root' ]
then
  func_title
  echo '[ERROR]: You must run this script with root privileges.'
  echo
  exit 1
fi

# Select Function and Menu Statement
func_title
case ${1} in
  -i|--install)
    func_install
    ;;
  -s|--server)
    func_build_server
    ;;
  -c|--client)
    func_build_client
    ;;
  -u|--update)
    func_update
    ;;
  *)
    echo ' Usage...: ./BuildVPN.sh [OPTION]'
    echo ' Options.:'
    echo '           -i | --install = Install OpenVPN Packages'
    echo '           -s | --server  = Build Server Configuration'
    echo '           -c | --client  = Build Client Configuration'
    echo '           -u | --update  = Update BuildVPN Script'
    echo
esac