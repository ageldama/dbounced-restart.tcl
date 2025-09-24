#!/usr/bin/env tclsh

#
# Jonghyouk Yun <ageldama@gmail.com>, 2025.
#
# - 시작하면, c.arg 실행 => stdout/stderr print (background?).
# - fswatch 등와 엮어서, stdin 입력이 있으면 k.arg 실행 => c.arg 실행.
# - d.arg 이내에 발생한 stdin은 무시함.
#
# *TODO*
# - k.arg 에서 subst 지원하기? (기존pid?)
#
# [Wed Sep 24 02:04:19 KST 2025]
# - (그래도) pid-file도 필요 없고, kill-switch도 필요 없어서 쓸만함
#

package require Tcl 8.6
package require cmdline
package require Thread
package require processman
package require logger
package require logger::utils



set logger_svc $argv0
set logger [logger::init ${logger_svc}]
logger::utils::applyAppender -appender console -service ${logger_svc}



set options {
    {"c.arg"  ""  "command to start process"}
    {"k.arg"  ""  "command to kill process"}
    {"i.arg"  5   "throttling seconds (0 = no-throttling)"}
    {"v"          "(more) verbose output"}
}
set usage ": (USAGE) $argv0 \[options]\n\nOPTIONS:"
try {
    array set params [::cmdline::getoptions argv $options $usage]
} trap {CMDLINE USAGE} {msg o} {
    ${logger}::info $msg
    exit -1
}

if {$params(v)} {
    ${logger}::enable debug
} else {
    ${logger}::disable debug
}



proc thr_new_empty {} {
    return [::thread::create {
        package require processman
        package require logger
        package require logger::utils

        variable logger
        variable pid

        proc run_cmd {parent_svc cmd} {
            variable pid
            variable logger

            set logger_svc [string cat $parent_svc "::" [::thread::id]]
            set logger [logger::init $logger_svc]
            logger::utils::applyAppender -appender console -service $logger_svc

            set pid [exec $cmd >@ stdout 2>@ stderr &]
            ${logger}::info "STARTED-PID: ${pid}"
        }

        proc kill_proc {} {
            variable pid
            variable logger
            ${logger}::info "KILL-PID: ${pid}"
            ::processman::kill $pid
            ::thread::release -wait
        }

        ::thread::wait
        vwait forever
    }]
}




proc start_proc {thr cmd} {
    variable logger
    variable logger_svc

    try {
        if {0 < [string length $cmd]} {
            ${logger}::info "STARTING: $cmd ..."
            ::thread::send -async $thr [list run_cmd "$logger_svc" "$cmd"]
        } else {
            ${logger}::warn "--- NO START-COMMAND SPECIFIED ---"
        }
    } on error {res opts} {
        ${logger}::error "START_PROC FAIL: $res -- $opts"
    }

    ${logger}::debug "THREADS: [::thread::names]"
}



set thr [thr_new_empty]


proc restart_proc {cmd kill_cmd} {
    variable thr
    variable logger

    if {0 < [string length $kill_cmd]} {
        ${logger}::info "KILL: $ckill_md ..."
        exec $kill_cmd >@ stdout 2>@ stderr
    } else {
        ${logger}::warn "--- NO KILL-COMMAND SPECIFIED ---"
    }

    try {
        ::thread::send $thr [list kill_proc]
        # ::thread::cancel -unwind $thr
    } on error {res opts} {
        ${logger}::error "THR-DEL FAIL: $res -- $opts"
    }

    ${logger}::debug "EXISTING: $thr"
    set new_thr [thr_new_empty]
    ${logger}::debug "NEW:      $new_thr"

    set thr $new_thr

    start_proc $new_thr $cmd
}


set last_restart [clock second]


proc handle_input {ch} {
    variable thr
    variable params
    variable last_restart
    variable logger

    ${logger}::info "--- GOT NEW INPUT ---"
    chan gets $ch

    set cur [clock second]
    if {$last_restart < ($cur - $params(i))} {
        restart_proc $params(c) $params(k)
        set last_restart $cur
    } else {
        set remain [expr {abs($cur - $params(i) - $last_restart)}]
        ${logger}::info "IGNORED: ${remain} seconds left ..."
    }
}


chan configure stdin -buffering line
chan event stdin readable [list handle_input stdin]



start_proc $thr $params(c)

vwait forever
