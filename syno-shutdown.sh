#!/bin/sh
 
# Path
LOG_PATH="/tmp"
LOGBACKUP_PATH="/volume2/logs/shutdown-script"
# Logfile
LOGFILE_NAME="shutdown-script.log"
LOGFILE="$LOG_PATH/$LOGFILE_NAME"
# Hier werden pro Durchlauf Einträge zum Zählen erzeugt
COUNTFILE="$LOG_PATH/shutdown-counter"
# netstat Log
NETLOG_NAME="shutdown-netstat.log"
NETLOG="$LOG_PATH/$NETLOG_NAME"
# KeepAlive Schalter
KEEPALIVE=0
# X Sekunden warten bevor das Skript beendet wird
WAIT_BEFORE_SCRIPT_EXITS=5
# X Sekunden warten vor dem naechsten Check (in Cron gesteuert)
WAIT_BEFORE_NEXT_CHECK=300
# X Sekunden warten, damit laufende Prozesse beendet werden können
WAIT_BEFORE_SHUTDOWN=15
# minimale Zeit die das NAS eingeschaltet bleibt
MIN_UPTIME=30
# maximale Anzahl der Zyklen die durchlaufen werden bis das NAS herunterfährt wenn kein Client erkannt wurde
MAX_INACTIVE_COUNT=5
# Aktuelles Datum und Zeit
DATUM=`date +%c`
# Stopfile - verhindert dass die Diskstation ausgeschaltet wird
STOPFILE="/tmp/shutdown-stop"
# Shutdownfile - umgeht Checks und schaltet Diskstation aus
SHUTDOWNFILE="/tmp/shutdown-start"
 
log() {
    echo `date +%c` $1 >> $LOGFILE
}
 
logHtml() {
    echo $1 >> $LOGFILE
}
 
logHtmlTd() {
    if [ -z "$2" ] 
    then
        echo "<tr><td>$1</td></tr>" >> $LOGFILE
    else
        echo "<tr class='$2'><td>$1</td></tr>" >> $LOGFILE
    fi
}
 
cancel() {
    [ -f $COUNTFILE ] && rm $COUNTFILE
    logHtml "<table>"
    logHtmlTd "waiting... next check in $WAIT_BEFORE_NEXT_CHECK seconds..." "wait"
    logHtml "</table>"
    sleep $WAIT_BEFORE_SCRIPT_EXITS
    exit 0
}
 
logBackup() {
    if [ -f "$1" ]; then
        if [ -f "$LOGBACKUP_PATH/2_$2" ]; then
            mv "$LOGBACKUP_PATH/2_$2" "$LOGBACKUP_PATH/3_$2"
        fi
        if [ -f "$LOGBACKUP_PATH/1_$2" ]; then
            mv "$LOGBACKUP_PATH/1_$2" "$LOGBACKUP_PATH/2_$2"
        fi
        if [ -f "$LOGBACKUP_PATH/$2" ]; then
            mv "$LOGBACKUP_PATH/$2" "$LOGBACKUP_PATH/1_$2"
        fi
        cp "$1" "$LOGBACKUP_PATH/$2"
    fi
}
 
keepAlive() {
    KEEPALIVE=1
}
 
shutdownDiskstation() {
    logBackup "$LOGFILE" "$LOGFILE_NAME"
    logBackup "$NETLOG" "$NETLOG_NAME"
    sleep $WAIT_BEFORE_SHUTDOWN
    /sbin/poweroff
}
 
##########################################
# Hier ist Platz für die einzelnen Checks
##########################################
 
# Ausgabe ins netstat log. Das ist der aktuelle Zustand der Verbindungen
echo "Aktive Verbindungen mit IP" > $NETLOG
echo "------------------------------------------------------" >> $NETLOG
netstat -n -W -p | grep ESTABLISHED >> $NETLOG
echo "" >> $NETLOG
echo "Aktive Verbindungen mit FQN" >> $NETLOG 
echo "------------------------------------------------------" >> $NETLOG
netstat -W -p | grep ESTABLISHED >> $NETLOG
 
