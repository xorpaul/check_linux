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
$stderr.reopen($stdout)

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
  # check_oom defaults
  config['check_oom'] = {}
  config['check_oom']['enabled'] = true
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

def check_context_switches()
  debug_header(__method__)
  context_switches_cmd = "vmstat 1 2"
  puts "executing #{context_switches_cmd}" if $debug
  context_switches_data = `#{context_switches_cmd}`.split("\n")[-1].split(" ")[-6]
  context_switches_result = {}
  context_switches_result['returncode'] = 0
  context_switches_result['text'] = "Context Switches: #{context_switches_data} per second"
  context_switches_result['perfdata'] = "ctx_sw=#{context_switches_data}"
  puts context_switches_result if $debug
  return context_switches_result
end

def check_sar()
  debug_header(__method__)
  sar_result = {}
  sar_cmd = "`which sar` 2>&1"
  puts "executing #{sar_cmd}" if $debug
  sar_output = `#{sar_cmd}`
  sar_data = sar_output.split("\n")
  if $?.exitstatus != 0 and sar_data.size <= 2
    sar_result['text'] = "WARNING: sar command failed, check for invalid system activity file"
    sar_result['returncode'] = 1
  else
    sar_result['text'] = "OK: sar looks good"
    sar_result['returncode'] = 0
  end
  puts sar_result if $debug
  return sar_result
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
    sar_cpu_cmd = "`which sar` 2>&1"
    puts "executing #{sar_cpu_cmd}" if $debug
    sar_cpu_output = `#{sar_cpu_cmd}`
    sar_cpu_data = sar_cpu_output.split("\n")
    m = regex.match(sar_cpu_data[-2])
    if m == nil
      m = regex.match(sar_cpu_data[-4])
    end
    if m == nil or $?.exitstatus != 0
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
    sar_cpu_nice = m[2].to_f.round()
    sar_cpu_system = m[3].to_f.round()
    sar_cpu_iowait = m[4].to_f.round()
    sar_cpu_steal = m[5].to_f.round()
    sar_cpu_idle = m[6].to_f.round()

    text = "OK - idle: #{sar_cpu_idle}%"
    rc = 0
    if (100 - sar_cpu_idle) >= crit
      text = "CRITICAL - idle: #{sar_cpu_idle}% < #{100 - crit}%"
      rc = 2
    elsif (100 - sar_cpu_idle) >= warn
      text = "WARNING - idle: #{sar_cpu_idle}% < #{100 - warn}%"
      rc = 1
    end

    # extra alarming for steal time
    if sar_cpu_steal >= 10
      text = "WARNING - steal time: #{sar_cpu_steal}% >= 10%" + text
      rc = 1
    else
      text = "OK - steal time: #{sar_cpu_steal}%" + text
      rc = 0
    end
    sar_cpu_result['returncode'] = rc
    sar_cpu_result['text'] = "#{text} user: #{sar_cpu_user}% system: #{sar_cpu_system}% iowait: #{sar_cpu_iowait}% steal: #{sar_cpu_steal} nice: #{sar_cpu_nice}% interactive_mode: #{interactive_mode}"
    sar_cpu_result['perfdata'] = "%idle=#{sar_cpu_idle}%;#{100-warn};#{100-crit};0 %user=#{sar_cpu_user}%;#{warn};#{crit};0 %system=#{sar_cpu_system}%;#{warn};#{crit};0 %iowait=#{sar_cpu_iowait}%;#{warn};#{crit};0 %nice=#{sar_cpu_nice}%;#{warn};#{crit};0 %steal=#{sar_cpu_steal}%;#{warn};#{crit};0"
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
    sar_swap_cmd = "`which sar` -W 2>&1"
    puts "executing #{sar_swap_cmd}" if $debug
    sar_swap_output = `#{sar_swap_cmd}`
    sar_swap_data = sar_swap_output.split("\n")
    m = regex.match(sar_swap_data[-2])
    if m == nil
      m = regex.match(sar_swap_data[-4])
    end
    if m == nil or $?.exitstatus != 0
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

