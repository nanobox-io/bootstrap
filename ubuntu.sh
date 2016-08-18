#!/bin/bash
#
# Boostraps an ubuntu machine to be used as an agent for nanobox

# exit if any any command fails
set -e

# todo:
# set timezone
# verify
# systemd compatibility

# set globals to defaults for testing
TOKEN="123"
VIP="192.168.0.55"
ID="123"
COMPONENT=""

ubuntu_version() {
  lsb_release -sd \
    | awk '{print $2}' \
      | awk -F. '{print $1"."$2}'
}

init_system() {
  if [[ -f /sbin/systemctl ]]; then
    echo "systemd"
  elif [[ -f /sbin/initctl ]]; then
    echo "upstart"
  else
    echo "sysvinit"
  fi
}

internal_ip() {
  ip addr \
    | grep "$(internal_iface)" \
      | grep "inet 10\." \
        | awk '{print $2}' \
          | awk -F/ '{print $1}'
}

internal_iface() {
  echo "eth1"
}

install_docker() {
  # install docker if not already installed
  if [[ ! -f /usr/bin/docker ]]; then
    # add docker's gpg key
    apt-key adv \
      --keyserver hkp://p80.pool.sks-keyservers.net:80 \
      --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

    # ensure lsb-release is installed
    apt-get -y install lsb-release

    release=$(lsb_release -c | awk '{print $2}')

    # add the source to our apt sources
    echo \
      "deb https://apt.dockerproject.org/repo ubuntu-${release} main" \
        > /etc/apt/sources.list.d/docker.list

    # update the package index
    apt-get -y update

    # ensure the old repo is purged
    apt-get -y purge lxc-docker

    # set docker defaults
    echo "$(docker_defaults)" > /etc/default/docker

    # install docker
    apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install docker-engine=1.12.0-0~${release}
  fi
}

start_docker() {
  if [[ ! `service docker status | grep start/running` ]]; then
    # start the docker daemon
    service docker start

    # wait for the docker sock file
    while [ ! -S /var/run/docker.sock ]; do
      sleep 1
    done
  fi
}

install_red() {
  if [[ ! -f /usr/bin/red ]]; then
    # fetch packages
    wget -O /tmp/libbframe_1.0.0-1_amd64.deb https://s3.amazonaws.com/nanopack.nanobox.io/deb/libbframe_1.0.0-1_amd64.deb
    wget -O /tmp/libmsgxchng_1.0.0-1_amd64.deb https://s3.amazonaws.com/nanopack.nanobox.io/deb/libmsgxchng_1.0.0-1_amd64.deb
    wget -O /tmp/red_1.0.0-1_amd64.deb https://s3.amazonaws.com/nanopack.nanobox.io/deb/red_1.0.0-1_amd64.deb
    wget -O /tmp/redd_1.0.0-1_amd64.deb https://s3.amazonaws.com/nanopack.nanobox.io/deb/redd_1.0.0-1_amd64.deb

    # install dependencies
    apt-get -y install libmsgpack3 libuv0.10

    # install packages
    dpkg -i /tmp/libbframe_1.0.0-1_amd64.deb
    dpkg -i /tmp/libmsgxchng_1.0.0-1_amd64.deb
    dpkg -i /tmp/red_1.0.0-1_amd64.deb
    dpkg -i /tmp/redd_1.0.0-1_amd64.deb

    # configure redd
    echo "$(redd_conf)" > /etc/redd.conf

    # ensure the redd db path exists
    mkdir -p /var/db/redd

    # create init entry
    if [[ "$(init_system)" = "systemd" ]]; then
      todo
    elif [[ "$(init_system)" = "upstart" ]]; then
      echo "$(redd_upstart_conf)" > /etc/init/redd.conf
    fi

    # remove cruft
    rm -f /tmp/libbframe_1.0.0-1_amd64.deb
    rm -f /tmp/libmsgxchng_1.0.0-1_amd64.deb
    rm -f /tmp/red_1.0.0-1_amd64.deb
    rm -f /tmp/redd_1.0.0-1_amd64.deb
  fi
}

start_redd() {
  if [[ ! `service redd status | grep start/running` ]]; then
    # start the redd daemon
    service redd start

    # wait for the docker sock file
    while [ ! `red ping | grep pong` ]; do
      sleep 1
    done
  fi
}

install_bridgeutils() {
  if [[ ! -f /sbin/brctl ]]; then
    apt-get install -y bridge-utils
  fi
}

