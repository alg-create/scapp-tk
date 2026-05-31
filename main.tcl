#!/usr/bin/env wish

package require tooltip
package require msgcat
package require asn
package require logger
package require control
namespace import msgcat::*
namespace import tooltip::tooltip
namespace import asn::*

control::control assert enabled 1
namespace import control::assert

##nagelfar syntax tooltip x x
##nagelfar syntax logger::init x
##nagelfar syntax assert E x*
##nagelfar syntax control s x*
##nagelfar syntax asnGetResponse x n
##nagelfar syntax asnGetSequence n n
##nagelfar syntax asnGetSet n n
##nagelfar syntax asnGetContext n n n? n?
##nagelfar syntax asnGetUTF8String n n
##nagelfar syntax asnGetEnumeration n n
##nagelfar syntax asnPeekTag n n n n
##nagelfar syntax asnGetLength n v
##nagelfar syntax asnSequence x x*
##nagelfar syntax asnEnumeration x
##nagelfar syntax asnChoiceConstr x x
##nagelfar syntax asnChoice x x
##nagelfar syntax asnContext x x
##nagelfar syntax asnContextConstr x x
##nagelfar syntax asnNull
##nagelfar syntax asnUTF8String x

set log [logger::init top]

namespace eval rpc {
    control::control assert enabled 1
    namespace import ::control::assert
    variable log
    set log [logger::init top::rpc]

    set listening_socket ""
    set current_socket ""
    array set response {}
    set notifications_allowed 0
}

namespace eval ui {
    set pending_events [list]
    set pending_event_last 0
    array set langlist {
        English en
        German de
        French fr
        Polish pl
    }
    array set evts {
        "Language Selection" ui::build_language_selection
        "Service Selection" ui::build_service_selection
        "Manual Entry" ui::build_manual_entry
        "Amount Entry" ui::build_amount_entry
    }
    set services [list "Card Validity Check" "Payment" "Refund" "Cancellation"]
    array set pans {
        Visa          4485936516057131
        "Visa E."     4917505187608015
        MasterCard    5144061495831024
        Maestro       5038218334590356
        Discover      6011978759425573
        "Diners Club" 30588293701510
        JCB           3537208456619863956
        AmEx          375493854861485
    }
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
    asnGetSequence apdu req
    asnPeekTag req tnumber tclass tconstructed
    rpc::assert {$tnumber == 0 && $tclass eq "CONTEXT" && $tconstructed}
    asnGetContext req cnumber
    rpc::assert {$cnumber == 0}
    asnGetSequence req registration
    set len 0
    asnGetLength registration len
    rpc::assert {$len == 0}
}

proc rpc::handle_request {sock handle} {
    variable log
    variable notifications_allowed
    if {[catch {asnGetResponse $sock apdu} err]} {
        close $sock
        ui::append_log scap rpc "Closed $handle: $err"
        ${log}::debug "handle_request: Closed $handle: $err"
        set rpc::current_socket ""
        ui::update_screen "---"
        return
    }
    ui::append_log scap rpc "Request $handle"
    asnGetSequence apdu req
    asnPeekTag req tnumber tclass tconstructed
    ${log}::debug "$tnumber == 0 && $tclass eq CONTEXT && $tconstructed"
    rpc::assert {$tclass eq "CONTEXT" && $tconstructed}
    if {$tnumber == 2} {
        asnGetContext req cnumber
        rpc::assert {$cnumber == 2}
        asnGetContext req cnumber
        rpc::assert {$cnumber >= 0 && $cnumber <= 5}
        switch $cnumber {
            0 { ${log}::debug "Update interfaces" }
            1 {
                ${log}::debug "Output interaction"
                asnGetSequence req output
                asnGetUTF8String output newLanguage
                ${log}::debug "New language: $newLanguage"
                mclocale $newLanguage
                asnGetSet output what
                asnGetContext what whatNum
                switch $whatNum {
                    0 {
                        asnGetEnumeration what cardholderMessage
                        ui::update_screen [mc $cardholderMessage]
                    }
                    default {
                        error "Scapi Interaction $whatNum isn't supported"
                    }
                }
            }
            2 { ${log}::debug "Print message" }
            3 { ${log}::debug "Entry interaction" }
            4 { ${log}::debug "Authorise service" }
            5 { ${log}::debug "Build Candidate List" }
        }
        # ScapiInteraction ::= {
        #     language: fr
        #     what: what ::= {
        #         20 (crdhldrMsgWelcome)
        #     }
        # }
        puts -nonewline $sock [rpc::ack]
        return
    }
    rpc::assert {$tnumber == 1}
    asnGetContext req cnumber
    ${log}::debug "cnumber == $cnumber"
    rpc::assert {$cnumber == 1}
    asnGetSequence req notificationRequest
    set len 0
    asnGetLength notificationRequest len
    rpc::assert {$len == 0}
    ${log}::debug "Can send notifications"
    set notifications_allowed 1
    fileevent $sock readable {}
}

