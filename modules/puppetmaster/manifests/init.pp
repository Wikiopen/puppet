# class: puppetmaster
class puppetmaster(
    $dbserver     = undef,
    $dbname       = undef,
    $dbuser       = undef,
    $use_puppetdb = hiera('puppetmaster::use_puppetdb', false),
  ) {
  
    $puppetmaster_hostname = hiera('puppetmaster_hostname', 'puppet.wikiopen.tk')
    $puppetmaster_certname = hiera('puppetmaster_cert', 'mw1.wikiopen.tk')
    $puppetmaster_version = hiera('puppetmaster_version', 4)

    if os_version('ubuntu >= artful') {
        $puppetmaster = 'puppet-master'
        $packages = [
            'libmariadbd-dev',
            'puppet-master',
            'puppet-common',
            'puppet-master-passenger',
        ]
    } else {
        $puppetmaster = 'puppetmaster'
        $packages = [
            'libmariadbd-dev',
            'puppetmaster',
            'puppet-common',
            'puppetmaster-passenger',
        ]
    }

    package { $packages:
        ensure => present,
    }

    $dbpassword = hiera('puppetmaster::dbpassword')

    file { '/etc/puppet/hiera.yaml':
        ensure  => present,
        source  => 'puppet:///modules/puppetmaster/hiera.yaml',
        require => Package[$puppetmaster],
        notify  => Service['apache2'],
    }

    file { '/etc/puppet/puppet.conf':
        ensure  => present,
        content => template("puppetmaster/puppet_${puppetmaster_version}.conf.erb"),
        require => Package[$puppetmaster],
        notify  => Service['apache2'],
    }

    file { '/etc/puppet/auth.conf':
        ensure  => present,
        source  => "puppet:///modules/puppetmaster/auth_${puppetmaster_version}.conf",
        require => Package[$puppetmaster],
        notify  => Service['apache2'],
    }

    file { '/etc/puppet/fileserver.conf':
        ensure  => present,
        source  => 'puppet:///modules/puppetmaster/fileserver.conf',
        require => Package[$puppetmaster],
        notify  => Service['apache2'],
    }

    git::clone { 'puppet':
        ensure    => latest,
        directory => '/etc/puppet/git',
        origin    => 'https://github.com/WikiOpen/puppet.git',
        require   => Package[$puppetmaster],
    }

    git::clone { 'ssl':
        ensure    => latest,
        directory => '/etc/puppet/ssl',
        origin    => 'https://github.com/miraheze/ssl.git',
        require   => Package[$puppetmaster],
    }

    file { '/etc/puppet/private':
        ensure => directory,
    }

    file { '/etc/puppet/hieradata':
        ensure  => link,
        target  => '/etc/puppet/git/hieradata',
        require => Git::Clone['puppet'],
    }

    file { '/etc/puppet/private/hieradata':
        ensure  => directory,
        require => File['/etc/puppet/private'],
    }

    file { '/etc/puppet/private/hieradata/hosts':
        ensure  => directory,
        require => File['/etc/puppet/private/hieradata'],
    }

    file { '/etc/puppet/manifests':
        ensure  => link,
        target  => '/etc/puppet/git/manifests',
        require => Git::Clone['puppet'],
    }

    file { '/etc/puppet/modules':
        ensure  => link,
        target  => '/etc/puppet/git/modules',
        require => Git::Clone['puppet'],
    }

    file { '/etc/puppet/code':
        ensure  => directory,
        owner   => 'root',
        group   => 'root',
        mode    => '0770',
        require => Package[$puppetmaster],
    }

    file { '/etc/puppet/code/environments':
        ensure  => directory,
        owner   => 'root',
        group   => 'root',
        mode    => '0770',
        require => File['/etc/puppet/code'],
    }

    file { '/etc/puppet/code/environments/production':
        ensure  => directory,
        owner   => 'root',
        group   => 'root',
        mode    => '0770',
        require => File['/etc/puppet/code/environments'],
    }

    file { '/etc/puppet/code/environments/production/manifests':
        ensure  => link,
        target  => '/etc/puppet/manifests',
        require => [File['/etc/puppet/code/environments/production'], File['/etc/puppet/manifests']],
    }

    file { '/etc/puppet/code/environments/production/modules':
        ensure  => link,
        target  => '/etc/puppet/modules',
        require => [File['/etc/puppet/code/environments/production'], File['/etc/puppet/modules']],
    }

    file { '/etc/puppet/code/environments/production/ssl':
        ensure  => link,
        target  => '/etc/puppet/ssl',
        require => [File['/etc/puppet/code/environments/production'], Git::Clone['ssl']],
    }

    file { '/etc/puppet/environments':
        ensure  => directory,
        mode    => '0775',
        require => Package[$puppetmaster],
    }

    file { '/etc/puppet/environments/production':
        ensure  => directory,
        mode    => '0775',
        require => File['/etc/puppet/environments'],
    }

    file { '/etc/puppet/environments/production/manifests':
        ensure  => link,
        target  => '/etc/puppet/manifests',
        require => [File['/etc/puppet/environments/production'], File['/etc/puppet/manifests']],
    }

    file { '/etc/puppet/environments/production/modules':
        ensure  => link,
        target  => '/etc/puppet/modules',
        require => [File['/etc/puppet/environments/production'], File['/etc/puppet/modules']],
    }

    file { '/etc/puppet/environments/production/ssl':
        ensure  => link,
        target  => '/etc/puppet/ssl',
        require => [File['/etc/puppet/environments/production'], Git::Clone['ssl']],
    }

    if $use_puppetdb {
        class { 'puppetmaster::puppetdb::client': }
    }

    service { $puppetmaster:
        ensure => stopped,
        enable => false,
        before => Service['apache2'],
    }

    include ::apache::mod::rewrite 
    include ::apache::mod::ssl

    apache::site { 'puppet-master':
        ensure => present,
        source => 'puppet:///modules/puppetmaster/puppet-master.conf',
    }

    # Place an empty puppet-master.conf file to prevent creation of this file
    # at package install time. Apache breaks if that happens. T179102
    file { '/etc/apache2/sites-available/puppet-master.conf':
        ensure  => present,
        content => '# This file intentionally left blank by puppet'
    }
    file { '/etc/apache2/sites-enabled/puppet-master.conf':
        ensure  => link,
        target  => '/etc/apache2/sites-available/puppet-master.conf',
        require => File['/etc/apache2/sites-available/puppet-master.conf'],
    }


    ufw::allow { 'puppetmaster':
        proto => 'tcp',
        port  => '8140',
    }

    cron { 'puppet-git':
        command => '/usr/bin/git -C /etc/puppet/git pull',
        user    => 'root',
        hour    => '*',
        minute  => [ '19', '29', '39', '49', '59' ],
    }

    cron { 'ssl-git':
        command => '/usr/bin/git -C /etc/puppet/ssl pull',
        user    => 'root',
        hour    => '*',
        minute  => [ '19', '29', '39', '49', '59' ],
    }
}
