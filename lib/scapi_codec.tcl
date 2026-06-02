package provide scapi_codec 0.1.0

set _scapi_codec_dir [file dirname [file normalize [info script]]]
lappend auto_path [file join [file dirname $_scapi_codec_dir] deps asn-tcl]
unset _scapi_codec_dir

package require asn1

namespace eval scapi {}
namespace eval scapi::codec {
    namespace export \
        decode_notification_request \
        decode_output_interaction_request \
        decode_registration_request \
        decode_socket_request \
        encode_ack \
        encode_amount_entry \
        encode_language_selection \
        encode_notification \
        encode_registration_response \
        encode_service_selection \
        hex \
        read_response

    array set service_to_num {
        none 0
        payment 1
        refund 2
        cancellation 3
        preauth 4
        updatePreauth 5
        completion 6
        cashAdvance 7
        deferredPayment 8
        deferredPaymentCompletion 9
        voiceAuthorisation 16
        cardholderDetection 17
        cardValidityCheck 18
        noShow 19
    }
}

proc scapi::codec::hex {bytes} {
    binary encode hex $bytes
}

proc scapi::codec::read_exact {sock length} {
    set data ""
    while {[string length $data] < $length} {
        set chunk [read $sock [expr {$length - [string length $data]}]]
        if {$chunk eq ""} {
            error "short read"
        }
        append data $chunk
    }
    return $data
}

proc scapi::codec::read_response {sock} {
    set tag [read_exact $sock 1]
    if {$tag ne "\x30"} {
        binary scan $tag H2 tagHex
        error "unknown start tag [string length $tag] $tagHex"
    }

    set firstLengthByte [read_exact $sock 1]
    binary scan $firstLengthByte cu length
    set lengthBytes ""
    if {$length >= 0x80} {
        set lengthByteCount [expr {$length & 0x7f}]
        if {$lengthByteCount == 0} {
            error "indefinite length is not supported for SCAPI socket messages"
        }
        set lengthBytes [read_exact $sock $lengthByteCount]
        set length 0
        for {set i 0} {$i < $lengthByteCount} {incr i} {
            binary scan [string index $lengthBytes $i] cu b
            set length [expr {($length << 8) | $b}]
        }
    }

    set payload [read_exact $sock $length]
    return $tag$firstLengthByte$lengthBytes$payload
}

proc scapi::codec::tlv {tagClass constructed tagNumber value} {
    set tagBytes [asn1::ber_encode_tag $tagClass [expr {$constructed ? 0x20 : 0x00}] $tagNumber]
    return $tagBytes[asn1::ber_encode_length [string length $value]]$value
}

proc scapi::codec::sequence {args} {
    return [tlv 0x00 1 0x10 [join $args ""]]
}

proc scapi::codec::set_of {args} {
    return [tlv 0x00 1 0x11 [join $args ""]]
}

proc scapi::codec::context {tagNumber value} {
    return [tlv 0x80 0 $tagNumber $value]
}

proc scapi::codec::context_constructed {tagNumber args} {
    return [tlv 0x80 1 $tagNumber [join $args ""]]
}

proc scapi::codec::application_constructed {tagNumber value} {
    return [tlv 0x40 1 $tagNumber $value]
}

proc scapi::codec::private_constructed {tagNumber value} {
    return [tlv 0xc0 1 $tagNumber $value]
}

proc scapi::codec::integer {value} {
    return [tlv 0x00 0 0x02 [asn1::ber_encode_integer $value]]
}

proc scapi::codec::enumeration {value} {
    return [tlv 0x00 0 0x0a [asn1::ber_encode_integer $value]]
}

proc scapi::codec::boolean {value} {
    return [tlv 0x00 0 0x01 [binary format c [expr {$value ? -1 : 0}]]]
}

proc scapi::codec::null {} {
    return [tlv 0x00 0 0x05 ""]
}

proc scapi::codec::utf8_string {value} {
    set bytes [encoding convertto utf-8 $value]
    return [tlv 0x00 0 0x0c $bytes]
}

proc scapi::codec::encode_ack {} {
    return [sequence [context_constructed 2 [context_constructed 1 [null]]]]
}

proc scapi::codec::encode_registration_response {} {
    return [sequence [context_constructed 0 [sequence]]]
}

proc scapi::codec::encode_language_selection {languageIsoCode} {
    return [context_constructed 3 [sequence [context_constructed 13 [utf8_string $languageIsoCode]]]]
}