# 30 06 a2 04 a1 02 05 00
proc rpc::ack {} {
    return [asnSequence [asnChoiceConstr 2 [asnChoiceConstr 1 [asnNull]]]]
}

# ScapiSocketResponse ::= {
#    rsp: ScapiSocketRegistrationAnswer ::= {
#    }
#}
# @retuns 30 04 a0 02 30 00
proc rpc::registration_response {} {
    return [asnSequence [asnChoiceConstr 0 [asnSequence {}]]]
}

proc rpc::language_selection {language_iso_code} {
    return [asnChoiceConstr 3 [asnSequence [asnContextConstr 13 [asnUTF8String $language_iso_code]]]]
}

proc rpc::handle_registration {sock handle} {
    variable log
    if {[catch {asnGetResponse $sock apdu} err]} {
        close $sock
        ui::append_log scap rpc "Closed $handle: $err"
        ${log}::debug "handle_registration: Closed $handle: $err"
        set rpc::current_socket ""
        ui::update_screen "---"
        return
    }
    ui::append_log scap rpc "Received $handle"
    rpc::get_registration_request $apdu
    puts -nonewline $sock [rpc::registration_response]
    fileevent $sock readable [list rpc::handle_request $sock $handle]
}

proc rpc::accept {sock addr port} {
    fconfigure $sock -blocking 0 -buffering none -translation binary -encoding binary
    set handle [format_peer $addr $port]
    ui::append_log scap rpc "Connected $handle"
    fileevent $sock readable [list rpc::handle_registration $sock $handle]
    set rpc::current_socket $sock
}

proc rpc::listen {port} {
    set rpc::listening_socket [socket -server rpc::accept $port]
    ui::append_log scap rpc "Listening [rpc::format_peer :: $port]"
}

proc ui::remove_flashcard {path} {
    destroy $path
    set ui::pending_events [lsearch -all -inline -not -exact $ui::pending_events $path]
}

proc ui::flashcard {base title} {
    incr ui::pending_event_last
    set path [ttk::labelframe $base.f$ui::pending_event_last]
    set hdr [ttk::frame $path.header]
    grid [ttk::button $hdr.close -style Close.Toolbutton -takefocus 0 \
        -text "×" \
        -command "ui::remove_flashcard $path"
    ] -row 0 -column 0 -sticky w
    grid [ttk::label $hdr.title -text $title] -row 0 -column 1 -sticky w
    grid columnconfigure $hdr 1 -weight 1
    $path configure -labelwidget $hdr
    tooltip $hdr.close "Remove event"
    lappend ui::pending_events $path
    return $path
}

proc ui::update_langiso {path} {
    set ui::langiso($path) $ui::langlist($ui::langname($path))
}

proc ui::language_selection_cleanup {path} {
    unset ui::langiso($path)
    unset ui::langname($path)
}

proc ui::build_language_selection {path} {
    variable langlist
    set desc [ttk::label $path.lbl -text "ISO 639-1 code"]
    set lang [ttk::combobox $path.sel -values [array names langlist] -state readonly -textvariable ui::langname($path)]
    set code [ttk::entry $path.code -width 2 -state readonly -textvariable ui::langiso($path)]

    grid $desc -row 0 -column 0
    grid $lang -row 1 -column 0
    grid $code -row 1 -column 1

    bind $lang <<ComboboxSelected>> "ui::update_langiso $path"
    bind $path <<Destroy>> "ui::language_selection_cleanup $path"

    $lang current 0
    ui::update_langiso $path
    return $path
}

proc ui::is_amount_valid {value isOptional} {
    if {[string trim $value] eq ""} {
        return $isOptional
    }
    if {[string is double -strict $value]} {
        return [expr {double($value) >= 0}]
    }
    return 0
}