def check_disk(warn, crit, partition, units='%')
  debug_header(__method__)
  if units != '%'
    disk_cmd = "#{$plugin_dir}/check_disk --units #{units} -w #{warn.gsub('%', '')} -c #{crit.gsub('%', '')} #{partition}"
  else
    disk_cmd = "#{$plugin_dir}/check_disk -w #{warn} -c #{crit} #{partition}"
  end
  puts "executing #{disk_cmd}" if $debug
  disk_data = `#{disk_cmd}`.split('|')
  disk_result = {}
  disk_result['returncode'] = $?.exitstatus
  disk_result['text'] = disk_data[0].chomp("\n")
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
  disks_cmd = "df --local --exclude-type rootfs --exclude-type tmpfs --exclude-type devtmpfs --portability --total"
  puts "executing #{disks_cmd}" if $debug
  disks_data = `#{disks_cmd}`.split("\n")
  # remove column header line
  disks_data = disks_data[1..-1]
  disks_results = []
  disks_data[0..-2].each do |d|
    cols = d.split("\s")
    mountpoint = cols[-1]
    next if mountpoint == '/boot'
    puts disks_config if $debug
    if disks_config.has_key?(mountpoint)
      if disks_config[mountpoint].has_key?('units')
        disks_results << check_disk(disks_config[mountpoint]['warn'], disks_config[mountpoint]['crit'], mountpoint, disks_config[mountpoint]['units'])
      else
        disks_results << check_disk(disks_config[mountpoint]['warn'], disks_config[mountpoint]['crit'], mountpoint)
      end # close case disks_config.has_key?(mountpoint['unit'])
    else
      disks_results << check_disk('10%', '5%', mountpoint)
    end
  end
  total_columns = disks_data[-1].split("\s")
  total_used = total_columns[2].to_i / 1024
  total_size = total_columns[1].to_i / 1024
  total_free = total_columns[3].to_i / 1024
  total_perc = total_columns[4]
  total_result = {'returncode' => 0}
  total_result['text'] = "Total disk space used: #{total_used}MB out of total: #{total_size}MB equals free: #{total_free}MB or #{total_perc}"
  total_result['perfdata'] = "total_used=#{total_used}MB total_size=#{total_size}MB total_free_M=#{total_free}MB total_free_perc=#{total_perc}"
  disks_results << total_result
  return disks_results
end

def check_proc(name, owner='root', check_with_regex=true)
  debug_header("#{__method__} with #{name}")
  absolute_path = `which #{name} 2>/dev/null`
  # if /usr/sbin is not in your PATH then fall back to fuzzier -C check_proc
  if check_with_regex and absolute_path != ''
    proc_pattern = "--ereg-argument-array \"^#{absolute_path.chomp("\n")}$\""
  else
    proc_pattern = "-C '#{name}'"
  end
  proc_cmd = "#{$plugin_dir}/check_procs -w 1: -u #{owner} #{proc_pattern}"
  puts "executing #{proc_cmd}" if $debug
  proc_data = `#{proc_cmd}`
  proc_result = {}
  proc_result['returncode'] = $?.exitstatus
  proc_result['text'] = proc_data.chomp().split('|')[0]
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
  ps_text = ''
  if rc == 1 || rc == 2
    ps_data = `ps aux --sort -rss | head -2`.split("\n")[1].split("\s")
    ps_text = " - top mem proc: #{ps_data[5].to_i/1024}MB #{ps_data[3]}% ram for #{ps_data[10..-1].join(" ")}"
  end
  ram_result['text'] = "#{text} - #{percent_free}% RAM free: #{free}MB total: #{total}MB#{ps_text}"
  ram_result['perfdata'] = "ram_free_percent=#{percent_free}%;#{warn};#{crit};0;100 ram_free=#{free}MB;#{(warn * total) / 100};#{(crit * total) / 100};0;#{total} ram_buffers=#{buffers / 1024}MB ram_cached=#{cached / 1024}MB ram_slabr=#{slabr / 1024}MB"
  puts ram_result if $debug
  return ram_result