proc scapi::codec::encode_service_selection {service} {
    variable service_to_num
    if {![info exists service_to_num($service)]} {
        error "unknown service '$service'"
    }
    return [context_constructed 4 [sequence [private_constructed 14 [enumeration $service_to_num($service)]]]]
}

proc scapi::codec::encode_amount_entry {amount args} {
    set options [dict create -supplementary "" -cashback ""]
    dict for {key value} $args {
        if {![dict exists $options $key]} {
            error "unknown encode_amount_entry option '$key'"
        }
        dict set options $key $value
    }

    set fields ""
    if {$amount ne ""} {
        set minus [expr {$amount < 0}]
        if {$amount < 0} {
            set amount [expr {abs($amount)}]
        }
        append fields [context_constructed 140 [integer $amount]]
        if {$minus} {
            append fields [context_constructed 147 [boolean 1]]
        }
    }

    set supplementary [dict get $options -supplementary]
    if {$supplementary ne ""} {
        if {$supplementary eq "confirmed"} {
            append fields [context_constructed 0 [boolean 1]]
        } else {
            append fields [context_constructed 143 [integer $supplementary]]
        }
    }

    set cashback [dict get $options -cashback]
    if {$cashback ne ""} {
        append fields [context_constructed 142 [integer $cashback]]
    }

    return [context_constructed 8 [sequence $fields]]
}

proc scapi::codec::encode_notification {events} {
    return [sequence [context_constructed 1 [sequence [context_constructed 2 [sequence $events]]]]]
}

proc scapi::codec::class_name {class} {
    switch -- $class {
        0 { return UNIVERSAL }
        64 { return APPLICATION }
        128 { return CONTEXT }
        192 { return PRIVATE }
    }
    return "UNKNOWN-$class"
}

proc scapi::codec::read_tlv {bytes idxVar} {
    upvar 1 $idxVar idx
    set start $idx
    asn1::ber_decode_tag $bytes idx class constructed tag
    set length [asn1::ber_decode_length $bytes idx]
    if {$length < 0} {
        error "indefinite length is not supported"
    }
    set value [string range $bytes $idx [expr {$idx + $length - 1}]]
    incr idx $length
    return [dict create \
        class $class \
        class_name [class_name $class] \
        constructed [expr {$constructed != 0}] \
        tag $tag \
        length $length \
        value $value \
        bytes [string range $bytes $start [expr {$idx - 1}]] \
    ]
}

proc scapi::codec::expect_tlv {bytes idxVar expectedClass expectedConstructed expectedTag} {
    upvar 1 $idxVar idx
    set tlv [read_tlv $bytes idx]
    if {[dict get $tlv class] != $expectedClass
        || [dict get $tlv constructed] != $expectedConstructed
        || [dict get $tlv tag] != $expectedTag} {
        error "expected tag [class_name $expectedClass]/$expectedTag constructed=$expectedConstructed, got [dict get $tlv class_name]/[dict get $tlv tag] constructed=[dict get $tlv constructed]"
    }
    return $tlv
}

proc scapi::codec::decode_integer_value {tlv expectedTag} {
    if {[dict get $tlv class] != 0 || [dict get $tlv constructed] || [dict get $tlv tag] != $expectedTag} {
        error "expected universal primitive tag $expectedTag"
    }
    return [asn1::ber_decode_integer [dict get $tlv value]]
}

proc scapi::codec::decode_utf8_value {tlv} {
    if {[dict get $tlv class] != 0 || [dict get $tlv constructed] || [dict get $tlv tag] != 12} {
        error "expected UTF8String"
    }
    return [encoding convertfrom utf-8 [dict get $tlv value]]
}

proc scapi::codec::decode_empty_sequence_choice {apdu expectedChoice} {
    set idx 0
    set outer [expect_tlv $apdu idx 0 1 16]
    if {$idx != [string length $apdu]} {
        error "trailing data after outer sequence"
    }

    set req [dict get $outer value]
    set reqIdx 0
    set choice [expect_tlv $req reqIdx 128 1 $expectedChoice]
    if {$reqIdx != [string length $req]} {
        error "trailing data after socket choice"
    }

    set body [dict get $choice value]
    set bodyIdx 0
    expect_tlv $body bodyIdx 0 1 16
    if {$bodyIdx != [string length $body]} {
        error "trailing data after empty sequence"
    }

    return [list \
        tag [dict get $choice tag] \
        class [dict get $choice class_name] \
        constructed [dict get $choice constructed] \
        choice [dict get $choice tag] \
        length 0 \
        remainder {} \
    ]
}

