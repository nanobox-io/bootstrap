#!/bin/bash
#
# Boostraps a CI server to run tests or deploy an app with Nanobox
# 
# sudo bash -c "$(curl -fsSL https://s3.amazonaws.com/tools.nanobox.io/bootstrap/ci.sh)"

# 1 - Install and run docker
# 2 - Download nanobox
# 3 - Chown nanobox
# 4 - Set Nanobox configuration

# 1 - Install Docker
# 
# * For the time being this only supports an Ubuntu installation.
#   If there is reason to believe other linux distributions are commonly
#   used for CI/CD solutions, we can switch through them here
if [[ ! -f /usr/bin/docker && "$USER" = "root" ]]; then
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
  
  # allow user to use docker without sudo
  if [[ -n $SUDO_USER ]]; then
    groupadd docker
    usermod -aG docker $SUDO_USER
  fi
fi

# 2 - Download nanobox
curl \
  -f \
  -k \
  -o /usr/local/bin/nanobox \
  https://s3.amazonaws.com/tools.nanobox.io/nanobox/v2/linux/amd64/nanobox
  
# 3 - Chown nanobox
chmod +x /usr/local/bin/nanobox

# 4 - Set nanobox configuration
nanobox config set provider native

echo "Nanobox is ready to go!"
