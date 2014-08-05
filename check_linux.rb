#! /usr/bin/env ruby

# -----------------------
# Author: Andreas Paul (xorpaul) <xorpaul@gmail.com>
# Date: 2013-12-02 10:57
# Version: 0.1
# -----------------------

require 'date'
require 'optparse'
require 'yaml'


$debug = false
$plugin_dir = '/usr/lib/nagios/plugins'
if !File.exist?($plugin_dir)
  $plugin_dir = '/usr/lib64/nagios/plugins'
end
# Pre-flight checks
if !File.exist?("#{$plugin_dir}/check_load")
  puts "ERROR: You need to install the nagios-plugins package!"
  exit 3
end
if !File.exist?(`which sar`.chomp("\n"))
  puts "ERROR: You need to install the sysstat package!"
  exit 3
end

# The config file should be somwhere where only root and nagios can edit
# Otherwise people could mess with your thresholds
configfile = '/tmp/check_linux.cfg.yml'
#configfile = '/var/lib/nagios/check_linux.cfg.yml'


opt = OptionParser.new
opt.on("--configfile [FILE]", "-c", "Config file to use in YAML format, defaults to #{configfile}") do |file|
    configfile = file
end
opt.on("--debug", "-d", "print debug information, defaults to #{$debug}") do |f|
    $debug = true
end
opt.parse!

if File.exists?(configfile)
  begin
    config = YAML.load_file(configfile)
  rescue
    puts "UNKNOWN - failed to parse config file: #{configfile}"
    exit 3
  end
  puts "Using config settings: #{config}" if $debug
else
  config = {}
  # check_load defaults
  config['check_load'] = {}
  pc = `grep -c vendor_id /proc/cpuinfo`.to_i
  config['check_load']['warn'] = "#{pc + 4},#{pc + 3},#{pc + 2}"
  config['check_load']['crit'] = "#{pc + 8},#{pc + 7},#{pc + 6}"
  # check_sar_cpu defaults
  config['check_sar_cpu'] = {}
  config['check_sar_cpu']['warn'] = 90
  config['check_sar_cpu']['crit'] = 95
  # check_sar_swap defaults
  config['check_sar_swap'] = {}
  config['check_sar_swap']['warn'] = 250
  config['check_sar_swap']['crit'] = 500
  # check_swap defaults
  config['check_swap'] = {}
  config['check_swap']['warn'] = '40%'
  config['check_swap']['crit'] = '20%'
  config['check_swap']['enabled'] = true
  # check_disk defaults
  config['check_disk'] = {}
  config['check_disk']['/'] = {}
  config['check_disk']['/']['warn'] = '10%'
  config['check_disk']['/']['crit'] = '5%'
  # check_mem defaults
  config['check_mem'] = {}
  config['check_mem']['warn'] = 10
  config['check_mem']['crit'] = 5
  # check_ntp defaults
  config['check_ntp'] = {}
  config['check_ntp']['warn'] = 5
  config['check_ntp']['crit'] = 10
  # check_tasks defaults
  config['check_tasks'] = {}
  config['check_tasks']['allowed_zombies'] = 0
  puts "Using default settings: #{config}" if $debug
  File.open(configfile, 'w') do |f|
    f.write(config.to_yaml)
  end
end

def debug_header(function_name)
  if $debug
    puts "# ------------------------------"
    puts "# %s" % function_name.to_s
    puts "# ------------------------------"
  end
end

# http://stackoverflow.com/a/4136485/682847
def humanize(secs)
  [[60, :seconds], [60, :minutes], [24, :hours], [1000, :days]].map{ |count, name|
    if secs > 0
      secs, n = secs.divmod(count)
      "#{n.to_i} #{name}"
    end
  }.compact.reverse.join(' ')
end