create_docker_network() {
  if [[ ! `docker network ls | grep nanobox` ]]; then
    # create a docker network
    docker network create \
      --driver=bridge --subnet=192.168.0.0/16 \
      --opt="com.docker.network.driver.mtu=1450" \
      --opt="com.docker.network.bridge.name=redd0" \
      --gateway=$VIP \
      nanobox
  fi
}

create_vxlan_bridge() {
  if [[ "$(init_system)" = "systemd" ]]; then
    todo
  elif [[ "$(init_system)" = "upstart" ]]; then
    echo "$(vxlan_upstart_conf)" > /etc/init/vxlan.conf
  fi
}

start_vxlan_bridge() {
  if [[ ! `service vxlan status | grep start/running` ]]; then
    # start the vxlan bridge
    service vxlan start
  fi
}

install_nanoagent() {
  if [[ ! -f /usr/local/bin/nanoagent ]]; then
    # download nanoagent
    curl \
      -f \
      -k \
      -o /usr/local/bin/nanoagent \
      http://tools.nanobox.io.s3.amazonaws.com/nanoagent/linux/amd64/nanoagent

    # update permissions
    chmod 755 /usr/local/bin/nanoagent

    # download md5
    mkdir -p /var/nanobox
    curl \
      -f \
      -k \
      -o /var/nanobox/nanoagent.md5 \
      http://tools.nanobox.io.s3.amazonaws.com/nanoagent/linux/amd64/nanoagent.md5

    # create db
    mkdir -p /var/db/nanoagent

    # generate config file
    mkdir -p /etc/nanoagent
    echo "$(nanoagent_json)" > /etc/nanoagent/config.json

    # create init script
    if [[ "$(init_system)" = "systemd" ]]; then
      todo
    elif [[ "$(init_system)" = "upstart" ]]; then
      echo "$(nanoagent_upstart_conf)" > /etc/init/nanoagent.conf
    fi
  fi

  # create update script
  if [[ ! -f /usr/local/bin/nanoagent-update ]]; then
    # create the utility
    echo "$(nanoagent_update)" > /usr/local/bin/nanoagent-update

    # update permissions
    chmod 755 /usr/local/bin/nanoagent-update
  fi
}

start_nanoagent() {
  if [[ ! `service nanoagent status | grep start/running` ]]; then
    # start the nanoagent daemon
    service nanoagent start
  fi
}

create_modloader() {
  if [[ "$(init_system)" = "systemd" ]]; then
    todo
  elif [[ "$(init_system)" = "upstart" ]]; then
    echo "$(modloader_upstart_conf)" > /etc/init/modloader.conf
  fi
}

start_modloader() {
  if [[ ! `service modloader status | grep start/running` ]]; then
    # start the nanoagent daemon
    service modloader start
  fi
}

configure_firewall() {
  # create init script
  if [[ "$(init_system)" = "systemd" ]]; then
    todo
  elif [[ "$(init_system)" = "upstart" ]]; then
    echo "$(firewall_upstart_conf)" > /etc/init/firewall.conf
  fi
}

start_firewall() {
  if [[ ! `service firewall status | grep start/running` ]]; then
    # start the firewall bridge
    service firewall start
  fi
}

docker_defaults() {
  size=`df -h / | sed -n 2p | awk '{print $2}'`
  cat <<-END
DOCKER_OPTS="--iptables=false --storage-opt dm.loopdatasize=$size --storage-opt dm.basesize=$size"

END
}

redd_conf() {
  cat <<-END
daemonize no
pidfile /var/run/redd.pid
logfile /var/log/redd.log
loglevel warning
port 4470
timeout 0

routing-enabled yes

bind 127.0.0.1
udp-listen-address $(internal_ip)
vxlan-interface $(internal_iface)
save-path /var/db/redd
END
}

redd_upstart_conf() {
  cat <<-END
description "Red vxlan daemon"

start on (filesystem and net-device-up IFACE!=lo)
stop on runlevel [!2345]

respawn

kill timeout 20

exec redd /etc/redd.conf
END
}

