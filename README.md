check_linux
===========

Linux monitoring script for Nagios/Icinga/Shinken that wraps other check plugins and uses sar(1), /proc/meminfo, /proc/uptime and /proc/cpuinfo


Managing many different alarm thresholds on a central monitoring server gets tedious very quickly.
This script parses a simple YAML config file, which can contain different thresholds for every server and you can deploy it via Puppet/Chef etc.


![ok](https://github.com/xorpaul/check_linux/raw/master/example-images/ok.png)
![warn](https://github.com/xorpaul/check_linux/raw/master/example-images/warn.png)
![crit](https://github.com/xorpaul/check_linux/raw/master/example-images/crit.png)


PREREQUISITES:
--------
* sysstat for sar(1)

RECOMMENDATIONS:
--------
* Use the sysstat cronjob, so the script doesn't start sar in interactive mode
* Have /usr/sbin in your path to find cron/crond
* Move the config YAML file to a secure location where only root and the monitoring user can edit it


USAGE:
--------

```
$ ruby check_linux.rb --help
Usage: check_linux [options]
    -c, --configfile [FILE]          Config file to use in YAML format, defaults to /tmp/check_linux.cfg.yml
    -d, --debug                      print debug information, defaults to false
$ cat /tmp/check_linux.cfg.yml
---
check_sar_cpu:
  crit: 95
  warn: 90
check_swap:
  crit: 20%
  warn: 40%
check_load:
  crit: "12,12,12"
  warn: "10,10,10"
check_sar_swap:
  crit: 500
  warn: 250
check_mem:
  crit: 5
  warn: 10
check_disk:
  /:
    crit: 5%
    warn: 10%
check_ntp:
  crit: 10
  warn: 5
```

You can edit the YAML file to overide thresholds for each check on specific servers.


**Example**

```
$ ruby check_linux.rb 
WARNING - load average: 9.85, 11.81, 9.32 |load1=9.850;10.000;12.000;0; load5=11.810;10.000;12.000;0; load15=9.320;10.000;12.000;0; %idle=52%;10;5;0 %user=34%;90;95;0 %system=3%;90;95;0 %iowait=11%;90;95;0 ram_free_percent=77%;10;5;0;100 ram_free=18524MB;2415;1207;0;24153 swap=3812MB;1528;764;0;3820 pswpout=0.0;250;500;0 pswpin=0.0;;;0 /=26171MB;120363;127050;0;133737 uptime=2598132s;1800;;0 asks_total=185 tasks_running=1 tasks_sleeping=184 tasks_stopped=0 tasks_zombie=0 ntp_offset=-0.000531s;5;10 
OK - idle: 52% user: 34% system: 3% iowait: 11% interactive_mode: false</br>
OK - 77% RAM free: 18524MB total: 24153MB</br>
SWAP OK - 100% free (3812 MB out of 3820 MB) </br>
OK - pswpout/s: 0.0 pswpin/s: 0.0 interactive_mode false</br>
DISK OK - free space: / 100771 MB (79% inode=92%);</br>
OK - Uptime 30 days 1 hours 42 minutes 12 seconds</br>
OK: Tasks: 185 total, 1 running, 184 sleeping, 0 stopped, 0 zombie</br>
OK - NTP offset: -0.000531 against 172.19.254.253</br>
PROCS OK: 1 process with UID = 101 (ntp), command name 'ntpd'</br>
PROCS OK: 1 process with UID = 0 (root), regex args '^/usr/sbin/cron$'</br>
PROCS OK: 1 process with UID = 0 (root), regex args '^/usr/sbin/sshd$'</br>
OK: No OOM killer activity found in dmesg output</br>
$ echo $?
1
$ sudo /etc/init.d/ntp stop
[ ok ] Stopping NTP server: ntpd.
$ ruby check_linux.rb
/usr/bin/ntpq: read: Connection refused
WARNING - load average: 11.09, 11.98, 9.45 CRITICAL - NTP offset: 999 against unknown PROCS WARNING: 0 processes with UID = 101 (ntp), command name 'ntpd' |load1=11.090;10.000;12.000;0; load5=11.980;10.000;12.000;0; load15=9.450;10.000;12.000;0; %idle=52%;10;5;0 %user=34%;90;95;0 %system=3%;90;95;0 %iowait=11%;90;95;0 ram_free_percent=75%;10;5;0;100 ram_free=18210MB;2415;1207;0;24153 swap=3812MB;1528;764;0;3820 pswpout=0.0;250;500;0 pswpin=0.0;;;0 /=26171MB;120363;127050;0;133737 uptime=2598157s;1800;;0 asks_total=185 tasks_running=1 tasks_sleeping=184 tasks_stopped=0 tasks_zombie=0 ntp_offset=999s;5;10
OK - idle: 52% user: 34% system: 3% iowait: 11% interactive_mode: false</br>
OK - 75% RAM free: 18210MB total: 24153MB</br>
SWAP OK - 100% free (3812 MB out of 3820 MB) </br>
OK - pswpout/s: 0.0 pswpin/s: 0.0 interactive_mode false</br>
DISK OK - free space: / 100771 MB (79% inode=92%);</br>
OK - Uptime 30 days 1 hours 42 minutes 37 seconds</br>
OK: Tasks: 185 total, 1 running, 184 sleeping, 0 stopped, 0 zombie</br>
PROCS OK: 1 process with UID = 0 (root), regex args '^/usr/sbin/cron$'</br>
PROCS OK: 1 process with UID = 0 (root), regex args '^/usr/sbin/sshd$'</br>
OK: No OOM killer activity found in dmesg output</br>
$ echo $?
2
$ ruby check_linux.rb
OK - everything looks okay|load1=9.360;10.000;12.000;0; load5=8.270;10.000;12.000;0; load15=8.520;10.000;12.000;0; %idle=47%;10;5;0 %user=46%;90;95;0 %system=3%;90;95;0 %iowait=4%;90;95;0 ram_free_percent=79%;10;5;0;100 ram_free=19060MB;2415;1207;0;24153 swap=3812MB;1528;764;0;3820 pswpout=0.15;250;500;0 pswpin=0.0;;;0 /=26166MB;120363;127050;0;133737 uptime=2598689s;1800;;0 asks_total=185 tasks_running=1 tasks_sleeping=184 tasks_stopped=0 tasks_zombie=0 ntp_offset=-0.000523s;5;10
OK - load average: 9.36, 8.27, 8.52</br>
OK - idle: 47% user: 46% system: 3% iowait: 4% interactive_mode: false</br>
OK - 79% RAM free: 19060MB total: 24153MB</br>
SWAP OK - 100% free (3812 MB out of 3820 MB) </br>
OK - pswpout/s: 0.15 pswpin/s: 0.0 interactive_mode false</br>
DISK OK - free space: / 100777 MB (79% inode=92%);</br>
OK - Uptime 30 days 1 hours 51 minutes 29 seconds</br>
OK: Tasks: 185 total, 1 running, 184 sleeping, 0 stopped, 0 zombie</br>
OK - NTP offset: -0.000523 against 172.19.255.253</br>
PROCS OK: 1 process with UID = 101 (ntp), command name 'ntpd'</br>
PROCS OK: 1 process with UID = 0 (root), regex args '^/usr/sbin/cron$'</br>
PROCS OK: 1 process with UID = 0 (root), regex args '^/usr/sbin/sshd$'</br>
OK: No OOM killer activity found in dmesg output</br>
$ echo $?
0
```
