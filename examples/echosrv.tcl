#!/usr/bin/env tclsh

package require Tcl 8.6
package require cmdline

set options {
    {"h.arg"  "127.0.0.1"  "bind-host"}
    {"p.arg"  1818         "listen-port"}
}
set usage ": (USAGE) $argv0 \[options]\n\nOPTIONS:"
try {
    array set params [::cmdline::getoptions argv $options $usage]
} trap {CMDLINE USAGE} {msg o} {
    puts stderr $msg
    exit -1
}

proc handle_echo {ch clientaddr clientport} {
    try {
        set s [chan gets $ch]
        chan puts $ch $s
    } on error {res opt} {
        puts stderr "$res -- $opt"
        puts stderr "Disconnection from $clientaddr:$clientport"
        chan close $ch
    }
}

proc accept_socket {ch clientaddr clientport} {
    puts stderr "Connection from $clientaddr:$clientport"
    chan configure $ch -buffering line -encoding binary -translation binary
    chan event $ch readable [list handle_echo $ch $clientaddr $clientport]
}


puts stderr "Listen on ${params(h)}:${params(p)} ..."
socket -server accept_socket -myaddr $params(h) $params(p)
vwait forever