end

def check_ntp(warn, crit)
  debug_header(__method__)
  ntp_cmd = "`which ntpq` -np 2>/dev/null"
  puts "executing #{ntp_cmd}" if $debug
  ntp_output = `#{ntp_cmd}`.split("\n")
  ntp_offset, ntp_server = 999, 'unknown'
  ntp_output.each do |line|
    if line =~ /^\*/
      ntp_data = line.split("\s")
      # offset is in ms not in seconds!
      ntp_offset = (ntp_data[-2].to_f / 1000).abs
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

def check_oom(enabled = true)
  debug_header(__method__)
  if enabled != true
    return {'returncode' => 0, 'text' => "#{__method__} is disabled by config setting", 'perfdata' => ''}
  end
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
    # rss column: Resident memory use (in 4 kB pages) http://unix.stackexchange.com/a/128667/38910
    oom_result['text'] = "WARNING: #{invoked_line.split(" ")[1]} invoked oom-killer: #{killed_line.split(" ")[1..4].join(" ")} to free #{killed_pid_rss / 1024 * 4 }MB - reset with dmesg -c when finished"
  elsif lines_count > 3
    # we can't match this with reasonable effort, so just scream for help
    oom_result['returncode'] = 1
    oom_result['text'] = "WARNING: oom-killer was invoked and went on a killing spree. Check /var/log/kern.log and reset with dmesg -c when finished"
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

def check_networkq()
  debug_header(__method__)
  if File.exist?('/bin/ss')
    networkq_cmd = "/bin/ss -utna"
  elsif File.exist?('/usr/sbin/ss')
    networkq_cmd = "/usr/sbin/ss -utna"
  else
    networkq_cmd = "/sbin/ss -utna"
  end
  puts "executing #{networkq_cmd}" if $debug
  networkq_data = `#{networkq_cmd}`.split("\n")
  text = ''
  count, threshold = 0, 200000
  parsed_data = []
  rows = %w(netid state recvq sendq src dest)
  # remove ss column headers
  networkq_data[1..-1].each do |line|
    # create hash with line comlumns as values
    fields = Hash[*rows.zip(line.split("\s")).flatten]
    if fields['recvq'].to_i > threshold or fields['sendq'].to_i > threshold
      parsed_data << fields 
      count += 1
      m_dest = fields['dest'].match('(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\*|::):(\d+|\*)$')
      m_src = fields['src'].match('(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\*|::):(\d+)$')
      if (m_dest and m_src) and (m_dest[1] != "*" and m_src[1] != "*")
        if m_dest[1].to_i != 514 or m_src[1].to_i != 56
          count -= 1
          next
        end
        dest_hostname = `host #{m_dest[0]}`.split("\s")[-1][0..-2]
        dest_hostname = fields['dest'] if $?.exitstatus != 0
        src_hostname = `host #{m_src[0]}`.split("\s")[-1][0..-2]
        src_hostname = fields['src'] if $?.exitstatus != 0
      else
        dest_hostname = fields['dest']
        src_hostname = fields['src']
        puts "networkq line was: #{line}" if $debug
      end
      text += "recvq: #{fields['recvq']} sendq: #{fields['sendq']} src: #{src_hostname}:#{m_src[2]} dest: #{dest_hostname}:#{m_dest[2]} "
    end
  end # close line each
  puts parsed_data if $debug
  networkq_result = {'perfdata' => "networkq_connections=#{count}"}
  if count > 0
    networkq_result['returncode'] = 1
    count > 1 ? con = 'connections' : con = 'connection'
    networkq_result['text'] = "WARNING: found #{count} #{con} with queue > #{threshold}, #{text}"
  else
    networkq_result['returncode'] = 0
    networkq_result['text'] = "OK: No connections found with > #{threshold} in sendq or recvq"
  end
  puts networkq_result if $debug
  return networkq_result
end

