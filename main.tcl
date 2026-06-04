#!/usr/bin/env wish

set app_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join $app_dir lib]
lappend auto_path [file join $app_dir deps]

package require msgcat
package require scapp_rpc
package require scapp_ui
namespace import msgcat::*

foreach catalog [lsort [glob -nocomplain -directory [file join $app_dir msgs] *.msg]] {
    source -encoding utf-8 $catalog
}

# Numeric values are defined by nexo, see nexoid sources for more details
array set scap_num_to_msg {
      0 crdhldrActNone
      3 crdhldrEmvApproved
      4 crdhldrEmvVoiceAuthRequired
      6 crdhldrEmvCardError
      7 crdhldrEmvDeclined
     10 crdhldrEmvIncorrectPin
     11 crdhldrEmvInsertCard
     14 crdhldrEmvPleaseWait
     15 crdhldrEmvProcessingError
     16 crdhldrEmvRemoveCard
     17 crdhldrEmvUseChipReader
     18 crdhldrEmvUseMagStripe
     19 crdhldrEmvTryAgain
     20 crdhldrMsgWelcome
     21 crdhldrMsgPresentCard
     22 crdhldrMsgProcessing
     23 crdhldrMsgCardReadOkRemoveCard
     24 crdhldrMsgPleaseInsertOrSwipeCard
     25 crdhldrMsgPleaseInsertOneCardOnly
     26 crdhldrMsgApprovedPleaseSign
     27 crdhldrMsgAuthorisingPleaseWait
     28 crdhldrMsgInsertSwipeOrTryAnotherCard
     29 crdhldrMsgPleaseInsertCard
     30 crdhldrActClear
     32 crdhldrMsgSeePhoneForInstructions
     33 crdhldrMsgPresentCardAgain
    176 crdhldrEntEnterPan
    177 crdhldrEntEnterExpiryDate
    178 crdhldrEntCvdPresence
    179 crdhldrEntCvd
    180 crdhldrEntDccConfirmation
    181 crdhldrMsgSupplementaryAmountNotAllowed
    182 crdhldrMsgCashbackNotAllowed
    183 crdhldrMsgCashbackAmountTooHigh
    184 crdhldrMsgPaymentAmountTooLowForCashback
    185 crdhldrMsgTransactionAmountIsOutOfRange
    196 crdhldrMsgEnterPin
    192 crdhldrMsgCardWrongWayOrNoChip
    193 crdhldrMsgReadError
    194 crdhldrMsgAmount
    195 crdhldrMsgMaxAmount
    197 crdhldrMsgEnter
    198 crdhldrMsgAmountAuthorised
    199 crdhldrMsgLeftToBePaid
    201 crdhldrMsgTransactionAborted
    209 crdhldrMsgPaymentApprovedCashbackDeclined
    211 crdhldrMsgChipErrorReEnterPin
    212 crdhldrMsgPresentCardOrUseMagstripe
    213 crdhldrMsgInsertOrPresentCard
    217 crdhldrMsgInsertOrSwipeCard
    218 crdhldrMsgNoPin
    219 crdhldrMsgDifferentChoice
    220 crdhldrMsgChooseApplication
    221 crdhldrMsgAmountEstimated
    222 crdhldrMsgFinalAmount
    223 crdhldrMsgAmountIncrement
    224 crdhldrMsgAmountDecrement
    225 crdhldrMsgPrinterOutOfOrder
    226 crdhldrMsgTip
    227 crdhldrMsgCashback
    228 crdhldrMsgPayment
    229 crdhldrMsgTotal
     50 crdhldrMsgRequestSignature
     51 crdhldrMsgReceiptPrintingFailed
     52 crdhldrMsgTerminalManagmentInProgress
     53 crdhldrMsgForceTransactionApproval
}

namespace eval app {}

proc app::log_rpc_event {msg} {
    ui::append_log scap rpc $msg
}

proc app::handle_rpc_closed {sock err} {
    ui::update_screen "---"
}

proc app::handle_rpc_interaction {sock request} {
    set cnumber [dict get $request choice]
    switch $cnumber {
        1 {
            set newLanguage [dict get $request output_language]
            mclocale $newLanguage
            set whatNum [dict get $request output_what]
            switch $whatNum {
                0 {
                    set cardholderMessage [dict get $request output_message]
                    ui::update_screen "[mc $::scap_num_to_msg($cardholderMessage)] [format {[%x]} $cardholderMessage]"
                }
                default {
                    error "Scapi Interaction $whatNum isn't supported"
                }
            }
        }
    }
}

proc app::encode_amount_entry {spec} {
    set options {}

    if {[dict exists $spec supplementary]} {
        lappend options -supplementary [dict get $spec supplementary]
    }
    if {[dict exists $spec cashback]} {
        lappend options -cashback [dict get $spec cashback]
    }

    return [rpc::der_amount_entry [dict get $spec amount] {*}$options]
}

proc app::notification_payload {} {
    set events {}

    foreach spec [ui::pending_event_specs] {
        if {[dict exists $spec language]} {
            append events [rpc::der_language_selection [dict get $spec language]]
        }
        if {[dict exists $spec service]} {
            append events [rpc::der_service_selection [dict get $spec service]]
        }
        if {[dict exists $spec amount]} {
            append events [app::encode_amount_entry $spec]
        }
    }

    return $events
}

proc app::send_pending_events {} {
    rpc::send_notification [app::notification_payload]
}

proc app::handle_exit {} {
    exit
}

rpc::configure \
    -on-log app::log_rpc_event \
    -on-closed app::handle_rpc_closed \
    -on-interaction app::handle_rpc_interaction

ui::build app::send_pending_events

bind all <Key-Escape> {app::handle_exit; break}
bind . <F5> {
    catch {destroy .p .top}
    source main.tcl
}

wm title . "Nexo SCAP (tk)"
wm geometry . 800x600
#wm minsize . [expr {int(550 * 1.0)}] [expr {int(550 * 1.0)}]
wm deiconify .
raise .

#puts "Known log levels: [logger::levels]"
#puts "Known services: [logger::services]"

rpc::listen 50153
