# -*- coding: UTF-8 -*-

$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__)) + '/lib'

require 'rubygems'
begin
  require 'bundler/setup'
rescue LoadError
  warn 'Warning: Not leveraging Bundler -- is it installed?'
end
require 'find'
require 'logger'
require 'etc'

require 'wiedii/constants'
require 'wiedii/logger'
require 'wiedii/exceptions'
require 'wiedii/extensions/object'
require 'wiedii/extensions/logger'
require 'wiedii/menu/node'
require 'wiedii/system/command'
require 'wiedii/platform/debian'
require 'wiedii/network/dnsmasq'


if Process.uid == 0
  fail 'Wiedii should not be run as root: use an user who can sudo instead!'
end


class Wiedii
  FileUtils.mkdir_p RWDIR
  FileUtils.chmod 0700, RWDIR # too much sensible data here ;-)
  FileUtils.mkdir_p LOGDIR unless Dir.exists? LOGDIR

  use_logfile

  LOGGER.level = Logger::INFO
  LOGGER.level = Logger::DEBUG if
      $0 == __FILE__ and not
      ENV['ONBOARD_ENVIRONMENT'] =~ /production/i
      # this is required because there is no Sinatra environment until
      # controller.rb is loaded (where Wiedii::Controller inherits
      # from Sinatra::Base)

  PLATFORM = Platform::Debian # TODO? make it configurable? get rid of Platform?

  MENU_ROOT = Menu::MenuNode.new('ROOT', {
    :href => '/',
    :name => 'Home',
    :desc => 'Home page',
    :n    => 0
  })

  def self.find_n_load(dir)
    # sort to resamble /etc/rc*.d/* or run-parts behavior
    Find.find(dir).sort.each do |file|
      if file =~ /\.rb$/
        print "loading: #{file}... "
        STDOUT.flush
        if load file
          print "OK\n"
          STDOUT.flush
        end
      end
    end
  end

  def self.web?
    return true unless (ARGV.include?('--no-web') or ARGV.include?('--restore-dns'))
    return false
  end

  def self.restore_dns
    Network::Dnsmasq.init_conf
    Network::Dnsmasq.restart
  end

  def self.prepare
    system "sudo mkdir -p #{VARRUN}"
    system "sudo chown #{Process.uid} #{VARRUN}"

    # modules
    Dir.foreach(ROOTDIR + '/modules') do |dir|
      dir_fullpath = ROOTDIR + '/modules/' + dir
      if File.directory? dir_fullpath and not dir =~ /^\./
        file = dir_fullpath + '/load.rb'
        if File.readable? file
          if File.exists? dir_fullpath + '/.disable'
            puts "Module #{dir}: disabled." if web?  # be quiet if non-web
          else
            load dir_fullpath + '/load.rb'
            puts "Module #{dir}: enabled." if web?  # be quiet if non-web
          end
        else
          STDERR.puts "Warning: Couldn't load modules/#{dir}/load.rb: Skipped!"
        end
      end
    end

    # After the modules, 'cause we want to know, among other things,
    # whether to activate public pages layout configuration page
    # (and relative menu item).
    if web?
      require 'wiedii/controller/helpers'
      require 'wiedii/controller'

      # modular menu
      find_n_load ROOTDIR + '/etc/menu/'
    end

    # restore scripts, sorted like /etc/rc?.d/ SysVInit/Unix/Linux scripts
    if ARGV.include? '--restore'
      restore_scripts =
          Dir.glob(ROOTDIR + '/etc/restore/[0-9][0-9]*.rb')           #+
          #Dir.glob(ROOTDIR + '/modules/*/etc/restore/[0-9][0-9]*.rb')
      Dir.glob(ROOTDIR + '/modules/*').each do |module_dir|
        next if File.exists? "#{module_dir}/.disable"
        restore_scripts += Dir.glob("#{module_dir}/etc/restore/[0-9][0-9]*.rb")
      end
      restore_scripts.sort!{|x,y| File.basename(x) <=> File.basename(y)}
      restore_scripts.each do |script|
        print "loading: #{script}... "
        STDOUT.flush
        begin
          load script and puts "OK"
        rescue Exception
          exception = $!

          puts "ERR!"
          puts "#{exception.class}: #{exception.message}"

          LOGGER.error "loading #{script}: #{exception.inspect}"
          backtrace_str = "Exception backtrace follows:"
          exception.backtrace.each{|line| backtrace_str << "\n" << line}
          LOGGER.error backtrace_str
        end
      end
    end
    # TODO: DRY DRY DRY
    if ARGV.include? '--shutdown'
      shutdown_scripts =
          Dir.glob(ROOTDIR + '/etc/shutdown/[0-9][0-9]*.rb')
      Dir.glob(ROOTDIR + '/modules/*').each do |module_dir|
        next if File.exists? "#{module_dir}/.disable"
        shutdown_scripts += Dir.glob("#{module_dir}/etc/shutdown/[0-9][0-9]*.rb")
      end
      shutdown_scripts.sort!{|x,y| File.basename(x) <=> File.basename(y)}
      shutdown_scripts.each do |script|
        print "loading: #{script}... "
        STDOUT.flush
        begin
          load script and puts "OK"
        rescue Exception
          exception = $!

          puts exception.inspect

          LOGGER.error "loading #{script}: #{exception.inspect}"
          backtrace_str = "Exception backtrace follows:"
          exception.backtrace.each{|line| backtrace_str << "\n" << line}
          LOGGER.error backtrace_str
        end
      end
    end

  end

  def self.save!
    LOGGER.info 'Saving configuration...'
    find_n_load ROOTDIR + '/etc/save/'

    # modules
    Dir.glob(ROOTDIR + '/modules/*').each do |module_dir|
      next if File.exists? "#{module_dir}/.disable"
      Dir.glob("#{module_dir}/etc/save/*.rb").each do |script|
        print "loading: #{script}... " and STDOUT.flush
        load script and puts ' OK'
      end
    end

    # for Voyage-Linux embedded Debian flavour http://linux.voyage.hk
    voyage_sync = '/etc/init.d/voyage-sync'
    if File.file? voyage_sync and File.executable? voyage_sync
      # TODO: move this to a specific file/module/method...
      rootfsmode = `(sudo touch /.rw 2> /dev/null) && echo 'rw' || echo 'ro'`.strip.to_sym
      System::Command.run "remountrw",            :sudo if rootfsmode == :ro
      System::Command.run "#{voyage_sync} sync",  :sudo
      System::Command.run "remountro",            :sudo if rootfsmode == :ro
    end

    System::Command.run 'sync'
  end

end

Wiedii.prepare

if ARGV.include? '--restore-dns'
  Wiedii.restore_dns
end

if Wiedii.web?
  if $0 == __FILE__
    Wiedii::Controller.run! :bind => '0.0.0.0'
  end
end