def check_mailq(warn, crit)
  debug_header(__method__)
  mailq_cmd = "`which mailq` 2>&1 | tail -1"
  puts "executing #{mailq_cmd}" if $debug
  mailq_output = `#{mailq_cmd}`.split(" ")
  count = mailq_output[-1].to_i
  mailq_result = {}
  if count >= crit
    text = 'CRITICAL'
    rc = 2
  elsif count >= warn
    text = 'WARNING'
    rc = 1
  else
    text = 'OK'
    rc = 0
  end
  mailq_result['returncode'] = rc
  mailq_result['text'] = "#{text} - mailq messages: #{count}"
  mailq_result['perfdata'] = "mailq_count=#{count};#{warn};#{crit}"
  puts mailq_result if $debug
  return mailq_result
end

def check_drbd()
  debug_header(__method__)
  drbd_cmd = "#{$plugin_dir}/check_drbd 2>&1"
  puts "executing #{drbd_cmd}" if $debug
  drbd_data = `#{drbd_cmd}`.split('|')
  drbd_result = {}
  drbd_result['returncode'] = $?.exitstatus
  drbd_result['text'] = drbd_data[0].chomp()
  drbd_result['perfdata'] = drbd_data[1].chomp().strip() if drbd_data.size >= 2
  puts drbd_result if $debug
  return drbd_result
end

def check_corosync()
  debug_header(__method__)
  corosync_cmd = "sudo #{$plugin_dir}/check_crm.pl 2>&1"
  puts "executing #{corosync_cmd}" if $debug
  corosync_data = `#{corosync_cmd}`.split('|')
  corosync_result = {}
  corosync_result['returncode'] = $?.exitstatus
  corosync_result['text'] = corosync_data[0].chomp()
  corosync_result['perfdata'] = corosync_data[1].chomp().strip() if corosync_data.size >= 2
  puts corosync_result if $debug
  return corosync_result
end

def check_heartbeat()
  debug_header(__method__)
  heartbeat_cmd = "#{$plugin_dir}/check_heartbeat.sh 2>&1"
  puts "executing #{heartbeat_cmd}" if $debug
  heartbeat_data = `#{heartbeat_cmd}`.split('|')
  heartbeat_result = {}
  heartbeat_result['returncode'] = $?.exitstatus
  heartbeat_result['text'] = heartbeat_data[0].chomp()
  heartbeat_result['perfdata'] = heartbeat_data[1].chomp().strip() if heartbeat_data.size >= 2
  puts heartbeat_result if $debug
  return heartbeat_result
end

def check_sensors(warn_delta=20)
  debug_header(__method__)
  puts "#{__method__}: warn_delta = #{warn_delta}" if $debug
  if File.exist?('/usr/bin/sensors')
    sensors_cmd = '/usr/bin/sensors 2>/dev/null'
  else
    return {'returncode' => 3, 'text' => 'lm-sensors package is not installed!'}
  end
  if $?.exitstatus == 1
    return {'returncode' => 0, 'text' => 'sensors exit code 1, probably VM'}
  end
  puts "executing #{sensors_cmd}" if $debug
  sensors_data = `#{sensors_cmd}`.split("\n")
  sensors_result = {'returncode' => 0, 'text' => '', 'perfdata' => ''}
  ok_text, warn_text = "", ""
  highest_socket, highest_core, highest_high = 0, 0, 0
  socket = 0
  highest_core_temp = 0
  high_threshold = 0
  sensors_data.each do |line|
    if line.start_with?('coretemp-isa-')
      socket_match = line.match(/-[0]*(\d+)/)
      socket = socket_match[1]
    elsif line.start_with?('Core ')
      #m = line.match(/^Core (?<core>\d+):\s+\+?(?<cur>\d+\.\d+|N\/A)(.C)?\s+\(high = \+(?<high>\d+.\d+).C, crit = \+(?<crit>\d+.\d+).C\)/)
      a = line.match(/^Core (\d+):\s+\+?(\d+\.\d+|N\/A)(?:.C)?\s+\(high = \+(\d+.\d+).C, crit = \+(\d+.\d+).C\)/)
      if ! a
        sensors_result['returncode'] = 3
        sensors_result['text'] = "#{__method__} regex did not match"
      else
        m = {'core' => a[1], 'cur' => a[2], 'high' => a[4]}
        #puts m
        high_threshold = m['high'].to_f
        if m['cur'] == 'N/A'
          sensors_result['text'] = "OK: ESX virtual machine detected</br>\n"
        else
          if m['cur'].to_f >= highest_core_temp
            highest_core_temp = m['cur'].to_f
            highest_core = m['core'].to_f
            highest_socket = socket
            highest_high = m['high'].to_f
          end
        end
        if (m['high'].to_f - warn_delta.to_f) >= m['cur'].to_f
        else
          sensors_result['returncode'] = 1
          warn_text += "WARNING: Socket #{socket} Core #{m['core']} temperature is #{m['cur']} >= #{m['high'].to_i - warn_delta.to_f} "
        end
      end

    end # close case start_with?
  end
  ok_text += "OK: Socket #{highest_socket} Core #{highest_core} temperature is #{highest_core_temp} < #{highest_high - warn_delta.to_f}</br>\n"
  sensors_result['perfdata'] += "highest_core_temp=#{highest_core_temp};#{high_threshold};#{high_threshold} "
  if sensors_result['returncode'] == 0
    sensors_result['text'] = ok_text
  else
    sensors_result['text'] = warn_text
  end
  puts sensors_result if $debug
  return sensors_result
