required_plugins = %w{
  vagrant-librarian-puppet
  vagrant-puppet-install
  vagrant-aws
}

plugins_to_install = required_plugins.select { |plugin| not Vagrant.has_plugin? plugin }
if not plugins_to_install.empty?
  puts "Installing plugins: #{plugins_to_install.join(' ')}"
  system "vagrant plugin install #{plugins_to_install.join(' ')}"
  exec "vagrant #{ARGV.join(' ')}"
end

# generate a psuedo unique hostname to avoid droplet name/aws tag collisions.
# eg, "jhoblitt-sxn-<os>"
# based on:
# https://stackoverflow.com/questions/88311/how-best-to-generate-a-random-string-in-ruby
def gen_hostname(boxname)
  "#{ENV['USER']}-#{(0...3).map { (65 + rand(26)).chr }.join.downcase}-#{boxname}"
end
def ci_hostname(hostname, provider)
  provider.user_data = <<-EOS
#cloud-config
hostname: #{hostname}
manage_etc_hosts: localhost
  EOS
end

Vagrant.configure('2') do |config|

  config.vm.define 'el7' do |define|
    hostname = gen_hostname('el7')
    define.vm.hostname = hostname

    define.vm.provider :virtualbox do |provider, override|
      override.vm.box = 'bento/centos-7.1'
      override.vm.network 'public_network', bridge: 'eno1'
    end
    define.vm.provider :aws do |provider, override|
      ci_hostname(hostname, provider)

      # base centos 7 ami
      # provider.ami = 'ami-c7d092f7'
      # override.ssh.username = 'centos'

      # packer build of base ami
      # provider.ami = 'ami-29576419'

      # packer built
      provider.ami = 'ami-ffe3839a'
      provider.region = 'us-east-1'
    end
  end

  # setup the remote repo needed to install a current version of puppet
  config.puppet_install.puppet_version = '3.8.2'

  config.vm.synced_folder 'hieradata/', '/tmp/vagrant-puppet/hieradata'

  config.vm.provision :puppet do |puppet|
    puppet.manifests_path = "manifests"
    puppet.module_path = "modules"
    puppet.manifest_file = "init.pp"
    puppet.hiera_config_path = "hiera.yaml"
    puppet.options = [
     '--verbose',
     '--report',
     '--show_diff',
     '--pluginsync',
     '--disable_warnings=deprecations',
    ]
  end

  config.vm.provider :virtualbox do |provider, override|
    provider.memory = 4096
    provider.cpus = 4
  end

  config.vm.provider :aws do |provider, override|
    override.vm.box = 'aws'
    override.vm.box_url = "https://github.com/mitchellh/vagrant-aws/raw/master/dummy.box"
    # http://blog.damore.it/2015/01/aws-vagrant-no-host-ip-was-given-to.html
    override.nfs.functional = false
    override.vm.synced_folder '.', '/vagrant', :disabled => true
    override.ssh.private_key_path = "#{Dir.home}/.vagrant.d/insecure_private_key"
    provider.keypair_name = "vagrant"
    provider.access_key_id = ENV['AWS_ACCESS_KEY_ID']
    provider.secret_access_key = ENV['AWS_SECRET_ACCESS_KEY']
    provider.region = ENV['AWS_DEFAULT_REGION']
    if ENV['AWS_SECURITY_GROUPS']
      provider.security_groups = ENV['AWS_SECURITY_GROUPS'].strip.split(/\s+/)
    else
      provider.security_groups = ['sshonly']
    end
    if ENV['AWS_SUBNET_ID']
      provider.subnet_id = ENV['AWS_SUBNET_ID']
      # assume we don't have an accessible public IP
      provider.ssh_host_attribute = :private_ip_address
    end
    provider.instance_type = 'c4.large'
    provider.ebs_optimized = true
    provider.block_device_mapping = [{
      'DeviceName'              => '/dev/sda1',
      'Ebs.VolumeSize'          => 40,
      'Ebs.VolumeType'          => 'gp2',
      'Ebs.DeleteOnTermination' => 'true',
    }]
    provider.tags = { 'Name' => "git-lfs-s3" }
  end

  if Vagrant.has_plugin?('vagrant-librarian-puppet')
    config.librarian_puppet.placeholder_filename = ".gitkeep"
  end

  if Vagrant.has_plugin?("vagrant-cachier")
    config.cache.scope = :box
  end
end