proc scapi::codec::decode_registration_request {apdu} {
    return [decode_empty_sequence_choice $apdu 0]
}

proc scapi::codec::decode_notification_request {apdu} {
    return [decode_empty_sequence_choice $apdu 1]
}

proc scapi::codec::decode_output_interaction_request {apdu} {
    set idx 0
    set outer [expect_tlv $apdu idx 0 1 16]
    if {$idx != [string length $apdu]} {
        error "trailing data after outer sequence"
    }

    set req [dict get $outer value]
    set reqIdx 0
    set requestChoice [expect_tlv $req reqIdx 128 1 2]
    if {$reqIdx != [string length $req]} {
        error "trailing data after request choice"
    }

    set requestBody [dict get $requestChoice value]
    set requestBodyIdx 0
    set interactionChoice [expect_tlv $requestBody requestBodyIdx 128 1 1]
    if {$requestBodyIdx != [string length $requestBody]} {
        error "trailing data after interaction choice"
    }

    set output [dict get $interactionChoice value]
    set outputIdx 0
    set outputSequence [expect_tlv $output outputIdx 0 1 16]
    if {$outputIdx != [string length $output]} {
        error "trailing data after output wrapper"
    }

    set outputFields [dict get $outputSequence value]
    set fieldsIdx 0
    set language [decode_utf8_value [read_tlv $outputFields fieldsIdx]]
    set whatSet [expect_tlv $outputFields fieldsIdx 0 1 17]
    if {$fieldsIdx != [string length $outputFields]} {
        error "trailing data after output fields"
    }

    set whatBytes [dict get $whatSet value]
    set whatIdx 0
    set whatChoice [expect_tlv $whatBytes whatIdx 128 1 0]
    if {$whatIdx != [string length $whatBytes]} {
        error "trailing data after interaction set"
    }

    set choiceValue [dict get $whatChoice value]
    set choiceIdx 0
    set cardholderMessage [decode_integer_value [read_tlv $choiceValue choiceIdx] 10]
    if {$choiceIdx != [string length $choiceValue]} {
        error "trailing data after cardholder message"
    }

    return [list \
        tag [dict get $requestChoice tag] \
        class [dict get $requestChoice class_name] \
        constructed [dict get $requestChoice constructed] \
        outer_choice [dict get $requestChoice tag] \
        inner_choice [dict get $interactionChoice tag] \
        language $language \
        what [dict get $whatChoice tag] \
        message $cardholderMessage \
        req_remainder {} \
        output_remainder {} \
        what_remainder {} \
    ]
}

proc scapi::codec::decode_socket_request {apdu} {
    set idx 0
    set outer [expect_tlv $apdu idx 0 1 16]
    if {$idx != [string length $apdu]} {
        error "trailing data after outer sequence"
    }

    set req [dict get $outer value]
    set reqIdx 0
    set choice [read_tlv $req reqIdx]
    if {[dict get $choice class] != 128 || ![dict get $choice constructed]} {
        error "expected socket request context choice"
    }
    if {$reqIdx != [string length $req]} {
        error "trailing data after socket request choice"
    }

    switch -- [dict get $choice tag] {
        0 {
            decode_registration_request $apdu
            return [dict create kind registration]
        }
        1 {
            decode_notification_request $apdu
            return [dict create kind notification_request]
        }
        2 {
            set body [dict get $choice value]
            set bodyIdx 0
            set interactionChoice [read_tlv $body bodyIdx]
            if {[dict get $interactionChoice class] != 128 || ![dict get $interactionChoice constructed]} {
                error "expected interaction context choice"
            }
            set interactionNumber [dict get $interactionChoice tag]
            if {$bodyIdx != [string length $body]} {
                error "trailing data after interaction request"
            }
            if {$interactionNumber == 1} {
                set decoded [decode_output_interaction_request $apdu]
                return [dict create \
                    kind interaction \
                    choice $interactionNumber \
                    output_language [dict get $decoded language] \
                    output_what [dict get $decoded what] \
                    output_message [dict get $decoded message] \
                ]
            }
            return [dict create kind interaction choice $interactionNumber]
        }
    }

    error "unsupported socket request choice [dict get $choice tag]"
}