proc ui::build_amount {path prefix desc isOptional} {
    if {$isOptional} {
        set desc "$desc:"
    } else {
        set desc "$desc: *"
    }
    grid [ttk::label $path.$prefix-label -text $desc] -sticky w
    grid [ttk::entry $path.$prefix-amount -validate focusout -validatecommand "ui::is_amount_valid %P $isOptional"]
    return $path
}

proc ui::build_amount_entry {path} {
    ui::build_amount $path trx "Amount" 0
    ui::build_amount $path supp "Supplementary (tip/gratuity)" 1
    ui::build_amount $path cash "Cashback" 1
    return $path
}

proc ui::build_service_selection {path} {
    grid [ttk::combobox $path.service -values $ui::services -state readonly]
    return $path
}

proc ui::update_pan {path} {
    set ui::pan($path) $ui::pans($ui::brand($path))
}

proc ui::reset_brand {n1 n2 op} {
    variable pans
    foreach brand [array names pans] {
        if {$ui::pan($n2) eq $ui::pans($brand)} {
            set ui::brand($n2) $brand
            return
        }
    }
    set ui::brand($n2) ""
}

proc ui::build_manual_entry {path} {
    variable pans
    set months [list 01 02 03 04 05 06 07 08 09 10 11 12]
    set years  [list 25 26 27 28 29 30]
    ttk::combobox $path.dummy -values [array names pans] -state readonly -textvariable ui::brand($path)
    grid [ttk::label $path.lpan -text "PAN: *"]                 -row 0 -column 0 -sticky w
    grid [ttk::label $path.ldummy -text "or test:"]             -row 0 -column 1 -sticky w
    grid [ttk::entry $path.epan -textvariable ui::pan($path)]   -row 1 -column 0 -sticky we
    grid $path.dummy                                            -row 1 -column 1
    grid [ttk::labelframe $path.expiry -text "Expiration Date"] -row 2 -columnspan 2
    grid [ttk::label $path.expiry.lyear -text "Year: *"]        -row 3 -column 0 -sticky w
    grid [ttk::combobox $path.expiry.eyear -values $years]      -row 4 -column 0
    grid [ttk::label $path.expiry.lmonth -text "Month: *"]      -row 3 -column 1 -sticky w
    grid [ttk::combobox $path.expiry.emonth -values $months]    -row 4 -column 1

    bind $path.dummy <<ComboboxSelected>> "ui::update_pan $path"
    trace add variable ui::pan($path) write ui::reset_brand
    return $path
}

proc ui::show_hide_scrollbar {scroll orientation first last} {
    $scroll set $first $last
    if {$first <= 0.0 && $last >= 1.0} {
        grid remove $scroll
    } else {
        switch $orientation {
            vertical {
                grid $scroll -row 0 -column 0 -sticky nsw
            }
            horizontal {
                grid $scroll -row 1 -column 1 -sticky wes
            }
        }
    }
}

proc ui::update_scrollable_area {path} {
    $path configure -scrollregion [$path bbox all]
}

proc ui::append_log {subsystem method msg} {
    set logarea .p.r.logs
    set numlines [lindex [split [$logarea index "end - 1 line"] "."] 0]
    $logarea configure -state normal
    if {$numlines==24} {$logarea delete 1.0 2.0}
    if {[$logarea index "end-1c"]!="1.0"} {$logarea insert end "\n"}
    $logarea insert end "[clock format [clock seconds] -format "%H:%M:%S"]\t$subsystem\t$method\t$msg"
    $logarea configure -state disabled
}

proc ui::remove_all_flashcards {} {
    destroy {*}[winfo children .p.l.f.c.events]
    set ui::pending_events [list]
    .p.l.f.c.events configure -width 1 -height 1
}

proc ui::update_screen {msg} {
    .p.r.screen configure -state normal
    .p.r.screen delete 1.0 end
    .p.r.screen insert 1.0 $msg .ce
    .p.r.screen configure -state disabled
}