def check_load(warn, crit)
  debug_header(__method__)
  load_cmd = "#{$plugin_dir}/check_load -w #{warn} -c #{crit}"
  puts "executing #{load_cmd}" if $debug
  load_data = `#{load_cmd}`.split('|')
  load_result = {}
  load_result['returncode'] = $?.exitstatus
  load_result['text'] = load_data[0]
  load_result['perfdata'] = load_data[1].chomp().strip() if load_data.size >= 2
  puts load_result if $debug
  return load_result
end

def check_sar_cpu(warn, crit, interactive_mode=false)
  debug_header(__method__)
  sar_cpu_result = {}
  regex = /([0-9]+[,.][0-9]+)\s+([0-9]+[,.][0-9]+)\s+([0-9]+[,.][0-9]+)\s+([0-9]+[,.][0-9]+)\s+([0-9]+[,.][0-9]+)\s+([0-9]+[,.][0-9]+)$/
  if interactive_mode == true
    sar_cpu_cmd = "`which sar` 25 1"
    puts "executing #{sar_cpu_cmd}" if $debug
    sar_cpu_output = `#{sar_cpu_cmd}`
    sar_cpu_data = sar_cpu_output.split("\n")
    m = regex.match(sar_cpu_data[-2])
  else
    sar_cpu_cmd = "`which sar`"
    puts "executing #{sar_cpu_cmd}" if $debug
    sar_cpu_output = `#{sar_cpu_cmd}`
    sar_cpu_data = sar_cpu_output.split("\n")
    m = regex.match(sar_cpu_data[-2])
    if m == nil
      m = regex.match(sar_cpu_data[-4])
    end
    if m == nil
      interactive_mode = true
      File.open('/tmp/check_linux_debug.txt', 'w+') { |file| file.write(sar_cpu_data) }
      sar_cpu_cmd = "`which sar` 25 1"
      puts "executing #{sar_cpu_cmd}, because regex did not match!" if $debug
      sar_cpu_output = `#{sar_cpu_cmd}`
      sar_cpu_data = sar_cpu_output.split("\n")
      m = regex.match(sar_cpu_data[-2])
    end
  end
  if m != nil 
    sar_cpu_user = m[1].to_f.round()
    sar_cpu_system = m[3].to_f.round()
    sar_cpu_iowait = m[4].to_f.round()
    sar_cpu_idle = m[6].to_f.round()
    if (100 - sar_cpu_idle) >= crit
      text = "CRITICAL - idle: #{sar_cpu_idle}% < #{100 - crit}%"
      rc = 2
    elsif (100 - sar_cpu_idle) >= warn
      text = "WARNING - idle: #{sar_cpu_idle}% < #{100 - warn}%"
      rc = 1
    else
      text = "OK - idle: #{sar_cpu_idle}%"
      rc = 0
    end
  sar_cpu_result['returncode'] = rc
  sar_cpu_result['text'] = "#{text} user: #{sar_cpu_user}% system: #{sar_cpu_system}% iowait: #{sar_cpu_iowait}% interactive_mode: #{interactive_mode}"
  sar_cpu_result['perfdata'] = "%idle=#{sar_cpu_idle}%;#{100-warn};#{100-crit};0 %user=#{sar_cpu_user}%;#{warn};#{crit};0 %system=#{sar_cpu_system}%;#{warn};#{crit};0 %iowait=#{sar_cpu_iowait}%;#{warn};#{crit};0"
  else
    puts "Regex did not match!" if $debug
    sar_cpu_result['returncode'] = 1
    sar_cpu_result['text'] = "WARNING: check_sar_cpu() regex did not match!"
    sar_cpu_result['perfdata'] = "%idle=0%;#{100-warn};#{100-crit};0 %user=0%;#{warn};#{crit};0 %system=0%;#{warn};#{crit};0 %iowait=0%;#{warn};#{crit};0"
    # XXX
    File.open('/tmp/check_linux_debug.txt', 'w+') { |file| file.write(sar_cpu_data) }
  end
  puts sar_cpu_result if $debug
  return sar_cpu_result
end

