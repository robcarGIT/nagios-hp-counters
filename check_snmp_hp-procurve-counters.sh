#!/bin/bash
# 
# This script gets a series of port counters from HP switches via SNMP.
# First it obtains all counters from the OID tree .1.3.6.1.2.1.16.1.1.1 (indexes, drops, CRC aligns errors, runts, giants, fragments, jabbers...).
# Everything is printed in a long column; then this string is processed to get records and a table, with every record containing the port index and error counters in CSV.
# Then each value in the table is processed when there are actually packets flowing for the port; if even the error counter is > 0 another calculation is done to check if:
# - max critical threshold reached
# - max warning threshold reached
# - max absolute threshold reached
# If the value obtained is bigger than the three thresholds the correspondent Nagios exit code is announced.
##
# Ver. 0.2s
# Last modified by Roberto Carraro (nagios@t3ch.it) on 20150804

# Exit codes in pipeline are the exit codes of the last program to return a non-zero exit code. 
set -o pipefail

# Tmp dir
TMPDIR=/tmp
# Dir where oui.txt (VENDORSFILE) is saved
OUIDIR=/usr/lib/nagios/plugins
# File with all hardware vendors' MAC addresses
VENDORSFILE="$OUIDIR/oui.txt"

# Function that prints plugin usage.
print_usage() {
        echo ""
        echo "This plugin checks HP Procurve switch counters."
        echo ""
        echo "Usage: $0 switch-IP-address community"
        echo ""
        exit 3
}