vxlan_upstart_conf() {
  cat <<-END
description "Red vxlan to docker bridge"

start on runlevel [2345]

pre-start script
  # wait for redd0
  while [ ! \`/sbin/ifconfig | /bin/grep redd0\` ]; do
    sleep 1
  done

  # wait for vxlan0
  while [ ! \`/sbin/ifconfig | /bin/grep vxlan0\` ]; do
    sleep 1
  done
end script

script
  if [ ! \`/sbin/brctl show | /bin/grep redd0 | /bin/grep vxlan0\` ]; then
    # disable mac address learning to ensure broadcasts are always forwarded
    /sbin/brctl setageing redd0 0

    # bridge the network onto the red vxlan
    /sbin/brctl addif redd0 vxlan0
  fi
end script

END
}

modloader_upstart_conf() {
  cat <<-END
description "Nanobox modloader"

start on runlevel [2345]

script

# ensure ip_vs module is loaded
modprobe ip_vs

end script
END
}

nanoagent_json() {
  cat <<-END
{
  "host_id": "$id",
  "token":"$TOKEN",
  "labels": {"component":"$COMPONENT"},
  "log_level":"DEBUG",
  "api_port":"8570",
  "route_http_port":"80",
  "route_tls_port":"443",
  "data_file":"/var/db/nanoagent/bolt.db"
}
END
}

nanoagent_update() {
  cat <<-END
#!/bin/bash

# extract installed version
current=\$(cat /var/nanobox/nanoagent.md5)

# download the latest checksum
curl \\
  -f \\
  -k \\
  -s \\
  -o /var/nanobox/nanoagent.md5 \\
  http://tools.nanobox.io.s3.amazonaws.com/nanoagent/linux/amd64/nanoagent.md5

# compare latest with installed
latest=\$(cat /var/nanobox/nanoagent.md5)

if [ ! "\$current" = "\$latest" ]; then
  echo "Nanoagent is out of date, updating to latest"

  # stop the running Nanoagent
  service nanoagent stop

  # download the latest version
  curl \\
    -f \\
    -k \\
    -o /usr/local/bin/nanoagent \\
    http://tools.nanobox.io.s3.amazonaws.com/nanoagent/linux/amd64/nanoagent

  # update permissions
  chmod 755 /usr/local/bin/nanoagent

  # start the new version
  service nanoagent start
else
  echo "Nanoagent is up to date."
fi
END
}

nanoagent_upstart_conf() {
  cat <<-END
description "Nanoagent daemon"

start on (filesystem and net-device-up IFACE!=lo and firewall)
stop on runlevel [!2345]

respawn

kill timeout 20

exec /usr/local/bin/nanoagent server --config /etc/nanoagent/config.json >> /var/log/nanoagent.log
END
}

firewall_upstart_conf() {
  cat <<-END
description "Nanobox firewall base lockdown"

start on runlevel [2345]

emits firewall

script

if [ ! -f /run/iptables ]; then
  # flush the current firewall
  iptables -F

  # Set default policies (nothing in, anything out)
  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT ACCEPT

  # Allow returning packets
  iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # Allow local traffic
  iptables -A INPUT -i lo -j ACCEPT

  # allow ssh connections from anywhere
  iptables -A INPUT -p tcp --dport 22 -j ACCEPT

  # allow nanoagent api connections
  iptables -A INPUT -p tcp --dport 8570 -j ACCEPT

  # Allow vxlan and docker traffic
  iptables -A INPUT -i redd0 -j ACCEPT
  iptables -A FORWARD -i redd0 -j ACCEPT
  iptables -A FORWARD -o redd0 -j ACCEPT
  iptables -A INPUT -i docker0 -j ACCEPT
  iptables -A FORWARD -i docker0 -j ACCEPT
  iptables -A FORWARD -o docker0 -j ACCEPT
  iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
  iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE
  touch /run/iptables
  initctl emit firewall
fi

end script
END
}

run() {
  echo "+> $2"
  $1 2>&1 | format '   '
}

format() {
  prefix=$1
  while read LINE;
  do
    echo "${prefix}${LINE}"
  done
}

# parse args and set values
for i in "${@}"; do

  case $i in
    --id=* )
      ID=${i#*=}
      ;;
    --token=* )
      TOKEN=${i#*=}
      ;;
    --vip=* )
      VIP=${i#*=}
      ;;
    --component=* )
      COMPONENT=${i#*=}
      ;;
  esac

done

run install_docker "Installing docker"
run start_docker "Starting docker daemon"

run install_red "Installing red"
run start_redd "Starting red daemon"

run install_bridgeutils "Installing ethernet bridging utilities"
run create_docker_network "Creating isolated docker network"
run create_vxlan_bridge "Creating red vxlan bridge"
run start_vxlan_bridge "Starting red vxlan bridge"

run create_modloader "Creating modloader"
run start_modloader "Starting modloader"

run configure_firewall "Configuring firewall"
run start_firewall "Starting firewall"

run install_nanoagent "Installing nanoagent"
run start_nanoagent "Starting nanoagent"

echo "+> Hold on to your butts"
