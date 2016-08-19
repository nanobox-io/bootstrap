# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.box     = "ubuntu/trusty64"

  config.vm.provider "virtualbox" do |v|
    v.customize ["modifyvm", :id, "--memory", "2048", "--ioapic", "on"]
  end
  config.vm.network "private_network", ip: "10.1.0.5"

  config.vm.synced_folder ".", "/vagrant"

   config.vm.provision "shell", inline: <<-SCRIPT
    /vagrant/ubuntu.sh id=test-value token=test-token vip=192.168.0.2 component=test-component
  SCRIPT
end
