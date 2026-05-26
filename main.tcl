#!/usr/bin/env wish
package require tooltip
package require msgcat
namespace import msgcat::*
namespace import tooltip::tooltip
##nagelfar syntax tooltip x*

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

proc ui::update_scrollable_area {path} {
    $path configure -scrollregion [$path bbox all]
}

proc ui::flashcard {base title} {
    incr ui::pending_event_last
    set path [ttk::labelframe $base.f$ui::pending_event_last]
    set hdr [ttk::frame $path.header]
    grid [ttk::button $hdr.close -style Close.Toolbutton -takefocus 0 \
        -text "×" \
        -command "destroy $path"
    ] -row 0 -column 0 -sticky w
    grid [ttk::label $hdr.title -text $title] -row 0 -column 1 -sticky w
    grid columnconfigure $hdr 1 -weight 1
    $path configure -labelwidget $hdr
    tooltip $hdr.close "Remove event"
    lappend ui::pending_events $path
    ui::update_scrollable_area [winfo parent $base]
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

proc ui::build_amount_entry {path} {
    grid [ttk::label $path.lamount -text "Amount: *"] -sticky w
    grid [ttk::entry $path.eamount]
    grid [ttk::label $path.lsupp -text "Supplementary (tip/gratuity):"] -sticky w
    grid [ttk::entry $path.esupp]
    grid [ttk::label $path.lcashback -text "Cashback:"] -sticky w
    grid [ttk::entry $path.ecashback]
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
    ttk::button $left.clear -text "Clear ⎚" -command {
        foreach path $ui::pending_events {
            destroy $path
        }
    }

    ttk::frame $left.f
    canvas $left.f.c -yscrollcommand "[ttk::scrollbar $left.f.vscroll -orient vertical -command "$left.f.c yview"] set"
    set ::winId [$left.f.c create window 0 0 -window [ttk::frame $left.f.c.events] -anchor nw]
    bind $left.f.c <Configure> {
        ui::update_scrollable_area .p.l.f.c
    }

    ttk::button $left.send -text "Send ⇨"
    ttk::combobox $left.event_selector -values [array names evts] -state readonly -textvariable ui::selected_event
    ttk::button $left.push -text "Add ⇩" -command {
        grid [$ui::evts($ui::selected_event) [ui::flashcard .p.l.f.c.events $ui::selected_event]]
    }

    set screen [text $right.screen -bg "black" -fg "#33ff33" -insertbackground "#33ff33" -font {courier 12 bold} -width 32 -height 3]

    $left.event_selector current 0
    $screen configure -state disabled

    grid $menubar             -column 0 -row 0 -sticky nwe
    grid $hamburger           -column 0 -row 0
    grid $main                -column 0 -row 1 -sticky nwes

    grid $left.lbl            -column 0 -row 1
    grid $left.push           -column 1 -row 2
    grid $left.send           -column 2 -row 1
    grid $left.clear          -column 2 -row 2
    grid $left.event_selector -column 0 -row 2
    grid $left.f              -column 0 -row 3 -sticky nsew -columnspan 3
    grid $screen              -column 1 -row 2

    grid $left.f.vscroll      -column 0 -row 0 -sticky nsw
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
}

proc handle_exit {} {
    exit
}

#ttk::style theme use clam
ttk::style configure Close.Toolbutton -foreground #cc0000 -padding 1
ttk::style map Close.Toolbutton -foreground {active #ff0000}
ttk::style configure TLabel -padding 4
ttk::style configure TButton -padding 4
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
