#!/bin/sh
#
# PROVIDE: zeek
# REQUIRE: NETWORKING pf
# KEYWORD: shutdown
#
# Add the following line to /etc/rc.conf to enable Zeek:
#
#   zeek_enable="YES"
#

. /etc/rc.subr

name="zeek"
rcvar=zeek_enable
desc="Zeek Network Security Monitor (JA4 fingerprinting)"

load_rc_config $name

: ${zeek_enable:="NO"}

command="/usr/local/bin/zeekctl"
required_files="/usr/local/etc/zeek/node.cfg"

start_cmd="zeek_start"
stop_cmd="zeek_stop"
status_cmd="zeek_status"
restart_cmd="zeek_restart"

zeek_start()
{
    echo "Starting ${name}."
    ${command} deploy
}

zeek_stop()
{
    echo "Stopping ${name}."
    ${command} stop
}

zeek_status()
{
    ${command} status
}

zeek_restart()
{
    echo "Restarting ${name}."
    ${command} restart
}

run_rc_command "$1"
