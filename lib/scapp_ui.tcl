package provide scapp_ui 0.1.0

package require tooltip

namespace eval ui {
    namespace export \
        append_log \
        build \
        pending_event_specs \
        remove_all_flashcards \
        update_screen \
        validate_pending_events

    namespace import ::tooltip::tooltip

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
    set services [list none payment refund cancellation preauth updatePreauth \
    deferredPaymentCompletion voiceAuthorisation cardholderDetection cardValidityCheck noShow]
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

    array set langiso {}
    array set langname {}
    array set amount {}
    array set supplementary_amount {}
    array set cashback {}
    array set selected_service {}
    array set pan {}
    array set brand {}
}

proc ui::reset_state {} {
    variable pending_events
    variable pending_event_last
    variable langiso
    variable langname
    variable amount
    variable supplementary_amount
    variable cashback
    variable selected_service
    variable pan
    variable brand

    set pending_events [list]
    set pending_event_last 0
    array unset langiso
    array unset langname
    array unset amount
    array unset supplementary_amount
    array unset cashback
    array unset selected_service
    array unset pan
    array unset brand
}

proc ui::configure_styles {} {
    #ttk::style theme use clam
    ttk::style configure Close.Toolbutton -foreground #cc0000 -padding 1
    ttk::style map Close.Toolbutton -foreground {active #ff0000}
    ttk::style configure TLabel -padding 4
    ttk::style configure TButton -padding 4
    ttk::style map TEntry -fieldbackground {invalid #ffdddd}
    #ttk::style configure TFrame -borderwidth 1 -relief solid
}

proc ui::remove_flashcard {path} {
    variable pending_events

    destroy $path
    set pending_events [lsearch -all -inline -not -exact $pending_events $path]
}

proc ui::build_flashcard {base title} {
    variable pending_event_last
    variable pending_events

    incr pending_event_last
    set path [ttk::labelframe $base.f$pending_event_last]
    set hdr [ttk::frame $path.header]
    grid [ttk::button $hdr.close -style Close.Toolbutton -takefocus 0 \
        -text "\u00d7" \
        -command "ui::remove_flashcard $path"
    ] -row 0 -column 0 -sticky w
    grid [ttk::label $hdr.title -text $title] -row 0 -column 1 -sticky w
    grid columnconfigure $hdr 1 -weight 1
    $path configure -labelwidget $hdr
    tooltip $hdr.close "Remove event"
    lappend pending_events $path
    return $path
}

proc ui::update_langiso {path} {
    variable langiso
    variable langlist
    variable langname

    set langiso($path) $langlist($langname($path))
}

proc ui::cleanup_language_selection {path} {
    variable langiso
    variable langname

    unset -nocomplain langiso($path)
    unset -nocomplain langname($path)
}

proc ui::build_language_selection {path} {
    variable langlist
    variable langiso
    variable langname

    set desc [ttk::label $path.lbl -text "ISO 639-1 code"]
    set lang [ttk::combobox $path.sel -values [array names langlist] -state readonly -textvariable ui::langname($path)]
    set code [ttk::entry $path.code -width 2 -state readonly -textvariable ui::langiso($path)]

    grid $desc -row 0 -column 0
    grid $lang -row 1 -column 0
    grid $code -row 1 -column 1

    bind $lang <<ComboboxSelected>> "ui::update_langiso $path"
    bind $path <<Destroy>> "ui::cleanup_language_selection $path"

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

proc ui::cleanup_amount_entry {path} {
    variable amount
    variable supplementary_amount
    variable cashback

    unset -nocomplain amount($path)
    unset -nocomplain supplementary_amount($path)
    unset -nocomplain cashback($path)
}

proc ui::build_amount_entry {path} {
    variable amount
    variable supplementary_amount
    variable cashback

    set amount($path) ""
    set supplementary_amount($path) ""
    set cashback($path) ""

    ui::build_amount $path trx "Amount" 0
    ui::build_amount $path supp "Supplementary (tip/gratuity)" 1
    ui::build_amount $path cash "Cashback" 1
    $path.trx-amount configure -textvariable ui::amount($path)
    $path.supp-amount configure -textvariable ui::supplementary_amount($path)
    $path.cash-amount configure -textvariable ui::cashback($path)
    bind $path <<Destroy>> "ui::cleanup_amount_entry $path"
    return $path
}

proc ui::cleanup_service_selection {path} {
    variable selected_service

    unset -nocomplain selected_service($path)
}

proc ui::build_service_selection {path} {
    variable services
    variable selected_service

    grid [ttk::combobox $path.service -values $services -state readonly -textvariable ui::selected_service($path)]
    bind $path <<Destroy>> "ui::cleanup_service_selection $path"
    $path.service current 0
    return $path
}

proc ui::update_pan {path} {
    variable brand
    variable pan
    variable pans

    set pan($path) $pans($brand($path))
}

proc ui::update_brand {n1 n2 op} {
    variable brand
    variable pan
    variable pans

    foreach card_brand [array names pans] {
        if {$pan($n2) eq $pans($card_brand)} {
            set brand($n2) $card_brand
            return
        }
    }
    set brand($n2) ""
}

proc ui::build_manual_entry {path} {
    variable brand
    variable pan
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
    trace add variable ui::pan($path) write ui::update_brand
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
    variable pending_events

    destroy {*}[winfo children .p.l.f.c.events]
    set pending_events [list]
    .p.l.f.c.events configure -width 1 -height 1
}

proc ui::update_screen {msg} {
    .p.r.screen configure -state normal
    .p.r.screen delete 1.0 end
    .p.r.screen insert 1.0 $msg .ce
    .p.r.screen configure -state disabled
}

proc ui::validate_pending_events {} {
    variable pending_events

    foreach path $pending_events {
        foreach prefix {trx supp cash} {
            set w $path.$prefix-amount
            if {[winfo exists $w]} {
                $w validate
            }
        }
    }
}

proc ui::pending_event_specs {} {
    variable pending_events
    variable langiso
    variable selected_service
    variable amount
    variable supplementary_amount
    variable cashback

    set specs {}
    foreach path $pending_events {
        set spec {}

        if {[info exists langiso($path)]} {
            dict set spec language $langiso($path)
        }
        if {[info exists selected_service($path)]} {
            dict set spec service $selected_service($path)
        }
        if {[info exists amount($path)]} {
            dict set spec amount $amount($path)
            if {[info exists supplementary_amount($path)] && [string trim $supplementary_amount($path)] ne ""} {
                dict set spec supplementary $supplementary_amount($path)
            }
            if {[info exists cashback($path)]} {
                dict set spec cashback $cashback($path)
            }
        }

        lappend specs $spec
    }

    return $specs
}

proc ui::invoke_send {send_command} {
    ui::validate_pending_events
    if {[uplevel #0 $send_command]} {
        ui::remove_all_flashcards
    }
}

proc ui::build {send_command} {
    variable evts

    ui::reset_state
    ui::configure_styles

    set menubar [ttk::frame .top]
    set hamburger [ttk::button $menubar.hamburger -text "\u2630" -width 2]
    set main [ttk::panedwindow .p -orient horizontal]
    set left  [ttk::frame $main.l]
    set right [ttk::frame $main.r]

    $main add $left -weight 1
    $main add $right -weight 1

    ttk::label $left.lbl -text "Notification"
    ttk::button $left.clear -text "Clear \u239a" -command ui::remove_all_flashcards

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

    ttk::button $left.send -text "Send \u21e8" -command [list ui::invoke_send $send_command]
    ttk::combobox $left.event_selector -values [array names evts] -state readonly -textvariable ui::selected_event
    ttk::button $left.push -text "Add \u21e9" -command {
        grid [$ui::evts($ui::selected_event) [ui::build_flashcard .p.l.f.c.events $ui::selected_event]]
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