logHtml "<table>"
logHtmlTd "$DATUM" "datum"
logHtmlTd "starting checks" "startcheck"
 
# Prevent shutdown if stopfile exists
if [ -e $STOPFILE ]; then
    logHtmlTd "Stopfile exists. Prevents shutdown!" "initialwait"
    keepAlive
fi
 
# Timecheck
uptime=$(cat /proc/uptime)
uptime=${uptime%%.*}
minutes=$(( uptime/60 ))
if [ $minutes -lt $MIN_UPTIME ]; then
    logHtmlTd "Online since only $minutes minutes. Doing nothing." "initialwait"
    keepAlive
fi
 
# Check if synolocalbkp is running
if [ "$(pidof synolocalbkp)" ]; then
    logHtmlTd "Backup is running" "backup"
    keepAlive
fi
 
# Check if there is a connection via Webinterface or via one of the Apps
WEB_CLIENTS="###Web.Client.Name###"
for client in $WEB_CLIENTS ; do
    if netstat | grep $client | grep ESTABLISHED > /dev/null; then
        logHtmlTd "Active connection to HTTPS Port from web client: $client" "access"
        keepAlive
    fi
done
 
# Check if there is a active connection by a MediaPlayer or other client
MEDIA_CLIENTS="###Media.Client.Name###"
for client in $MEDIA_CLIENTS ; do
    if netstat | grep $client | grep ESTABLISHED > /dev/null; then
        logHtmlTd "Active connection from media client: $client" "access"
        keepAlive
    fi
done
 
# Check if one of the ACTIVEHOSTS has an open connection
ACTIVEHOSTS="192.168.178.xx 192.168.178.xy"
for host in $ACTIVEHOSTS ; do
    if netstat -n | grep ' '$host':.*ESTABLISHED' > /dev/null; then
        hostname=$(nslookup $host | sed -n 's/.*arpa.*name = \(.*\)/\1/p'); 
        logHtmlTd "$host ($hostname) currently accessing NAS" "access"
        keepAlive
    fi
done
 
# Pingcheck - should be performed last - only for clients without permanent access
if [ $KEEPALIVE -eq 0 ]; then
    PINGHOSTS="192.168.178.xx 192.68.178.xy"
    for host in $PINGHOSTS ; do
        if ping -c 1 -w 1 $host > /dev/null; then
            ### log "$host isn't offline"
            logHtmlTd "$host isn't offline" "access"
            keepAlive
        fi
    done
fi
 
logHtmlTd "end checks" "endcheck"
logHtml "</table>"
 
##########################################
# und vorbei
##########################################
 
if [ -e $SHUTDOWNFILE ]; then
    logHtml "<table>"
    logHtmlTd "Shutdownfile exists! Shutting down!" "shutdown"
    logHtml "</table>"
    rm $SHUTDOWNFILE
    if [ -e $COUNTFILE ]; then
        rm $COUNTFILE
    fi
    shutdownDiskstation
fi
 
# Wenn ein Client eingeschaltet ist und erkannt wird,
# wird das Skript mit einer Verzögerung beendet
if [ $KEEPALIVE -eq 1 ]; then
    cancel
fi
 
# Increment counter if all checks failed
echo >>$COUNTFILE
COUNTER=`ls -la $COUNTFILE | awk '{print $5}'`
logHtml "<table>"
logHtmlTd "NAS has been idle for $COUNTER checks" "idle"
logHtml "</table>"
 
# Shutdown NAS if counter has already been incremented X times
if [ $COUNTER -gt $MAX_INACTIVE_COUNT ]; then
    logHtml "<table>"
    logHtmlTd "Shutdown Diskstation!" "shutdown"
    logHtml "</table>"
    if [ -e $COUNTFILE ]; then
        rm $COUNTFILE
    fi
    shutdownDiskstation
fi