def check_sar_swap(warn, crit, interactive_mode)
  debug_header(__method__)
  sar_swap_result = {}
  regex = /([0-9]+[,.][0-9]+)\s+([0-9]+[,.][0-9]+)$/
  if interactive_mode == true
    sar_swap_cmd = "`which sar` -W 25 1"
    puts "executing #{sar_swap_cmd}" if $debug
    sar_swap_output = `#{sar_swap_cmd}`
    sar_swap_data = sar_swap_output.split("\n")
    m = regex.match(sar_swap_data[-2])
  else
    sar_swap_cmd = "`which sar` -W"
    puts "executing #{sar_swap_cmd}" if $debug
    sar_swap_output = `#{sar_swap_cmd}`
    sar_swap_data = sar_swap_output.split("\n")
    m = regex.match(sar_swap_data[-2])
    if m == nil
      m = regex.match(sar_swap_data[-4])
    end
    if m == nil
      interactive_mode = true
      File.open('/tmp/check_linux_debug.txt', 'w+') { |file| file.write(sar_swap_data) }
      sar_swap_cmd = "`which sar` -W 25 1"
      puts "executing #{sar_swap_cmd}, because regex did not match!" if $debug
      sar_swap_output = `#{sar_swap_cmd}`
      sar_swap_data = sar_swap_output.split("\n")
      m = regex.match(sar_swap_data[-2])
    end
  end
  if m != nil
    pswpout = m[1].to_f
    pswpin = m[2].to_f
    if pswpout >= crit
      text = 'CRITICAL'
      rc = 2
    elsif pswpout >= warn
      text = 'WARNING'
      rc = 1
    else
      text = 'OK'
      rc = 0
    end
    sar_swap_result['returncode'] = rc
    sar_swap_result['text'] = "#{text} - pswpout/s: #{pswpout} pswpin/s: #{pswpin} interactive_mode #{interactive_mode}"
    sar_swap_result['perfdata'] = "pswpout=#{pswpout};#{warn};#{crit};0 pswpin=#{pswpin};;;0"
  else
    puts "Regex did not match!" if $debug
    sar_swap_result['returncode'] = 1
    sar_swap_result['text'] = "WARNING: check_sar_swap() regex did not match!"
    sar_swap_result['perfdata'] = "pswpout=0;#{warn};#{crit};0 pswpout=0;;;0"
  end
  puts sar_swap_result if $debug
  return sar_swap_result
end

def check_swap(warn, crit, ram_warn, ram_crit)
  debug_header(__method__)
  swap_cmd = "#{$plugin_dir}/check_swap -w #{warn} -c #{crit}"
  puts "executing #{swap_cmd}" if $debug
  swap_data = `#{swap_cmd}`.split('|')
  # only alert on low swap space if it is also low on free ram
  swap_result,ram_result = {}, {}
  ram_result = check_ram(ram_warn, ram_crit)
  if ram_result['returncode'] == 2
    swap_result['returncode'] = $?.exitstatus
    swap_result['text'] = swap_data[0]
  else
    $?.exitstatus > 0 ? text = "ignored, because there is enough free RAM (>#{ram_crit}% free)" : text = ''
    swap_result['returncode'] = 0
    swap_result['text'] = "#{swap_data[0]}#{text}"
  end
  swap_result['perfdata'] = swap_data[1].chomp().strip()
  puts swap_result if $debug
  return swap_result
end