end

def check_ipmi()
  debug_header(__method__)
  puts "#{__method__}" if $debug
  if File.exist?('/bin/ipmitool')
    ipmi_cmd = 'sudo /bin/ipmitool sensor 2>/dev/null'
  elsif File.exist?('/usr/bin/ipmitool')
    ipmi_cmd = 'sudo /usr/bin/ipmitool sensor 2>/dev/null'
  else
    return {'returncode' => 3, 'text' => 'ipmitool package is not installed!'}
  end
  puts "executing #{ipmi_cmd}" if $debug
  ipmi_data = `#{ipmi_cmd}`.split("\n")
  if $?.exitstatus == 1
    return {'returncode' => 0, 'text' => 'ipmi exit code 1, probably VM'}
  end
  ipmi_result = {'returncode' => 0, 'text' => '', 'perfdata' => ''}
  ok_text, warn_text = "", ""
  fan_speed_type, fastest_fan = 'RPM', ""
  fastest_fan_speed = 0
  pwr_consumption = 0
  ipmi_data.each do |line|
    if line.start_with?('Pwr Consumption') or line.start_with?('Power Meter')
      pwr_match = line.match(/\| (\d+)/)
      pwr_consumption = pwr_match[1]
      ok_text += "OK: Current power consumption is #{pwr_consumption} watts</br>\n"
    elsif line.match(/^Fan\d+[A-Z]/)
      a = line.match(/^Fan(\d+[A-Z])\s+(?:RPM)?\s+\| (\d+)/)
      m = {'fan' => a[1], 'speed' => a[2]}
      if m['speed'].to_i >= fastest_fan_speed
        fastest_fan_speed = m['speed'].to_i
        fastest_fan = m['fan']
      end
    elsif line.match(/^Fan Block/)
      a = line.match(/^Fan Block (\d+)\s+\| (\d+)/)
      m = {'fan' => a[1], 'speed' => a[2]}
      if m['speed'].to_i >= fastest_fan_speed
        fastest_fan_speed = m['speed'].to_i
        fastest_fan = m['fan']
        fan_speed_type = 'percent utilization'
      end

    end # close case start_with?
  end
  ok_text += "OK: Fastest Fan is FAN#{fastest_fan} with #{fastest_fan_speed} #{fan_speed_type}</br>\n"
  ipmi_result['perfdata'] += "fastest_fan_speed=#{fastest_fan_speed};; "
  ipmi_result['perfdata'] += "pwr_consumption=#{pwr_consumption};; "
  if ipmi_result['returncode'] == 0
    ipmi_result['text'] = ok_text
  else
    ipmi_result['text'] = warn_text
  end
  puts ipmi_result if $debug
  return ipmi_result
end