proc ui::build {} {
    variable evts
    set menubar [ttk::frame .top]
    set hamburger [ttk::button $menubar.hamburger -text "\u2630" -width 2]
    set main [ttk::panedwindow .p -orient horizontal]
    set left  [ttk::frame $main.l]
    set right [ttk::frame $main.r]

    $main add $left -weight 1
    $main add $right -weight 1

    ttk::label $left.lbl -text "Notification"
    ttk::button $left.clear -text "Clear ⎚" -command ui::remove_all_flashcards

    ttk::frame $left.f -relief sunken -borderwidth 2
    set vscroll [ttk::scrollbar $left.f.vscroll -orient vertical -command "$left.f.c yview"]
    set hscroll [ttk::scrollbar $left.f.hscroll -orient horizontal -command "$left.f.c xview"]
    canvas $left.f.c -yscrollcommand "ui::show_hide_scrollbar $vscroll vertical" -xscrollcommand "ui::show_hide_scrollbar $hscroll horizontal"
    set ::winId [$left.f.c create window 0 0 -window [ttk::frame $left.f.c.events] -anchor nw]
    bind $left.f.c <Configure> {
        ui::update_scrollable_area .p.l.f.c
    }
    bind $left.f.c.events <Configure> {
        ui::update_scrollable_area .p.l.f.c
    }

    ttk::button $left.send -text "Send ⇨" -command {
        foreach path $ui::pending_events {
            foreach prefix {trx} {
                set w $path.$prefix-amount
                if {[winfo exists $w]} {
                    $path.trx-amount validate
                }
            }
        }
        if {[send_pending_events $rpc::current_socket]} {
            ui::remove_all_flashcards
        }
    }
    ttk::combobox $left.event_selector -values [array names evts] -state readonly -textvariable ui::selected_event
    ttk::button $left.push -text "Add ⇩" -command {
        grid [$ui::evts($ui::selected_event) [ui::flashcard .p.l.f.c.events $ui::selected_event]]
    }

    set screen [text $right.screen -width 24 -height 3 -wrap none -bg "black" -fg "#55ff55" -font {Courier 12}]
    $screen tag add .ce 1.0
    $screen tag configure .ce -justify center
    $screen insert end "---\n" .ce
    $screen configure -state disabled
    set logarea [text $right.logs -wrap char -width 24]

    $left.event_selector current 0

    grid $menubar             -column 0 -row 0 -sticky nwe
    grid $hamburger           -column 0 -row 0
    grid $main                -column 0 -row 1 -sticky nwes

    grid $left.lbl            -column 0 -row 1
    grid $left.push           -column 1 -row 2
    grid $left.send           -column 2 -row 1
    grid $left.clear          -column 2 -row 2
    grid $left.event_selector -column 0 -row 2
    grid $left.f              -column 0 -row 3 -sticky nsew -columnspan 3
    grid $screen              -column 0 -row 0
    grid $logarea             -column 0 -row 1 -stick nsew

    grid $left.f.c            -column 1 -row 0 -sticky nswe

    # 1. Configure the root window to allow the main panedwindow (row 1) to stretch
    grid columnconfigure . 0 -weight 1
    grid rowconfigure    . 0 -weight 0
    grid rowconfigure    . 1 -weight 1

    # 2. Configure the left pane to allow the canvas container (row 3) to stretch
    grid columnconfigure $left 0 -weight 1
    grid rowconfigure    $left 3 -weight 1

    # 3. Configure the canvas container to allow the canvas (row 0) to stretch
    grid columnconfigure $left.f 1 -weight 1
    grid columnconfigure $left.f 0 -weight 0
    grid rowconfigure    $left.f 0 -weight 1

    # 4. Log area
    grid columnconfigure $right 0 -weight 1
    grid rowconfigure    $right 1 -weight 1
}

proc handle_exit {} {
    exit
}

proc send_pending_events {sock} {
    variable log
    if {!$rpc::notifications_allowed} {
        ${log}::warn "No events are accepted by FAT"
        return 0
    }
    set rpc::notifications_allowed 0
    set events {}
    foreach path $ui::pending_events {
        if {[info exists ui::langiso($path)]} {
            append events [rpc::language_selection $ui::langiso($path)]
        }
        foreach prefix {trx supp cash} {
            set w $path.$prefix-amount
            if {[winfo exists $w]} {
                $path.trx-amount validate
            }
        }
    }
    ${log}::debug "Will send [binary encode hex $events] to $sock"
    fileevent $sock readable [list rpc::handle_request $sock "N/A"]
    puts -nonewline $sock [asnSequence [asnChoiceConstr 1 [asnSequence [asnContextConstr 2 [asnSequence $events]]]]]
    return 1
}