def check_disk(warn, crit, partition)
  debug_header(__method__)
  disk_cmd = "#{$plugin_dir}/check_disk -w #{warn} -c #{crit} #{partition}"
  puts "executing #{disk_cmd}" if $debug
  disk_data = `#{disk_cmd}`.split('|')
  disk_result = {}
  disk_result['returncode'] = $?.exitstatus
  disk_result['text'] = disk_data[0]
  # parse the free disk space percentage out of the output
  m = /\((\d+)% inode=/.match(disk_result['text'])
  disk_used_percentage_perfdata = ''
  if m
    disk_used_percentage = 100 - m[1].to_i
    disk_used_percentage_perfdata = "#{partition}_used_%=#{disk_used_percentage}%;#{100-warn.to_i};#{100-crit.to_i}"
  end
  disk_result['perfdata'] = "#{disk_used_percentage_perfdata} #{disk_data[1].chomp().strip()}" if disk_data.size >= 2
  puts disk_result if $debug
  return disk_result
end

def check_disks(disks_config)
  debug_header(__method__)
  disks_cmd = "df --local --exclude-type rootfs --exclude-type tmpfs --exclude-type devtmpfs"
  puts "executing #{disks_cmd}" if $debug
  disks_data = `#{disks_cmd}`.split("\n")
  # remove column header line
  disks_data = disks_data[1..-1]
  disks_results = []
  disks_data.each do |d|
    cols = d.split("\s")
    mountpoint = cols[-1]
    next if mountpoint == '/boot'
    puts disks_config if $debug
    if disks_config.has_key?(mountpoint)
      disks_results << check_disk(disks_config[mountpoint]['warn'], disks_config[mountpoint]['crit'], mountpoint)
    else
      disks_results << check_disk('5%', '10%', mountpoint)
    end
  end
  return disks_results
end

def check_proc(name, owner='root', check_with_regex=true)
  debug_header("#{__method__} with #{name}")
  absolute_path = `which #{name}`
  # if /usr/sbin is not in your PATH then fall back to fuzzier -C check_proc
  if check_with_regex and absolute_path != ''
    proc_pattern = "--ereg-argument-array \"^#{absolute_path.chomp("\n")}$\""
  else
    proc_pattern = "-C #{name}"
  end
  proc_cmd = "#{$plugin_dir}/check_procs -w 1: -u #{owner} #{proc_pattern}"
  puts "executing #{proc_cmd}" if $debug
  proc_data = `#{proc_cmd}`
  proc_result = {}
  proc_result['returncode'] = $?.exitstatus
  proc_result['text'] = proc_data.chomp()
  proc_result['perfdata'] = ''
  puts proc_result if $debug
  return proc_result
end

def check_ram(warn, crit)
  debug_header(__method__)
  mf = '/proc/meminfo'
  puts "inspecting #{mf}" if $debug
  total, free, buffers, cached, slabr = 0, 0, 0, 0, 0
  File.open(mf, 'r').each do |line|
    case line
    when /^(?:MemTotal:)\s+([0-9]+) kB$/
      total = $~[1].to_i
    when /^(MemFree|Buffers|Cached|SReclaimable):\s+([0-9]+) kB$/
      free += $~[2].to_i
      type = $~[1].to_s
      if type == 'Buffers'
        buffers = $~[2].to_i
      elsif type == 'Cached'
        cached = $~[2].to_i
      elsif type == 'SReclaimable'
        slabr = $~[2].to_i
      end
    end
  end
  ram_result = {}
  # MB is better readable than kB
  free /= 1024
  total /= 1024
  percent_free = (free / (total / 100.0)).round()
  if percent_free <= crit
    text = 'CRITICAL'
    rc = 2
    # TODO exec 'ps aux --sort -rss | head' and append to long output
  elsif percent_free <= warn
    text = 'WARNING'
    rc = 1
  else
    text = 'OK'
    rc = 0
  end
  ram_result['returncode'] = rc
  ram_result['text'] = "#{text} - #{percent_free}% RAM free: #{free}MB total: #{total}MB"
  ram_result['perfdata'] = "ram_free_percent=#{percent_free}%;#{warn};#{crit};0;100 ram_free=#{free}MB;#{(warn * total) / 100};#{(crit * total) / 100};0;#{total} ram_buffers=#{buffers / 1024}MB ram_cached=#{cached / 1024}MB ram_slabr=#{slabr / 1024}MB"
  puts ram_result if $debug
  return ram_result
end

def check_ntp(warn, crit)
  debug_header(__method__)
  ntp_cmd = "`which ntpq` -np"
  puts "executing #{ntp_cmd}" if $debug
  ntp_output = `#{ntp_cmd}`.split("\n")
  ntp_offset, ntp_server = 999, 'unknown'
  ntp_output.each do |line|
    if line =~ /^\*/
      ntp_data = line.split("\s")
      # offset is in ms not in seconds!
      ntp_offset = ntp_data[-2].to_f / 1000
      ntp_server = ntp_data[0][1..-1]
    end
  end
  ntp_result = {}
  if ntp_offset >= crit
    text = 'CRITICAL'
    rc = 2
  elsif ntp_offset >= warn
    text = 'WARNING'
    rc = 1
  else
    text = 'OK'
    rc = 0
  end
  ntp_result['returncode'] = rc
  ntp_result['text'] = "#{text} - NTP offset: #{ntp_offset} seconds against #{ntp_server}"
  ntp_result['perfdata'] = "ntp_offset=#{ntp_offset}s;#{warn};#{crit}"
  puts ntp_result if $debug
  return ntp_result
end

def check_uptime(secs)
  debug_header(__method__)
  upf = '/proc/uptime'
  puts "inspecting #{upf}" if $debug
  m = nil
  File.open(upf, 'r').each do |line|
    m = line.match(/^([0-9]+)\./)
  end
  uptime_result = {}
  if m
    sec_since_boot = m[1].to_i
    if sec_since_boot <= secs
      uptime_result['returncode'] = 1
      uptime_result['text'] = "WARNING - Uptime #{humanize(sec_since_boot)}"
      uptime_result['perfdata'] = "uptime=#{m[1]}s;#{secs};;0"
    else
      uptime_result['returncode'] = 0
      uptime_result['text'] = "OK - Uptime #{humanize(sec_since_boot)}"
      uptime_result['perfdata'] = "uptime=#{m[1]}s;#{secs};;0"
    end
  else
    uptime_result['returncode'] = 3
    uptime_result['text'] = 'UNKNOWN: Uptime regex failed to match'
    uptime_result['perfdata'] = "uptime=0s;#{secs};;0"
  end
  puts uptime_result if $debug
  return uptime_result
end  

def check_oom()
  debug_header(__method__)
  oom_cmd = "dmesg | awk '/invoked oom-killer:/ || /Killed process/'"
  puts "executing #{oom_cmd}" if $debug
  oom_data = `#{oom_cmd}`
  lines_count = oom_data.split("\n").size
  oom_result = {'perfdata' => "oom_killer_lines=#{lines_count}"}
  if lines_count == 2
    oom_result['returncode'] = 1
    invoked_line, killed_line = oom_data.split("\n")
    killed_pid = killed_line.split(" ")[3]
    killed_cmd = "dmesg | grep #{killed_pid}]"
    puts "executing #{killed_cmd}" if $debug
    killed_data = `#{killed_cmd}`
    killed_pid_rss = killed_data.split(" ")[-5].to_i
    oom_result['text'] = "WARNING: #{invoked_line.split(" ")[1]} invoked oom-killer: #{killed_line.split(" ")[1..4].join(" ")} to free #{killed_pid_rss / 1024}MB - reset with dmesg -c when finished"
  elsif lines_count > 3
    # we can't match this with reasonable effort, so just scream for help
    oom_result['returncode'] = 1
    oom_result['text'] = "WARNING: oom-killer was invoked and went on a killing spree (dmesg | awk '/invoked oom-killer:/ || /Killed process/) - reset with dmesg -c when finished"
  else
    oom_result['returncode'] = 0
    oom_result['text'] = "OK: No OOM killer activity found in dmesg output"
    oom_result['perfdata'] = ''
  end
  puts oom_result if $debug
  return oom_result
end

def check_tasks(allowed_zombies = 0)
  debug_header(__method__)
  tasks_cmd = "top -c -b -n1"
  puts "executing #{tasks_cmd}" if $debug
  tasks_data = `#{tasks_cmd}`.split("\n")
  tasks_result = {'perfdata' => '', 'returncode' => 0}
  # How to write unmaintainable ruby code part 1
  rows = %w(total running sleeping stopped zombie)
  m = tasks_data[1].match(/^Tasks:\s*([0-9]+) total,\s*([0-9]+) running,\s*([0-9]+) sleeping,\s*([0-9]+) stopped,\s*([0-9]+) zombie/)
  if m.size > 4 # check if regex did match top output
    # create hash with regex groups as values with cast to Integer
    d = Hash[*rows.zip(m[1..5].map(&:to_i)).flatten]
    tasks_result['perfdata'] = "tasks_total=#{d['total']} tasks_running=#{d['running']} tasks_sleeping=#{d['sleeping']} tasks_stopped=#{d['stopped']} tasks_zombie=#{d['zombie']}"
    if d['zombie'] != 0
      time_now = Time.now.to_i
      text = ''
      # How to write unmaintainable ruby code part 2
      tasks_data[7..tasks_data.size].each do |line|
        if line.match(/\d+\s+Z\s+\d+/)
          zombie = line.split("\s")

          # check if the zombie is at least x seconds old before alarming
          ps_cmd = "ps -p #{zombie[0]} -o lstart"
          puts "executing #{ps_cmd}" if $debug
          ps_data = `#{ps_cmd}`.split("\n")
          if ps_data.size > 1
            zombie_start_date = DateTime.strptime("#{ps_data[1]} #{Time.new.zone}", '%a %b %d %H:%M:%S %Y %Z')
            zombie_start_epoch = zombie_start_date.strftime('%s')
            puts "found zombie_start_date: #{zombie_start_date} zombie_start_epoch: #{zombie_start_epoch}" if $debug
            zombie_age_seconds = time_now - zombie_start_epoch.to_i
            puts "found zombie_age_seconds: #{zombie_age_seconds} because #{time_now} - #{zombie_start_epoch}" if $debug

            # top has 12 columns until the COMMAND column and we
            # do not know if the command string contains more white space 
            if zombie_age_seconds > 3000
              # get PPID of zombie process
              m_ppid = nil
              File.open("/proc/#{zombie[0]}/status", 'r').each do |status_line|
                 m_ppid = status_line.match(/^PPid:\t([0-9]+)\n/)
                 break if m_ppid
              end
              text += "pid: #{zombie[0]} #{zombie[11..zombie.size].join(" ")} user: #{zombie[1]} ppid: #{m_ppid[1]} started: #{zombie_start_date} (#{zombie_age_seconds}s)"
              tasks_result['returncode'] = 1
            end
          end # close ps_data.size > 1
        end # close line.match
      end # close d['zombie'] != 0
    end # close m.size > 4
  if tasks_result['returncode'] == 1
    d['zombie'] > 1 ? p = "processes" : p = "process"
    if d['zombie'] > allowed_zombies
      tasks_result['text'] = "WARNING: Found #{d['zombie']} zombie #{p}: #{text}"
    else
      tasks_result['text'] = "OK: Found #{d['zombie']} <= #{allowed_zombies} allowed zombie #{p}: #{text}"
      tasks_result['returncode'] = 0
      tasks_result['text'] = "OK: Tasks: #{d['total']} total, #{d['running']} running, #{d['sleeping']} sleeping, #{d['stopped']} stopped, #{d['zombie']} zombie"
    end
  elsif tasks_result['returncode'] == 0
    tasks_result['returncode'] = 0
    tasks_result['text'] = "OK: Tasks: #{d['total']} total, #{d['running']} running, #{d['sleeping']} sleeping, #{d['stopped']} stopped, #{d['zombie']} zombie"
  end
  else
    tasks_result['returncode'] = 3
    tasks_result['text'] = "UNKNOWN: check_tasks regex did not match!"
  end
  puts tasks_result if $debug
  return tasks_result
end

def check_os()
  debug_header(__method__)
  type = 'Debian'
  if File.exists?('/etc/redhat-release')
    type = 'RedHat'
  elsif File.exists?('/etc/lsb-release')
    type = 'Ubuntu'
  end
  return type
end

$os_type = check_os()

# Actually call the check functions

results = []
results << check_load(config['check_load']['warn'], config['check_load']['crit'])

# Use sar in interactive mode if the sysstat data file can not be found
sar_interactive_mode = false
if File.exists?("/var/log/sysstat/sa#{Time.now.strftime("%d")}") == false
  sar_interactive_mode = true
  sar_cpu_thread = Thread.new{results << check_sar_cpu(config['check_sar_cpu']['warn'], config['check_sar_cpu']['crit'], sar_interactive_mode)}
else
  results << check_sar_cpu(config['check_sar_cpu']['warn'], config['check_sar_cpu']['crit'], sar_interactive_mode)
end
results << check_ram(config['check_mem']['warn'], config['check_mem']['crit'])

# Only check for swap size and activity if there is any swap present
has_swap = false
File.open('/proc/meminfo', 'r').each do |line|
  case line
  when /^(?:SwapTotal:)\s+([0-9]+) kB$/
    has_swap = true if $~[1].to_i > 0
  end
end
if has_swap and config['check_swap']['enabled'] != false
  results << check_swap(config['check_swap']['warn'], config['check_swap']['crit'], config['check_mem']['warn'], config['check_mem']['crit'])
  if sar_interactive_mode
    sar_swap_thread = Thread.new{results << check_sar_swap(config['check_sar_swap']['warn'], config['check_sar_swap']['crit'], sar_interactive_mode)}
  else
    results << check_sar_swap(config['check_sar_swap']['warn'], config['check_sar_swap']['crit'], sar_interactive_mode)
  end
end

check_disks(config['check_disk']).each {|result| results << result}
results << check_uptime(1800)

begin
  results << check_tasks(config['check_tasks']['allowed_zombies'])
rescue NoMethodError
  results << check_tasks(0)
end
results << check_ntp(config['check_ntp']['warn'], config['check_ntp']['crit'])
results << check_proc('ntpd', 'ntp', false)
case $os_type
  when 'Debian'
    # Debian cron process name is /usr/sbin/cron
    results << check_proc('cron')
    results << check_proc('sshd')
  when 'RedHat'
    # and on RedHat it's crond
    results << check_proc('crond', 'root', false)
    results << check_proc('sshd')
  when 'Ubuntu'
    # But on Ubuntu it's just cron
    results << check_proc('cron', 'root', false)
    # Ubuntu uses sshd -D, so we can't match with regex sshd$
    results << check_proc('sshd', 'root', false)
end
#results << check_proc('rsyslogd', 'root', false)
results << check_oom()

# Wait for the interactive sar threads to terminate
# Appending to an array is thread safe/atomic operation
# http://stackoverflow.com/a/17767589/682847
if sar_interactive_mode
  sar_cpu_thread.join
  if has_swap and config['check_swap']['enabled'] != false
    sar_swap_thread.join
  end
end
puts "\n\nresult array: #{results}\n\n" if $debug


# Aggregate check results

output = {}
output['returncode'] = 0
output['text'] = ''
output['multiline'] = ''
output['perfdata'] = ''
results.each do |result|
  output['perfdata'] += "#{result['perfdata']} " if result['perfdata'] != ''
  if result['returncode'] >= 1
    output['text'] += "#{result['text']} "
    case result['returncode']
    when 3
      output['returncode'] = 3 if result['returncode'] > output['returncode']
    when 2
      output['returncode'] = 2 if result['returncode'] > output['returncode']
    when 1
      output['returncode'] = 1 if result['returncode'] > output['returncode']
    end
  else
    output['multiline'] += "#{result['text']}</br>\n"
  end
end
if output['text'] == ''
  output['text'] = 'OK - everything looks okay'
end

puts "#{output['text']}|#{output['perfdata']}\n#{output['multiline'].chomp()}"

exit output['returncode']
