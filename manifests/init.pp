# == Class: build
#
# Full description of class build here.
#
# === Parameters
#
# Document parameters here.
#
# [*sample_parameter*]
#   Explanation of what this parameter affects and what it defaults to.
#   e.g. "Specify one or more upstream ntp servers as an array."
#
# === Variables
#
# Here you should define a list of variables that this module would require.
#
# [*sample_variable*]
#   Explanation of how this variable affects the funtion of this class and if it
#   has a default. e.g. "The parameter enc_ntp_servers must be set by the
#   External Node Classifier as a comma separated list of hostnames." (Note,
#   global variables should not be used in preference to class parameters  as of
#   Puppet 2.6.)
#
# === Examples
#
# build::install { 'top':
#   download => 'http://www.unixtop.org/dist/top-3.7.tar.gz',
#   creates  => '/usr/local/bin/top',
# }
#
# === Authors
#
# Tomas Barton <barton.tomas@gmail.com>
#
# === Copyright
#
# Copyright 2013 Tomas Barton
#


define build::install (
    $url, 
    $creates, 
    $owner               = 'root',
    $group               = 'root',
    $pkg_folder='', 
    $pkg_format="tar", 
    $pkg_extension="", 
    $buildoptions="", 
    $extractorcmd="",
    $extracted_dir       = '', 
    $rm_build_folder     = true,
    $destination_dir     = '/tmp',
    $work_dir            = '/tmp',
    $path                = '/bin:/sbin:/usr/bin:/usr/sbin',
    $extract_command     = '',
    $preextract_command  = '',
    $postextract_command = '',
    $exec_env            = [],
  ) {
  
  build::requires { "$name-requires-build-essential":  package => 'build-essential' }


 #should be ok for most linux distributions
  $tmp_dir = "/tmp"

  $source_filename = url_parse($url,'filename')
  $source_filetype = url_parse($url,'filetype')
  $source_dirname = url_parse($url,'filedir')

#  $extracted_dir = inline_template("<%= source_filename[0, source_filename.index('-')] %>")

  Exec {
    unless => "test -f $creates",
  }


 $real_extract_command = $extract_command ? {
    ''      => $source_filetype ? {
      '.tgz'     => 'tar -zxf',
      '.tar.gz'  => 'tar -zxf',
      '.tar.bz2' => 'tar -jxf',
      '.tar'     => 'tar -xf',
      '.zip'     => 'unzip',
      default    => 'tar -zxf',
    },
    default => $extract_command,
  }

  $extract_command_second_arg = $real_extract_command ? {
    /^cp.*/    => '.',
    /^rsync.*/ => '.',
    default    => '',
  }

  $real_extracted_dir = $extracted_dir ? {
    ''      => $real_extract_command ? {
      /(^cp.*|^rsync.*)/  => $source_filename,
      default             => $source_dirname,
    },
    default => $extracted_dir,
  }

  if $preextract_command {
    exec { "PreExtract ${source_filename}":
      command     => $preextract_command,
      before      => Exec["Extract ${source_filename}"],
      refreshonly => true,
      path        => $path,
      environment => $exec_env,
    }
  }

  exec { "Retrieve ${url}":
    cwd         => $work_dir,
    command     => "wget ${url} -O ${work_dir}/${source_filename}",
    creates     => "${work_dir}/${source_filename}",
    timeout     => 3600,
    path        => $path,
    environment => $exec_env,
  }

  exec { "Extract ${source_filename}":
    command     => "mkdir -p ${destination_dir} && cd ${destination_dir} && ${real_extract_command} ${work_dir}/${source_filename} ${extract_command_second_arg}",
    unless      => "ls ${destination_dir}/${real_extracted_dir}",
    creates     => "${destination_dir}/${real_extracted_dir}",
    require     => Exec["Retrieve ${url}"],
    path        => $path,
    environment => $exec_env,
    notify      => Exec["Chown ${source_filename}"],
  }

  exec { "Chown ${source_filename}":
    command     => "chown -R ${owner}:${group} ${destination_dir}/${real_extracted_dir}",
    refreshonly => true,
    require     => Exec["Extract ${source_filename}"],
    path        => $path,
    environment => $exec_env,
    notify      => Exec["config-$name"],
  }

  if $postextract_command {
    exec { "PostExtract ${source_filename}":
      command     => $postextract_command,
      cwd         => "${destination_dir}/${real_extracted_dir}",
      subscribe   => Exec["Extract ${source_filename}"],
      refreshonly => true,
      timeout     => 3600,
      require     => Exec["Retrieve ${url}"],
      path        => $path,
      environment => $exec_env,
    }
  }

  $cwd    = "${destination_dir}/${real_extracted_dir}"

  exec { "config-$name":
    cwd     => "$cwd",
    command => "$cwd/configure $buildoptions",
    timeout => 120, # 2 minutes
    require => Exec["Chown ${source_filename}"],
  }
  
  exec { "make-install-$name":
    cwd     => "$cwd",
    command => "make && make install",
    timeout => 600, # 10 minutes
    require => Exec["config-$name"],
  }
  
  # remove build folder
  case $rm_build_folder {
    true: {
      notice("remove build folder")
      exec { "remove-$name-build-folder":
        cwd     => "$cwd",
        command => "rm -rf $cwd",
        require => Exec["make-install-$name"],
      } # exec
    } # true
  } # case
  
}

define build::requires ( $ensure='installed', $package ) {
  if defined( Package[$package] ) {
    debug("$package already installed")
  } else {
    package { $package: ensure => $ensure }
  }
}