def check_os()
  debug_header(__method__)
  if File.exist?('/etc/centos-release')
    type = 'Centos'
  elsif File.exist?('/etc/redhat-release')
    type = 'RedHat'
  elsif File.exist?('/etc/lsb-release')
    type = 'Ubuntu'
  elsif File.exist?('/etc/os-release')
    type = 'Debian'
    #m = File.open('/etc/os-release').grep(/^VERSION_ID="8"/)
    #type = 'Debian8' if m[0]
  end
  return type
end

$os_type = check_os()

sysstat_dir = '/var/log/sysstat'
if $os_type == 'RedHat' ||  $os_type == 'Centos'
  sysstat_dir = '/var/log/sa'
end


# Actually call the check functions

results = []
begin
  results << check_load(config['check_load']['warn'], config['check_load']['crit'])
rescue NoMethodError
  pc = `grep -c vendor_id /proc/cpuinfo`.to_i
  results << check_load("#{pc + 4},#{pc + 3},#{pc + 2}", "#{pc + 8},#{pc + 7},#{pc + 6}")
end
results << check_context_switches()

# Use sar in interactive mode if the sysstat data file can not be found
begin
  sar_interactive_mode = config['check_sar_cpu']['interactive'] if config['check_sar_cpu'].has_key?('interactive')
rescue
  sar_interactive_mode = false
end
if File.exist?("#{sysstat_dir}/sa#{Time.now.strftime("%d")}")
  begin
    results << check_sar_cpu(config['check_sar_cpu']['warn'], config['check_sar_cpu']['crit'], sar_interactive_mode)
  rescue
    results << check_sar_cpu(90, 95, sar_interactive_mode)
  end
else
  puts "using sar interactive mode..." if $debug
  sar_interactive_mode = true
  sar_cpu_thread = Thread.new{results << check_sar_cpu(config['check_sar_cpu']['warn'], config['check_sar_cpu']['crit'], sar_interactive_mode)}
  begin
    sar_cpu_thread = Thread.new{results << check_sar_cpu(config['check_sar_cpu']['warn'], config['check_sar_cpu']['crit'], sar_interactive_mode)}
  rescue
    sar_cpu_thread = Thread.new{results << check_sar_cpu(90, 95, sar_interactive_mode)}
  end
end

begin
  results << check_ram(config['check_mem']['warn'], config['check_mem']['crit'])
rescue
  results << check_ram(10, 5)
end

# Only check for swap size and activity if there is any swap present
has_swap = false
File.open('/proc/meminfo', 'r').each do |line|
  case line
  when /^(?:SwapTotal:)\s+([0-9]+) kB$/
    has_swap = true if $~[1].to_i > 0
  end
end
begin
  do_check_swap = true
rescue
  do_check_swap = false
end
if has_swap and do_check_swap != false
  begin
    results << check_swap(config['check_swap']['warn'], config['check_swap']['crit'], config['check_mem']['warn'], config['check_mem']['crit'])
  rescue
    results << check_swap('40%', '20%', 10, 5)
  end
  if sar_interactive_mode
    begin
      sar_swap_thread = Thread.new{results << check_sar_swap(config['check_sar_swap']['warn'], config['check_sar_swap']['crit'], sar_interactive_mode)}
    rescue
      sar_swap_thread = Thread.new{results << check_sar_swap(250, 500, sar_interactive_mode)}
    end
  else
    begin
      results << check_sar_swap(config['check_sar_swap']['warn'], config['check_sar_swap']['crit'], sar_interactive_mode)
    rescue
      results << check_sar_swap(250, 500, sar_interactive_mode)
    end
  end
end

check_disks(config['check_disk']).each {|result| results << result}
results << check_uptime(1800)

begin
  results << check_tasks(config['check_tasks']['allowed_zombies'])
rescue NoMethodError
  results << check_tasks(0)
end
begin
  results << check_ntp(config['check_ntp']['warn'], config['check_ntp']['crit'])
rescue
  results << check_ntp(5, 10)
