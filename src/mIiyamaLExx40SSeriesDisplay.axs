MODULE_NAME='mIiyamaLExx40SSeriesDisplay'	(
                                                dev vdvObject,
                                                dev dvPort
                                            )

(***********************************************************)
#include 'NAVFoundation.ModuleBase.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

constant long TL_DRIVE	= 1
// constant long TL_VOLUME_RAMP	= 2

// constant integer HEADER = $A6

constant integer POWER_STATE_ON	= 1
constant integer POWER_STATE_OFF	= 2

constant integer INPUT_VGA	= 1
constant integer INPUT_DISPLAYPORT	= 2
constant integer INPUT_HDMI_1	= 3
constant integer INPUT_DVI	= 4
constant integer INPUT_HDMI_2   = 5

//constant char INPUT_COMMANDS[][NAV_MAX_CHARS]	= { "$AC, $05, $00, $00, $00",  // VGA
//                                                    "$AC, $07, $01, $00, $00",  // DisplayPort
//                                                   "$AC, $0D, $00, $00, $00",  // HDMI 1
//                                                    "$AC, $09, $01, $00, $00", // DVI
//                                                    "$AC, $06, $01, $00, $00" } // HDMI 2

constant integer GET_POWER	= 1
constant integer GET_INPUT	= 2
constant integer GET_AUDIO_MUTE	= 3
constant integer GET_VOLUME	= 4

constant integer MAX_VOLUME = 100
constant integer MIN_VOLUME = 0