# If host parameter not specified print usage.
if [ $# -lt 2 ]; then
   print_usage
fi

# Set OID tree base
etherStatsEntry=".1.3.6.1.2.1.16.1.1.1"
snmpMACPortIndexes=".1.3.6.1.2.1.17.4.3.1.2"

# Set maximum number of errors referred to TX+RX packets
# Examples: 
# - to get 1% threshold, set errorsMultiplier to 1000 and maxErrorsWarning or maxErrorsCritical to 10
# - to get 5% threshold, set errorsMultiplier to 1000 and maxErrorsWarning or maxErrorsCritical to 50
# - to get 10% threshold, set errorsMultiplier to 1000 and maxErrorsWarning or maxErrorsCritical to 100
errorsMultiplier=1000
maxErrorsWarning=5
maxErrorsCritical=50
# Set a maximum number of errors in general, not referred to TX+RX packets
maxErrorsGeneral=2000

# The following ones will be used as exit codes by Nagios
readonly EXIT_OK=0
readonly EXIT_WARNING=1
readonly EXIT_CRITICAL=2
readonly EXIT_UNKNOWN=3

# The following flags will be used to evaluate which Nagios exit code to use
warningFlag=0
criticalFlag=0

# Save plugin parameters
switchIpAddr=$1
community=$2

# Temp files
tmpFile="$TMPDIR/check_snmp_hp-procurve-counters-"$switchIpAddr".tmp"
tmpTable="$TMPDIR/check_snmp_hp-procurve-counters-table-"$switchIpAddr".tmp"
tmpResult="$TMPDIR/check-snmp_hp-procurve-counters-tmpResult-"$switchIpAddr".tmp"
tmpResultPorts="$TMPDIR/check-snmp_hp-procurve-counters-tmpResult-ports-"$switchIpAddr".tmp"

# Function to clean up temp files
function cleanUpTempFiles {
   # Delete them if they exist
   if [ -f $tmpFile ]; then
      rm $tmpFile
   fi
   if [ -f $tmpTable ]; then
      rm $tmpTable
   fi
   if [ -f $tmpResult ]; then
      rm $tmpResult
   fi
   if [ -f $tmpResultPorts ]; then
      rm $tmpResultPorts
   fi
}

# Call clean up temp files function
cleanUpTempFiles

# Function that extracts MAC addresses and MAC vendors
function getMAC {
   # Get MAC addresses/vendors connected to the port
   snmpwalk -v 2c -c $community $switchIpAddr $snmpMACPortIndexes | grep -w " "$portIndex | cut -d ' ' -f1 | cut -d '.' -f7-12 | tr "." " " | while read line ; do printf "%02x-" $line; grep -i `printf "%02x-" $line | cut -d '-' -f 1-3` $VENDORSFILE | cut -f3; done>>$tmpResult
}

# Function that checks errors on ports
function checkErrors {
         # If there are no errors don't consider this element and skip to the next one.
         if [ $check -ne 0 ]; then
             # If there is 1 error every N packets there is a potential problem.
             # So we multiply the errors by N and if result is >= $maxErrors there is a potential problem.
             result=$(($check*$errorsMultiplier/$portPkts))
             percentErrors=$(($result/($errorsMultiplier/100)))
             if [ $percentErrors -eq 0 ]; then
                percentErrors="less than 1"
             fi
             # Check if critical threshold has been reached, either as a percentage or as a general maximum.
             if [ $result -ge $maxErrorsCritical ] || [ $check -ge $maxErrorsGeneral ]; then
                echo $description $check "on" $portPkts "packets (ratio "$percentErrors"%) for port" $portDescription "(ID "$portIndex") CRITICAL">>$tmpResult
                echo "MAC(s):">>$tmpResult
		# Call getMAC function
		getMAC
                echo -e "DESCRIPTION:\n"$longDescription>>$tmpResult
                echo -e "COMMON CAUSE:\n"$rootCause>>$tmpResult
                echo "">>$tmpResult
		echo -n $portDescription" ">>$tmpResultPorts
                # Set critical flag
                criticalFlag=1
             elif [ $result -ge $maxErrorsWarning ]; then
                echo $description $check "on" $portPkts "packets (ratio "$percentErrors"%) for port" $portDescription "(ID "$portIndex") WARNING">>$tmpResult
                echo "MAC(s):">>$tmpResult
		# Call getMAC function
		getMAC
                echo -e "DESCRIPTION:\n"$longDescription>>$tmpResult
                echo -e "COMMON CAUSE:\n"$rootCause>>$tmpResult
                echo "">>$tmpResult
		echo -n $portDescription" ">>$tmpResultPorts
                # Set warning flag
                warningFlag=1
             fi
         fi
}

# We are only interested in the 4th column; the new line ('\n') is replaced by a ' ' 
# Get array port index
snmpwalk -v 2c -c $community $switchIpAddr $etherStatsEntry.1 | awk '{printf $4 " ";} END {print "";}'>>$tmpFile

# Is it possibile to get answers from switch?
# The exit state of the last command is evaluated '0' if True or '1' if False and is intercepted by '$?'
if [ $? -ne 0 ]; then
   # Something's wrong
   echo "Wrong IP address or SNMP not configured for switch."
   # Call clean up temp files function
   cleanUpTempFiles
   exit $EXIT_UNKNOWN 
fi

# Get number of Tx+Rx packets
snmpwalk -v 2c -c $community $switchIpAddr $etherStatsEntry.5 | awk '{printf $4 " ";} END {print "";}'>>$tmpFile
# Get drop events
snmpwalk -v 2c -c $community $switchIpAddr $etherStatsEntry.3 | awk '{printf $4 " ";} END {print "";}'>>$tmpFile
# Get broadcasts
snmpwalk -v 2c -c $community $switchIpAddr $etherStatsEntry.6 | awk '{printf $4 " ";} END {print "";}'>>$tmpFile
# Get multicasts
snmpwalk -v 2c -c $community $switchIpAddr $etherStatsEntry.7 | awk '{printf $4 " ";} END {print "";}'>>$tmpFile
# Get CRC Align errors
snmpwalk -v 2c -c $community $switchIpAddr $etherStatsEntry.8 | awk '{printf $4 " ";} END {print "";}'>>$tmpFile
# Get runts
snmpwalk -v 2c -c $community $switchIpAddr $etherStatsEntry.9 | awk '{printf $4 " ";} END {print "";}'>>$tmpFile
# Get oversize packets (giants)
snmpwalk -v 2c -c $community $switchIpAddr $etherStatsEntry.10 | awk '{printf $4 " ";} END {print "";}'>>$tmpFile
# Get fragments
snmpwalk -v 2c -c $community $switchIpAddr $etherStatsEntry.11 | awk '{printf $4 " ";} END {print "";}'>>$tmpFile
# Get jabbers
snmpwalk -v 2c -c $community $switchIpAddr $etherStatsEntry.12 | awk '{printf $4 " ";} END {print "";}'>>$tmpFile
# Get collisions
snmpwalk -v 2c -c $community $switchIpAddr $etherStatsEntry.13 | awk '{printf $4 " ";} END {print "";}'>>$tmpFile
# Get port description
snmpwalk -v 2c -c $community $switchIpAddr $etherStatsEntry.20 | awk '{printf $5 " ";} END {print "";}' | tr -d \">>$tmpFile

# Now we get a file like this:
# 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76
# 224935329 476719 103394313 199898217 95558954 314561175 90614615 103448233 0 0 0 0 30619216 106471141 0 0 0 95352436 0 107444674 0 0 3979826 0 352300013 0 0 71096 198141466 4813 91680434 28219 0 96965560 0 0 355782799 91580441 97230069 97286930 112667244 0 115509788 24242070 0 0 21770598 24576451 417150301 300460802 229031185 239466808 276054520 210187773 167588139 292748254 403573858 276285333 102166080 540 269961282 197083387 209184569 273590929 216909346 191889683 264054334 279960319 0 262120271 172514094 96410038
# ...

# Obtain the Number of Fields from the first line
LastField=`head -n 1 $tmpFile | awk '{print NF}'`

# Cycle through fields (columns)
for (( i=1; i<=$LastField; i++ ))
   do
      # With printf there's no new line; with print at the END of the row we put a new line
      awk -v I=$i '{printf $I ",";} END {print "";}' $tmpFile>>$tmpTable
   done

# Now we get a new file like this:
#1,225004472,0,14490854,77046678,0,0,0,0,0,0,
#2,476719,0,145062,326014,0,0,0,0,0,0,
#3,103400889,0,14390556,76214085,0,0,0,0,0,0,
#...
#75,172520851,0,14491651,77052981,0,0,0,0,0,0,
#76,96416794,0,14334367,75616867,1,0,0,0,0,0,

# For each line in $tmpTable
#  create an array with the values
while read p; do
   PREV_IFS="$IFS" # Save previous IFS
   IFS=, arrRowTmpTable=($p)
   IFS="$PREV_IFS" # Restore IFS
   # Get values from that line/record
   portIndex=${arrRowTmpTable[0]}
   portPkts=${arrRowTmpTable[1]}
   portDropEvents=${arrRowTmpTable[2]}
   portBroadcasts=${arrRowTmpTable[3]}
   portMulticasts=${arrRowTmpTable[4]}
   portCrcAligns=${arrRowTmpTable[5]}
   portUndersizePkts=${arrRowTmpTable[6]}
   portOversizePkts=${arrRowTmpTable[7]}
   portFragments=${arrRowTmpTable[8]}
   portJabbers=${arrRowTmpTable[9]}
   portCollisions=${arrRowTmpTable[10]}
   portDescription=${arrRowTmpTable[11]}

   # Only proceed if packets for ports are > 0
   if [ $portPkts -ne 0 ]; then

         # Check drop events
         check=$portDropEvents
         description="DROP EVENTS"
         longDescription="Congestion can cause dropped packets, resulting in end nodes timing out and re-trasmitting those packets."
         rootCause="High traffic or network design problems."
         # Call function checkErrors
         checkErrors

#         # Check broadcasts (Rx+Tx)
#         check=$portBroadcasts
#         description="BROADCASTS"
#         # Call function checkErrors
#         checkErrors

#         # Check multicasts (Rx+Tx)
#         check=$portMulticasts
#         description="MULTICASTS"
#         # Call function checkErrors
#         checkErrors

         # Check CRC Align errors
         check=$portCrcAligns
         description="CRC ALIGN ERRORS/FCS"
         longDescription="Wrong checksum or frames received that don't end with an even number of octets."
         rootCause="Half/full duplex mismatch or faulty driver, NIC or faulty cable."
         # Call function checkErrors
         checkErrors

         # Check runts
         check=$portUndersizePkts
         description="RUNTS"
         longDescription="Runts are undersize frames < 64 bytes."
         rootCause="Duplex mismatch or bad cable, port or NIC."
         # Call function checkErrors
         checkErrors

         # Check oversize packets (giants)
         check=$portOversizePkts
         description="GIANTS"
	 longDescription="Frames received that exceed max IEEE 802.3 frame size (1518 bytes)."
         rootCause="Faulty NIC or NIC driver."
         # Call function checkErrors
         checkErrors
 
	 # Check fragments
         check=$portFragments
         description="FRAGMENTS"
         longDescription="Fragments are undersize frames < 64 bytes with a bad CRC."
         rootCause="Duplex mismatch or bad cable, port or NIC."
         # Call function checkErrors
         checkErrors

         # Check jabbers
         check=$portJabbers
         description="JABBERS"
         longDescription="Jabbers are overrsize frames > 1518 bytes with a bad CRC."
         rootCause="Bad cable or NIC."
         # Call function checkErrors
         checkErrors

         # Check collisions
         check=$portCollisions
         description="COLLISIONS"
         longDescription="Collisions occurred before the interface trasmitted a frame to the media successfully."
         rootCause="Normal for half-duplex interfaces; for full-duplex too much traffic for Ethernet to handle or duplex mismatch."
         # Call function checkErrors
         checkErrors

   fi

done <$tmpTable

# Thows out exit codes for Nagios.
# Check if there are some criticals in $tmpFile; don't output anything.
# We are only interested in the exit state of the grep command.

if [[ $criticalFlag -eq 1 ]] && [[ $warningFlag -eq 1 ]]; then
   # At least one critical and one warning found
   echo "Switch $switchIpAddr got at least one CRITICAL and one WARNING counter for port(s): "`cat $tmpResultPorts`
   echo ""
   cat $tmpResult
   # Call clean up temp files function
   cleanUpTempFiles
   # Throws out the exit code which will be handled by Nagios as Critical
   exit $EXIT_CRITICAL
fi

if [[ $criticalFlag -eq 1 ]] ; then
   # At least one critical found
   echo "Switch $switchIpAddr got at least one CRITICAL counter for port(s): "`cat $tmpResultPorts`
   echo ""
   cat $tmpResult
   # Call clean up temp files function
   cleanUpTempFiles
   # Throws out the exit code which will be handled by Nagios as Critical
   exit $EXIT_CRITICAL
fi

if [[ $warningFlag -eq 1 ]] ; then
   # At least one warning found
   echo "Switch $switchIpAddr got at least one WARNING counter for port(s): "`cat $tmpResultPorts`
   echo ""
   cat $tmpResult
   # Call clean up temp files function
   cleanUpTempFiles
   # Throws out the exit code which will be handled by Nagios as Warning
   exit $EXIT_WARNING
else
   # No critical or warning found
   echo "Switch $switchIpAddr counters are ok."
   # Call clean up temp files function
   cleanUpTempFiles
   # Throws out the exit code which will be handled by Nagios as Ok
   exit $EXIT_OK
fi