#ttk::style theme use clam
ttk::style configure Close.Toolbutton -foreground #cc0000 -padding 1
ttk::style map Close.Toolbutton -foreground {active #ff0000}
ttk::style configure TLabel -padding 4
ttk::style configure TButton -padding 4
ttk::style map TEntry -fieldbackground {invalid #ffdddd}
#ttk::style configure TFrame -borderwidth 1 -relief solid

ui::build

bind all <Key-Escape> {handle_exit; break}
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

mcset en none "None"
mcset pl none "Żaden"
mcset fr none "Aucune"
mcset de none "Keiner"
mcset en payment "Sale"
mcset pl payment "Sprzedaż"
mcset fr payment "Vente"
mcset de payment "Verkauf"
mcset en refund "Refund"
mcset pl refund "Zwrot"
mcset fr refund "Rembourser"
mcset de refund "Rückerstattung"
mcset en cancellation "Cancellation"
mcset pl cancellation "Unieważnienie"
mcset fr cancellation "Annulation"
mcset de cancellation "Stornierung"
mcset en preauth "Pre-Authorisation"
mcset pl preauth "Preautoryzacja"
mcset fr preauth "Pré-autorisation"
mcset de preauth "Vorautorisierung"
mcset en updatePreauth "Update Pre-Auth."
mcset pl updatePreauth "Zaktualizuj preautoryzację"
mcset fr updatePreauth "Mettre à jour la pré-autorisation"
mcset de updatePreauth "Vorautorisierung aktualisieren"
mcset pl deferredPaymentCompletion "Zakończenie odroczonej płatności"
mcset fr deferredPaymentCompletion "Achèvement du paiement différé"
mcset de deferredPaymentCompletion "Abschluss der Zahlungsaufschub"
mcset en voiceAuthorisation "Voice Auth."
mcset pl voiceAuthorisation "Autoryzacja głosowa"
mcset fr voiceAuthorisation "Autorisation vocale"
mcset de voiceAuthorisation "Sprachautorisierung"
mcset en cardholderDetection "Cardholder Detection"
mcset pl cardholderDetection "Wykrywanie posiadacza karty"
mcset fr cardholderDetection "Détection des titulaires de carte"
mcset de cardholderDetection "Karteninhabererkennung"
mcset en cardValidityCheck "Card Validity Check"
mcset pl cardValidityCheck "Sprawdzanie ważności karty"
mcset fr cardValidityCheck "Vérification de la validité de la carte"
mcset de cardValidityCheck "Überprüfung der Kartengültigkeit"
mcset en noShow "No-show"
mcset pl noShow "Brak pokazu"
mcset fr noShow "Non-présentation"
mcset de noShow "No-show"

mcset C    0 crdhldrActNone
mcset C    3 crdhldrEmvApproved
mcset en   3 "Approved."
mcset pl   3 "Zgoda."
mcset fr   3 "Approuvée"
mcset de   3 "Genehmigt"
mcset C    4 crdhldrEmvVoiceAuthRequired
mcset C    6 crdhldrEmvCardError
mcset C    7 crdhldrEmvDeclined
mcset C   10 crdhldrEmvIncorrectPin
mcset C   11 crdhldrEmvInsertCard
mcset en  11 "INSERT CARD"
mcset pl  11 "WŁÓŻ KARTĘ"
mcset fr  11 "INSÉRER LA CARTE"
mcset de  11 "KARTE EINFÜHREN"
mcset C   14 crdhldrEmvPleaseWait
mcset en  14 "Please Wait..."
mcset pl  14 "Proszę czekać..."
mcset fr  14 "S'il vous plaît attendez..."
mcset de  14 "Warten Sie mal..."
mcset C   15 crdhldrEmvProcessingError
mcset C   16 crdhldrEmvRemoveCard
mcset C   17 crdhldrEmvUseChipReader
mcset C   18 crdhldrEmvUseMagStripe
mcset en  18 "USE MAG STRIPE"
mcset pl  18 "UŻYJ PASKA MAGNETYCZNEGO"
mcset fr  18 "UTILISER UNE BANDE MAGNÉTIQUE"
mcset de  18 "MAGNETSTREIFEN VERWENDEN"
mcset C   19 crdhldrEmvTryAgain
mcset C   20 crdhldrMsgWelcome
mcset en  20 "Welcome"
mcset pl  20 "Witamy"
mcset fr  20 "Bienvenue"
mcset de  20 "Willkommen"
mcset C   21 crdhldrMsgPresentCard
mcset C   22 crdhldrMsgProcessing
mcset C   23 crdhldrMsgCardReadOkRemoveCard
mcset C   24 crdhldrMsgPleaseInsertOrSwipeCard
mcset C   25 crdhldrMsgPleaseInsertOneCardOnly
mcset C   26 crdhldrMsgApprovedPleaseSign
mcset C   27 crdhldrMsgAuthorisingPleaseWait
mcset C   28 crdhldrMsgInsertSwipeOrTryAnotherCard
mcset C   29 crdhldrMsgPleaseInsertCard
mcset C   30 crdhldrActClear
mcset C   32 crdhldrMsgSeePhoneForInstructions
mcset C   33 crdhldrMsgPresentCardAgain
mcset C  176 crdhldrEntEnterPan
mcset C  177 crdhldrEntEnterExpiryDate
mcset C  178 crdhldrEntCvdPresence
mcset C  179 crdhldrEntCvd
mcset C  180 crdhldrEntDccConfirmation
mcset C  181 crdhldrMsgSupplementaryAmountNotAllowed
mcset en 181 "Supplementary amount isn't allowed"
mcset pl 181 "Napiwek niedozwolony"
mcset fr 181 "Le montant supplémentaire n'est pas autorisé"
mcset de 181 "Ergänzungsbetrag ist nicht zulässig"
mcset C  182 crdhldrMsgCashbackNotAllowed
mcset en 182 "Cashback Not Allowed"
mcset pl 182 "Wypłata gotówki niedozwolona"
mcset fr 182 "Cashback non autorisé"
mcset de 182 "Cashback nicht erlaubt"
mcset C  183 crdhldrMsgCashbackAmountTooHigh
mcset C  184 crdhldrMsgPaymentAmountTooLowForCashback
mcset C  185 crdhldrMsgTransactionAmountIsOutOfRange
mcset C  196 crdhldrMsgEnterPin
mcset C  192 crdhldrMsgCardWrongWayOrNoChip
mcset C  193 crdhldrMsgReadError
mcset C  194 crdhldrMsgAmount
mcset C  195 crdhldrMsgMaxAmount
mcset C  197 crdhldrMsgEnter
mcset C  198 crdhldrMsgAmountAuthorised
mcset C  199 crdhldrMsgLeftToBePaid
mcset C  201 crdhldrMsgTransactionAborted
mcset en 201 "Transaction Aborted"
mcset pl 201 "Transakcję przerwano"
mcset fr 201 "Transaction annulée"
mcset de 201 "Transaktion abgebrochen"
mcset C  209 crdhldrMsgPaymentApprovedCashbackDeclined
mcset C  211 crdhldrMsgChipErrorReEnterPin
mcset C  212 crdhldrMsgPresentCardOrUseMagstripe
mcset C  213 crdhldrMsgInsertOrPresentCard
mcset C  217 crdhldrMsgInsertOrSwipeCard
mcset C  218 crdhldrMsgNoPin
mcset C  219 crdhldrMsgDifferentChoice
mcset C  220 crdhldrMsgChooseApplication
mcset C  221 crdhldrMsgAmountEstimated
mcset C  222 crdhldrMsgFinalAmount
mcset C  223 crdhldrMsgAmountIncrement
mcset C  224 crdhldrMsgAmountDecrement
mcset C  225 crdhldrMsgPrinterOutOfOrder
mcset C  226 crdhldrMsgTip
mcset C  227 crdhldrMsgCashback
mcset C  228 crdhldrMsgPayment
mcset C  229 crdhldrMsgTotal
mcset C   50 crdhldrMsgRequestSignature
mcset C   51 crdhldrMsgReceiptPrintingFailed
mcset en  51 "Receipt printing failed!"
mcset pl  51 "Drukowanie paragonu nie powiodło się!"
mcset fr  51 "L'impression du reçu a échoué!"
mcset de  51 "Belegdruck fehlgeschlagen!"
mcset C   52 crdhldrMsgTerminalManagmentInProgress
mcset C   53 crdhldrMsgForceTransactionApproval
