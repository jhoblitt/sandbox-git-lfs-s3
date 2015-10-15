include ::stdlib
include ::augeas
include ::sysstat
include ::wget
include ::ntp
include ::gcc
include ::irqbalance
include ::epel
include ::rvm
include ::nginx

$user  = 'vagrant'
$group = 'vagrant'
$root  = '/opt/lsst/git-lfs-s3-server'

Class['epel'] -> Package<| provider != 'rpm' |>

class { 'timezone': timezone  => 'US/Pacific' }
class { 'tuned': profile      => 'virtual-host' }
class { 'selinux': mode       => 'disabled' }
class { 'firewall': ensure    => 'stopped' }
resources { 'firewall': purge => true }

service { 'postfix':
  ensure => 'stopped',
  enable => false,
}

ensure_packages(['git', 'tree', 'vim-enhanced', 'ack'])

#class { '::ruby::dev':
#  bundler_ensure => 'latest',
#}
# ruby::dev and bundler::install both think they own bundler
ensure_packages(['ruby-devel'])

#$ruby_version = 'ruby-2.1'
#$passenger_version = '5.0.20'
#rvm::system_user { 'vagrant': }
#rvm_system_ruby { $ruby_version:
#  ensure      => 'present',
#  default_use => true,
#  require     => Class['rvm'],
#}
#
#rvm_gem { "${ruby_version}/passenger":
#  ensure => $passenger_version,
#  require => Rvm_system_ruby["${ruby_version}"],
#  ruby_version => $ruby_version;
#}
#
#rvm_gem { "${ruby_version}/bundler":
#  require => Rvm_system_ruby["${ruby_version}"],
#  ruby_version => $ruby_version;
#}

vcsrepo { $root:
  alias    => 'git-lfs-s3-server',
  ensure   => present,
  owner    => $user,
  group    => $group,
  provider => git,
  source   => 'https://github.com/lsst-sqre/git-lfs-s3-server.git',
}

bundler::install { $root:
  user       => $user,
  group      => $group,
  deployment => true,
  without    => 'development',
  require    => Package['ruby-devel'],
}

yumrepo { 'passenger':
  ensure        => 'present',
  baseurl       => 'https://oss-binaries.phusionpassenger.com/yum/passenger/el/$releasever/$basearch',
  descr         => 'passenger',
  enabled       => '1',
  gpgcheck      => '0',
  gpgkey        => 'https://packagecloud.io/gpg.key',
  repo_gpgcheck => '1',
  sslcacert     => '/etc/pki/tls/certs/ca-bundle.crt',
  sslverify     => '1',
} -> Package<| provider != 'rpm' |>
package { 'passenger': }

$private_dir         = '/var/private'
$ssl_cert_path       = "${private_dir}/cert_chain.pem"
$ssl_key_path        = "${private_dir}/private.key"
$ssl_dhparam_path    = "${private_dir}/dhparam.pem"
$ssl_root_chain_path = "${private_dir}/root_chain.pem"
$ssl_cert            = hiera('ssl_cert', undef)
$ssl_chain_cert      = hiera('ssl_chain_cert', undef)
$ssl_root_cert       = hiera('ssl_root_cert', undef)
$ssl_key             = hiera('ssl_key', undef)
$add_header          = hiera('add_header', undef)
$www_host            = hiera('www_host', 'git-lfs-s3')
$access_log          = "/var/log/nginx/${www_host}.access.log"
$error_log           = "/var/log/nginx/${www_host}.error.log"

$proxy_set_header = [
  'Host            $host',
  'X-Real-IP       $remote_addr',
  'X-Forwarded-For $proxy_add_x_forwarded_for',
]

if $ssl_cert and $ssl_key {
  $enable_ssl = true
}

#selboolean { 'httpd_can_network_connect':
#  value      => on,
#  persistent => true,
#}

#selboolean { 'httpd_setrlimit':
#  value      => on,
#  persistent => true,
#}

# If SSL is enabled and we are catching an DNS cname, we need to redirect to
# the canonical https URL in one step.  If we do a http -> https redirect, as
# is enabled by puppet-nginx's rewrite_to_https param, the the U-A will catch
# a certificate error before getting to the redirect to the canonical name.
$raw_prepend = [
  "if ( \$host != \'${www_host}\' ) {",
  "  return 301 https://${www_host}\$request_uri;",
  '}',
]