(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile integer loop

volatile integer pollSequence = GET_POWER

volatile integer requiredPower
volatile integer requiredInput

volatile integer actualPower
volatile integer actualInput
volatile sinteger siActualVolume

volatile long driveTicks[] = { 200 }

volatile integer semaphore
volatile char rxBuffer[NAV_MAX_BUFFER]

volatile integer commandBusy

volatile integer id = 1

volatile char responseHeader[2]

(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)
(* EXAMPLE: DEFINE_FUNCTION <RETURN_TYPE> <NAME> (<PARAMETERS>) *)
(* EXAMPLE: DEFINE_CALL '<NAME>' (<PARAMETERS>) *)

define_function Send(char payload[]) {
    NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'String To ', NAVConvertDPSToAscii(dvPort), '-[', payload, ']'")
    send_string dvPort, "payload"
}


define_function char[NAV_MAX_CHARS] Build(integer id, char cmd[]) {
    char payload[NAV_MAX_CHARS]

    payload = "$A6, id, $00, $00, $00, length_array(cmd) + 2, $01, cmd"
    payload = "payload, NAVCalculateXOROfBytesChecksum(1, payload)"
    return payload
}


define_function SendQuery(integer query) {
    switch (query) {
        case GET_POWER: Send(Build(id, "$19"))
        case GET_VOLUME: Send(Build(id, "$45"))
        case GET_INPUT: Send(Build(id, "$AD"))
    }
}


define_function TimeOut() {
    cancel_wait 'CommsTimeOut'
    wait 300 'CommsTimeOut' { [vdvObject, DEVICE_COMMUNICATING] = false }
}


define_function SetPower(integer state) {
    switch (state) {
        case POWER_STATE_ON: { Send(Build(id, "$18, $02")) }
        case POWER_STATE_OFF: { Send(Build(id, "$18, $01")) }
    }
}


define_function SetInput(integer iInput) {
    //Send(Build(id, "INPUT_COMMANDS[iInput]"))

    switch (iInput) {
        case INPUT_HDMI_1: {
            Send(Build(id, "$AC, $0D, $00, $00, $00"))
        }
        case INPUT_HDMI_2: {
            Send(Build(id, "$AC, $06, $00, $00, $00"))
        }
    }
}


// define_function RampVolume(integer iParam, sinteger iValue) {
//     switch(iParam) {
//         case VOL_UP: {
//             if((siActualVolume + iValue) < MAX_VOLUME) {
//                 SetVolume(siActualVolume + iValue)
//             }
//             else {
//                 SetVolume(MAX_VOLUME)
//             }
//         }
//         case VOL_DN: {
//             if((siActualVolume - iValue) > MIN_VOLUME) {
//                 SetVolume(siActualVolume - iValue)
//             }
//             else {
//                 SetVolume(MIN_VOLUME)
//             }
//         }
//     }
// }


define_function SetVolume(integer iParam) {
    if (commandBusy) {
        return
    }

    Send(Build(id, "$44, iParam, iParam"))
    // commandBusy = true
    // wait 6 commandBusy = false
    //pollSequence = GET_VOLUME
}


// define_function SetMute(integer iParam) {
//     switch(iParam) {
//         case AUDIO_MUTE_ON: { Send(Build('S', '9', '')) }
//         case AUDIO_MUTE_OFF: { Send(Build('S', '9', '')) }
//     }
// }


define_function SetResponseHeader(integer id) {
    responseHeader = "'!', id"
}


define_function Process() {
    stack_var integer iLen
    stack_var char buffer[NAV_MAX_BUFFER]

    if (semaphore) {
        return
    }

    semaphore = true

    while (length_array(rxBuffer) && NAVContains(rxBuffer, responseHeader)) {
        buffer = remove_string(rxBuffer, responseHeader, 1)

        if (!length_array(buffer)) {
            continue
        }

        buffer = "buffer, get_buffer_string(rxBuffer, 2)"
        iLen = get_buffer_char(rxBuffer)

        buffer = get_buffer_string(rxBuffer, iLen)
        buffer = NAVStripCharsFromLeft(buffer, 1)
        buffer = NAVStripCharsFromRight(buffer, 1)

        switch (get_buffer_char(buffer)) {
            case $19: {
                NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'iiyama Power Query Response'")
                switch (buffer[1]) {
                    case $01: { actualPower = POWER_STATE_OFF }
                    case $02: { actualPower = POWER_STATE_ON }
                }
            }
            case $45: {
                NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'iiyama Volume Query Response'")
            }
            case $AD: {
                NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'iiyama Input Query Response'")
            }
            case $00: {
                NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'iiyama Command Response'")
                // switch (buffer[1]) {
                //     case $00: {
                //         NAVErrorLog(NAV_LOG_LEVEL_DEBUG, 'iiyama Command Ack: Completed')
                //     }
                //     case $01: {
                //         NAVErrorLog(NAV_LOG_LEVEL_DEBUG, 'iiyama Command Error: Limit Over')
                //     }
                //     case $02: {
                //         NAVErrorLog(NAV_LOG_LEVEL_DEBUG, 'iiyama Command Error: Limit Over')
                //     }
                //     case $03: {
                //         NAVErrorLog(NAV_LOG_LEVEL_DEBUG, 'iiyama Command Error: Cancelled')
                //     }
                //     case $04: {
                //         NAVErrorLog(NAV_LOG_LEVEL_DEBUG, 'iiyama Command Error: Parse Error')
                //     }
                // }
            }
        }
    }

    semaphore = false
}


define_function Drive() {
    loop++

    switch (loop) {
        case 5:
        case 10:
        case 15:
        case 20: { SendQuery(pollSequence); return }
        case 25: { loop = 0; return }
        default: {
            if (commandBusy) { return }

            if (requiredPower && (requiredPower == actualPower)) { requiredPower = 0; return }
            if(requiredInput && (requiredInput == actualInput)) { requiredInput = 0; return }
            // if(iRequiredAudioMute && (iRequiredAudioMute == iActualAudioMute)) { iRequiredAudioMute = 0; return }

            if (requiredPower && (requiredPower != actualPower)) {
                commandBusy = true
                SetPower(requiredPower)
                wait 80 commandBusy = false
                return
            }

            if (requiredInput && (actualPower == POWER_STATE_ON) && (requiredInput != actualInput)) {
                commandBusy = true
                SetInput(requiredInput)
                wait 10 commandBusy = false
                actualInput = requiredInput
                return
            }

            // if (iRequiredAudioMute && (actualPower == POWER_STATE_ON) && (iRequiredAudioMute != iActualAudioMute)) {
            //     commandBusy = TRUE
            //     SetMute(iRequiredAudioMute);
            //     wait 10 commandBusy = FALSE
            //     pollSequence = GET_AUDIO_MUTE;
            //     return
            // }
        }
    }
}


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    create_buffer dvPort, rxBuffer
    SetResponseHeader(id)
}

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT

