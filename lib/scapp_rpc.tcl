package provide scapp_rpc 0.1.0

package require logger
package require control
package require scapi_codec

namespace eval rpc {
    namespace export \
        configure \
        current_socket \
        der_ack \
        der_amount_entry \
        der_language_selection \
        der_notification \
        der_registration_response \
        der_service_selection \
        format_peer \
        get_registration_request \
        listen \
        notifications_allowed \
        send_notification

    control::control assert enabled 1
    namespace import ::control::assert

    variable log
    set log [logger::init top::rpc]

    variable listening_socket ""
    variable current_socket ""
    variable notifications_allowed 0

    variable callbacks
    array set callbacks {
        closed {}
        connected {}
        interaction {}
        log {}
        notification_request {}
    }
}

proc rpc::configure {args} {
    variable callbacks

    if {[llength $args] % 2 != 0} {
        error "wrong # args: should be \"rpc::configure ?-option command ...?\""
    }

    foreach {option command} $args {
        switch -- $option {
            -on-closed { set callbacks(closed) $command }
            -on-connected { set callbacks(connected) $command }
            -on-interaction { set callbacks(interaction) $command }
            -on-log { set callbacks(log) $command }
            -on-notification-request { set callbacks(notification_request) $command }
            default { error "unknown rpc callback option \"$option\"" }
        }
    }
}

proc rpc::emit {name args} {
    variable callbacks

    if {[info exists callbacks($name)] && $callbacks($name) ne ""} {
        uplevel #0 [linsert $callbacks($name) end {*}$args]
    }
}

proc rpc::log_event {msg} {
    rpc::emit log $msg
}

proc rpc::close_current_socket {sock source err} {
    variable current_socket
    variable notifications_allowed
    variable log

    catch {close $sock}
    set current_socket ""
    set notifications_allowed 0

    rpc::log_event "Closed: $err"
    ${log}::debug "$source: Closed: $err"
    rpc::emit closed $sock $err
}

proc rpc::format_peer {addr port} {
    if {[string first ":" $addr] >= 0} {
        return "\[$addr\]:$port"
    } else {
        return "$addr:$port"
    }
}

# Parse SCAP registration request.
#
# @param apdu Received full TLV buffer
#
# ScapiSocketRequest ::= {
#    req: ScapiSocketRegistrationRequest ::= {
#    }
# }
#
# Currently it always exactly: 30 04 a0 02 30 00
proc rpc::get_registration_request {apdu} {
    scapi::codec::decode_registration_request $apdu
}

proc rpc::handle_request {sock} {
    variable log
    variable notifications_allowed

    if {[catch {set apdu [scapi::codec::read_response $sock]} err]} {
        rpc::close_current_socket $sock handle_request $err
        return
    }

    rpc::log_event "New request"
    set request [scapi::codec::decode_socket_request $apdu]
    switch [dict get $request kind] {
        interaction {
            set cnumber [dict get $request choice]
            rpc::assert {$cnumber >= 0 && $cnumber <= 5}
            switch $cnumber {
                0 { ${log}::debug "Update interfaces" }
                1 {
                    ${log}::debug "Output interaction"
                    ${log}::debug "New language: [dict get $request output_language]"
                }
                2 { ${log}::debug "Print message" }
                3 { ${log}::debug "Entry interaction" }
                4 { ${log}::debug "Authorise service" }
                5 { ${log}::debug "Build Candidate List" }
            }

            rpc::emit interaction $sock $request
            puts -nonewline $sock [rpc::der_ack]
            return
        }
        notification_request {
            ${log}::debug "Can send notifications"
            set notifications_allowed 1
            fileevent $sock readable {}
            rpc::emit notification_request $sock
        }
        default {
            error "Unsupported SCAPI request kind [dict get $request kind]"
        }
    }
}

# 30 06 a2 04 a1 02 05 00
proc rpc::der_ack {} {
    return [scapi::codec::encode_ack]
}

# ScapiSocketResponse ::= {
#    rsp: ScapiSocketRegistrationAnswer ::= {
#    }
#}
# @retuns 30 04 a0 02 30 00
proc rpc::der_registration_response {} {
    return [scapi::codec::encode_registration_response]
}

proc rpc::der_language_selection {language_iso_code} {
    return [scapi::codec::encode_language_selection $language_iso_code]
}

proc rpc::der_service_selection {service} {
    return [scapi::codec::encode_service_selection $service]
}

proc rpc::der_amount_entry {amount args} {
    return [scapi::codec::encode_amount_entry $amount {*}$args]
}

proc rpc::der_notification {events} {
    return [scapi::codec::encode_notification $events]
}

proc rpc::handle_registration {sock} {
    if {[catch {set apdu [scapi::codec::read_response $sock]} err]} {
        rpc::close_current_socket $sock handle_registration $err
        return
    }

    rpc::log_event "Received"
    rpc::get_registration_request $apdu
    puts -nonewline $sock [rpc::der_registration_response]
    fileevent $sock readable [list rpc::handle_request $sock]
}

proc rpc::accept {sock addr port} {
    variable current_socket

    fconfigure $sock -blocking 0 -buffering none -translation binary -encoding binary
    set current_socket $sock

    rpc::log_event "Connected [format_peer $addr $port]"
    rpc::emit connected $sock $addr $port
    fileevent $sock readable [list rpc::handle_registration $sock]
}

proc rpc::listen {port} {
    variable listening_socket

    if {$listening_socket ne ""} {
        catch {close $listening_socket}
        set listening_socket ""
    }

    set listening_socket [socket -server rpc::accept $port]
    rpc::log_event "Listening [rpc::format_peer :: $port]"
}

proc rpc::current_socket {} {
    variable current_socket
    return $current_socket
}

proc rpc::notifications_allowed {} {
    variable notifications_allowed
    return $notifications_allowed
}

proc rpc::send_notification {events} {
    variable current_socket
    variable notifications_allowed
    variable log

    if {$current_socket eq "" || !$notifications_allowed} {
        ${log}::warn "No events are accepted by FAT"
        return 0
    }

    set notifications_allowed 0
    ${log}::debug "Will send \[hex [scapi::codec::hex $events]\] to $current_socket"
    fileevent $current_socket readable [list rpc::handle_request $current_socket]
    puts -nonewline $current_socket [rpc::der_notification $events]
    return 1
}