if $enable_ssl {
  file { $private_dir:
    ensure   => directory,
    mode     => '0750',
    #selrange => 's0',
    #selrole  => 'object_r',
    #seltype  => 'httpd_config_t',
    #seluser  => 'system_u',
  }

  exec { 'openssl dhparam -out dhparam.pem 2048':
    path    => ['/usr/bin'],
    cwd     => $private_dir,
    umask   => '0433',
    creates => $ssl_dhparam_path,
  } ->
  file { $ssl_dhparam_path:
    ensure   => file,
    mode     => '0400',
    #selrange => 's0',
    #selrole  => 'object_r',
    #seltype  => 'httpd_config_t',
    #seluser  => 'system_u',
    replace  => false,
    backup   => false,
  }

  # note that nginx needs the signed cert and the CA chain in the same file
  concat { $ssl_cert_path:
    ensure   => present,
    mode     => '0444',
    #selrange => 's0',
    #selrole  => 'object_r',
    #seltype  => 'httpd_config_t',
    #seluser  => 'system_u',
    backup   => false,
    before   => Class['::nginx'],
  }
  concat::fragment { 'public - signed cert':
    target  => $ssl_cert_path,
    order   => 1,
    content => $ssl_cert,
  }
  concat::fragment { 'public - chain cert':
    target  => $ssl_cert_path,
    order   => 2,
    content => $ssl_chain_cert,
  }

  file { $ssl_key_path:
    ensure    => file,
    mode      => '0400',
    #selrange  => 's0',
    #selrole   => 'object_r',
    #seltype   => 'httpd_config_t',
    #seluser   => 'system_u',
    content   => $ssl_key,
    backup    => false,
    show_diff => false,
    before    => Class['::nginx'],
  }

  concat { $ssl_root_chain_path:
    ensure   => present,
    mode     => '0444',
    #selrange => 's0',
    #selrole  => 'object_r',
    #seltype  => 'httpd_config_t',
    #seluser  => 'system_u',
    backup   => false,
    before   => Class['::nginx'],
  }
  concat::fragment { 'root-chain - chain cert':
    target  => $ssl_root_chain_path,
    order   => 1,
    content => $ssl_chain_cert,
  }
  concat::fragment { 'root-chain - root cert':
    target  => $ssl_root_chain_path,
    order   => 2,
    content => $ssl_root_cert,
  }

  nginx::resource::vhost { "${www_host}-ssl":
    ensure              => present,
    listen_port         => 443,
    ssl                 => true,
    rewrite_to_https    => false,
    access_log          => $access_log,
    error_log           => $error_log,
    ssl_key             => $ssl_key_path,
    ssl_cert            => $ssl_cert_path,
    ssl_dhparam         => $ssl_dhparam_path,
    ssl_session_timeout => '1d',
    ssl_cache           => 'shared:SSL:50m',
    ssl_stapling        => true,
    ssl_stapling_verify => true,
    ssl_trusted_cert    => $ssl_root_chain_path,
    resolver            => [ '8.8.8.8', '4.4.4.4'],
    #add_header         => $add_header,
    raw_prepend         => $raw_prepend,
    use_default_location => false,
    index_files => [],
    www_root            => $root,
    vhost_cfg_append    => {
      'passenger_enabled' => 'on',
      'passenger_ruby'    => '/usr/bin/ruby',
    },
  }
}

nginx::resource::vhost { $www_host:
  ensure                => present,
  listen_port           => 80,
  ssl                   => false,
  access_log            => $access_log,
  error_log             => $error_log,
  rewrite_to_https      => $enable_ssl ? {
    true    => true,
    default => false,
  },
  use_default_location => false,
  index_files => [],
  # see comment above $raw_prepend declaration
  raw_prepend           => $enable_ssl ? {
    true     => $raw_prepend,
    default  => undef,
  },
}

file { '/etc/nginx/conf.d/passenger.conf':
  ensure  => file,
  content => '
passenger_root /usr/share/ruby/vendor_ruby/phusion_passenger/locations.ini;
passenger_ruby /usr/bin/ruby;
passenger_instance_registry_dir /var/run/passenger-instreg;
',
}