data_event[dvPort] {
    online: {
        NAVCommand(data.device, "'SET BAUD 9600,N,8,1 485 DISABLE'")
        NAVCommand(data.device, "'B9MOFF'")
        NAVCommand(data.device, "'CHARD-0'")
        NAVCommand(data.device, "'CHARDM-0'")
        NAVCommand(data.device, "'HSOFF'")

        NAVTimelineStart(TL_DRIVE, driveTicks, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
    }
    string: {
        [vdvObject, DEVICE_COMMUNICATING] = true
        [vdvObject, DATA_INITIALIZED] = true

        TimeOut()

        NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'String From ', NAVConvertDPSToAscii(dvPort), '-[', data.text, ']'")
        if (!semaphore) { Process() }
    }
}


data_event[vdvObject] {
    command: {
        stack_var char cCmdHeader[NAV_MAX_CHARS]
        stack_var char cCmdParam[3][NAV_MAX_CHARS]

        NAVErrorLog(NAV_LOG_LEVEL_DEBUG, "'Command From ', NAVConvertDPSToAscii(data.device), '-[', data.text, ']'")

        cCmdHeader = DuetParseCmdHeader(data.text)
        cCmdParam[1] = DuetParseCmdParam(data.text)
        cCmdParam[2] = DuetParseCmdParam(data.text)
        cCmdParam[3] = DuetParseCmdParam(data.text)

        switch (cCmdHeader) {
            case 'PROPERTY': {
                switch (cCmdParam[1]) {
                    case 'ID': { id = atoi(cCmdParam[2]); SetResponseHeader(id) }
                }
            }
            case 'POWER': {
                switch (cCmdParam[1]) {
                    case 'ON': { requiredPower = POWER_STATE_ON; Drive() }
                    case 'OFF': { requiredPower = POWER_STATE_OFF; requiredInput = 0; Drive() }
                }
            }
            case 'VOLUME': {
                switch (cCmdParam[1]) {
                    case 'ABS': {
                        if (actualPower == POWER_STATE_ON) {
                            SetVolume(atoi(cCmdParam[2]))
                        }
                    }
                    // case 'INC': {
                    //     if(actualPower = POWER_STATE_ON) {
                    //         RampVolume(VOL_UP, 1)
                    //     }
                    // }
                    // case 'DEC': {
                    //     if(actualPower = POWER_STATE_ON) {
                    //         RampVolume(VOL_DN, 1)
                    //     }
                    // }
                    default: {
                        if (actualPower == POWER_STATE_ON) {
                            SetVolume(type_cast(NAVScaleValue(atoi(cCmdParam[1]), 255, (MAX_VOLUME - MIN_VOLUME), 0)))
                        }
                    }
                }
            }
            case 'INPUT': {
                switch (cCmdParam[1]) {
                    case 'HDMI': {
                        switch (cCmdParam[2]) {
                            case '1': { requiredPower = POWER_STATE_ON; requiredInput = INPUT_HDMI_1; Drive() }
                            case '2': { requiredPower = POWER_STATE_ON; requiredInput = INPUT_HDMI_2; Drive() }
                            // case '3': { requiredPower = POWER_STATE_ON; requiredInput = INPUT_HDMI_3; Drive() }
                            // case '4': { requiredPower = POWER_STATE_ON; requiredInput = INPUT_HDMI_4; Drive() }
                        }
                    }
                    case 'DISPLAYPORT': {
                        switch (cCmdParam[2]) {
                            case '1': { requiredPower = POWER_STATE_ON; requiredInput = INPUT_DISPLAYPORT; Drive() }
                        }
                    }
                    case 'DVI': {
                        switch (cCmdParam[2]) {
                            case '1': { requiredPower = POWER_STATE_ON; requiredInput = INPUT_DVI; Drive() }
                        }
                    }
                    case 'VGA': {
                        switch (cCmdParam[2]) {
                            case '1': { requiredPower = POWER_STATE_ON; requiredInput = INPUT_VGA; Drive() }
                            // case '2': { requiredPower = POWER_STATE_ON; requiredInput = INPUT_VGA_2; Drive() }
                            // case '3': { requiredPower = POWER_STATE_ON; requiredInput = INPUT_VGA_3; Drive() }
                        }
                    }
                    // case 'PC': {
                    //     switch(cCmdParam[2]) {
                    //         case '1': { requiredPower = POWER_STATE_ON; requiredInput = INPUT_PC_1; Drive() }
                    //         case '2': { requiredPower = POWER_STATE_ON; requiredInput = INPUT_PC_2; Drive() }
                    //         case '3': { requiredPower = POWER_STATE_ON; requiredInput = INPUT_PC_3; Drive() }
                    //     }
                    // }
                }
            }
        }
    }
}


channel_event[vdvObject, 0] {
    on: {
        switch(channel.channel) {
            case POWER: {
                if (requiredPower) {
                    switch (requiredPower) {
                        case POWER_STATE_ON: { requiredPower = POWER_STATE_OFF; requiredInput = 0; Drive() }
                        case POWER_STATE_OFF: { requiredPower = POWER_STATE_ON; Drive() }
                    }
                }
                else {
                    switch (actualPower) {
                        case POWER_STATE_ON: { requiredPower = POWER_STATE_OFF; requiredInput = 0; Drive() }
                        case POWER_STATE_OFF: { requiredPower = POWER_STATE_ON; Drive() }
                    }
                }
            }
            case PWR_ON: { requiredPower = POWER_STATE_ON; Drive() }
            case PWR_OFF: { requiredPower = POWER_STATE_OFF; requiredInput = 0; Drive() }
            // case VOL_MUTE: {
            //     if(actualPower == POWER_STATE_ON) {
            //         if(iRequiredAudioMute) {
            //             switch(iRequiredAudioMute) {
            //                 case AUDIO_MUTE_ON: { iRequiredAudioMute = AUDIO_MUTE_OFF; Drive() }
            //                 case AUDIO_MUTE_OFF: { iRequiredAudioMute = AUDIO_MUTE_ON; Drive() }
            //             }
            //             }else {
            //             switch(iActualAudioMute) {
            //                 case AUDIO_MUTE_ON: { iRequiredAudioMute = AUDIO_MUTE_OFF; Drive() }
            //                 case AUDIO_MUTE_OFF: { iRequiredAudioMute = AUDIO_MUTE_ON; Drive() }
            //             }
            //         }
            //     }
            // }
            // case VOL_UP:
            // case VOL_DN: {
            //     timeline_create(TL_VOLUME_RAMP, ltVolumeRamp, length_array(ltVolumeRamp), TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
            // }
        }
    }
    off: {
        // switch(channel.channel) {
        //     case VOL_UP:
        //     case VOL_DN: {
        //         if(timeline_active(TL_VOLUME_RAMP)) {
        //             NAVTimelineStop(TL_VOLUME_RAMP)
        //         }
        //     }
        // }
    }
}


timeline_event[TL_DRIVE] { Drive() }


// timeline_event[TL_VOLUME_RAMP] {
//     select {
//         active([vdvObject, VOL_UP]): {
//             RampVolume(VOL_UP, 5)
//         }
//         active([vdvObject, VOL_DN]): {
//             RampVolume(VOL_DN, 5)
//         }
//     }
// }


timeline_event[TL_NAV_FEEDBACK] {
    // [vdvObject, VOL_MUTE_FB] = (iActualAudioMute == AUDIO_MUTE_ON)
    [vdvObject, POWER_FB] = (actualPower == POWER_STATE_ON)
}


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)
