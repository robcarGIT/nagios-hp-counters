# nagios-hp-counters
This Nagios plugin gets a series of port counters (indexes, drops, CRC aligns errors, runts, giants, fragments, jabbers...) from HP switches via SNMP queries.

When certain (adjustable) thresholds are reached critical or warning signals are raised. 

For example, here a switch was checked for counter errors and two issues were found for port B19. 
The plugin then gets the MAC addresses connected to that port and the vendor id. 
Finally it prints a description and probable cause for the issue. 

Switch 10.10.10.254 got at least one CRITICAL counter for port(s): B19 B19 

CRC ALIGN ERRORS/FCS 2770 on 117891520 packets (ratio less than 1%) for port B19 (ID 45) CRITICAL 
MAC(s): 00-17-95-32-54-07-CISCO SYSTEMS, INC.
DESCRIPTION: 
Wrong checksum or frames received that don't end with an even number of octets. 
COMMON CAUSE: 
Half/full duplex mismatch or faulty driver, NIC or faulty cable. 

COLLISIONS 11443 on 117891520 packets (ratio less than 1%) for port B19 (ID 45) CRITICAL 
MAC(s): 00-17-95-32-54-07-CISCO SYSTEMS, INC.
DESCRIPTION: 
Collisions occurred before the interface trasmitted a frame to the media successfully. 
COMMON CAUSE: 
Normal for half-duplex interfaces; for full-duplex too much traffic for Ethernet to handle or duplex mismatch. 

Now the question is: how many errors are too many? 
The parameters in the script, which can be modified, are set to give: 
- a warning when 5 counter errors are found every 1000 packtes (0,5%) 
- a critical when 50 counter errors are found every 1000 packtes (5%) 
- a critical when an absolute value of 2000 is reached for counter errors 
Btw I'm open to suggestions for which could be the optimal values to use here. 
The plugin has been tested with various HP models: 

Reference: 
http://www.hp.com/rnd/library/troubleshoot_lan.htm 
http://www.cisco.com/c/en/us/support/docs/switches/catalyst-6500-series-switches/12027-53.html 

Instructions. 
Save the plugin in /usr/lib/nagios/plugins/ directory (or whatever directory the other plugins reside in). 
Give execution rights to all for it. 

Download MAC vendors file from: 
http://standards-oui.ieee.org/oui.txt 
Place it in the same directory of the plugin and give execution rights to all for it. 

Then add the following definitions in your config. 

### Icinga2

```
object CheckCommand "check_snmp_hp-procurve-counters"  {
  import "plugin-check-command"

  command = [ PluginDir + "/check_snmp_hp-procurve-counters.sh", ]
  arguments = {
    "-H" = "$host$"
    "-S" = "$snmpcommunity$"
    "-M" = "$errormultiplier$"
    "-W" = "$errorwarning$"
    "-C" = "$errorcritical$"
    "-G" = "$errorgeneral$"
    "-P" = "$excludedports$"
  }
  vars.host = "$check_address$"
  vars.snmpcommunity = "$snmpcommunity$"
  vars.errormultiplier = "$errormultiplier$"
  vars.errorwarning = "$errorwarning$"
  vars.errorcritical = "$errorcritical$"
  vars.errorgeneral = "$errorgeneral$"
  vars.excludedports = "$excludedports$"
}
```

### Nagios

Command definition:

```
define command { 
command_name check_snmp_hp-procurve-counters 
command_line $USER1$/check_snmp_hp-procurve-counters.sh -H $HOSTADDRESS$ -S $ARG1$ -M $ARG2$ -W $ARG3$ -C $ARG4$ -G $ARG5$ -P $ARG6$
} 
```

Service definition: 

```
define service { 
hostgroup_name switch 
service_description HP-counters 
check_command check_snmp_hp-procurve-counters!public!1000!5!50!2000!0
use generic-service 
}
```