end
results << check_proc('ntpd', 'ntp', false)
case $os_type
  when 'Debian'
    # Debian cron process name is /usr/sbin/cron
    results << check_proc('cron', 'root', false)
    results << check_proc('sshd', 'root', false)
  when 'RedHat'
    # and on RedHat it's crond
    results << check_proc('crond', 'root', false)
    results << check_proc('sshd', 'root', false)
  when 'Centos'
    results << check_proc('crond', 'root', false)
    results << check_proc('sshd', 'root', false)
  when 'Ubuntu'
    # But on Ubuntu it's just cron
    results << check_proc('cron', 'root', false)
    # Ubuntu uses sshd -D, so we can't match with regex sshd$
    results << check_proc('sshd', 'root', false)
end
begin
  results << check_proc('rsyslogd', 'root', false) if config['check_proc']['rsyslogd']['enabled']
rescue NoMethodError
  results << check_proc('rsyslogd', 'root', false)
end
begin
  results << check_oom(config['check_oom']['enabled'])
rescue NoMethodError
  results << check_oom()
end
results << check_networkq()
begin
  results << check_sar() if config['check_sar']['enabled']
rescue NoMethodError
  results << check_sar()
end
begin
  results << check_mailq(config['check_mailq']['warn'], config['check_mailq']['crit'])
rescue NoMethodError
  results << check_mailq(500, 10000)
end

if File.exists?('/proc/drbd')
  results << check_drbd()
  begin
    results << check_drbd() if config['check_drbd']['enabled']
  rescue NoMethodError
    results << check_drbd()
  end
end

if File.exists?('/usr/sbin/crm_mon')
  begin
    results << check_corosync() if config['check_corosync']['enabled']
  rescue NoMethodError
    results << check_corosync()
  end
end

if File.exists?('/usr/bin/cl_status')
  begin
    results << check_heartbeat() if config['check_heartbeat']['enabled']
  rescue NoMethodError
    results << check_heartbeat()
  end
end

if File.exists?('/usr/bin/sensors')
  begin
    results << check_sensors(config['check_sensors']['warn']) if config['check_sensors']['warn']
    results << check_sensors() if config['check_sensors']['enabled']
  rescue NoMethodError
    results << check_sensors()
  end
end

if File.exists?('/usr/bin/ipmitool') or File.exists?('/bin/ipmitool')
  begin
    results << check_ipmi() if config['check_ipmi']['enabled']
  rescue NoMethodError
    results << check_ipmi()
  end
end

# Wait for the interactive sar threads to terminate
# Appending to an array is thread safe/atomic operation
# http://stackoverflow.com/a/17767589/682847
if sar_cpu_thread and sar_swap_thread and sar_interactive_mode
  sar_cpu_thread.join
  if has_swap and config['check_swap']['enabled'] != false
    sar_swap_thread.join
  end
end
puts "\n\nresult array: #{results}\n\n" if $debug


# Aggregate check results

output = {}
output['returncode'] = 0
output['crit_text'] = ''
output['warn_text'] = ''
output['unknown_text'] = ''
output['multiline'] = ''
output['perfdata'] = ''
results.each do |result|
  output['perfdata'] += "#{result['perfdata']} " if result['perfdata'] != ''
  if result['returncode'] >= 1
    case result['returncode']
    when 3
      output['returncode'] = 3 if result['returncode'] > output['returncode']
      output['unknown_text'] += "#{result['text']} "
    when 2
      output['returncode'] = 2 if result['returncode'] > output['returncode']
      output['crit_text'] += "#{result['text']} "
    when 1
      output['returncode'] = 1 if result['returncode'] > output['returncode']
      output['warn_text'] += "#{result['text']} "
    end
  else
    output['multiline'] += "#{result['text']}</br>\n"
  end
end
if output['crit_text'] == '' and output['warn_text'] == '' and output['unknown_text'] == ''
  output['warn_text'] = 'OK - everything looks okay - v3.41'
end

puts "#{output['crit_text']}#{output['warn_text']}#{output['unknown_text']}|#{output['perfdata']}\n#{output['multiline'].chomp()}"

exit output['returncode']
