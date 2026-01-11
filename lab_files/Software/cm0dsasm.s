        PRESERVE8
        THUMB

;============================================================
; Vector table
;============================================================
        AREA    RESET, DATA, READONLY
        EXPORT  __Vectors

__Vectors
        DCD     0x00003FFC          ; initial SP
        DCD     Reset_Handler       ; reset
        DCD     0
        DCD     0
        DCD     0,0,0,0,0,0,0,0,0,0,0,0

        ; External IRQs (IRQ0..)
        DCD     Timer_Handler       ; IRQ0 = TIMER
        DCD     Default_Handler     ; IRQ1 = UART (ignored)
        DCD     0,0,0,0,0,0,0,0,0,0,0,0,0,0

;============================================================
; Code
;============================================================
        AREA    |.text|, CODE, READONLY

;============================================================
; Peripheral base addresses / offsets
;============================================================

; LCD
LCD_BASE            EQU     0x50000000
LCD_CTRL_OFFS       EQU     0x00
LCD_STATUS_OFFS     EQU     0x04
LCD_RAM_OFFS        EQU     0x10

; GPIO
GPIO_BASE           EQU     0x53000000
GPIO_DATA_OFFS      EQU     0x00
GPIO_DIR_OFFS       EQU     0x04

; TIMER
TIMER_BASE          EQU     0x52000000
TIMER_LD_OFFS       EQU     0x00
TIMER_VAL_OFFS      EQU     0x04
TIMER_CTL_OFFS      EQU     0x08
TIMER_CLR_OFFS      EQU     0x0C

; NVIC
NVIC_ISER0          EQU     0xE000E100
NVIC_ICPR0          EQU     0xE000E280

;============================================================
; MODE values
;============================================================
MODE_OFF            EQU     0
MODE_ON             EQU     1
MODE_UP             EQU     2
MODE_DOWN           EQU     3

TIMER_LOAD_1S       EQU     3125000

;============================================================
; State registers
; R4 = prev_sw
; R5 = led latch
; R6 = mode
; R7 = counter
; R8 = resume_flag (1=resume from R7 for SW2/SW3, 0=start fresh)
;============================================================

Reset_Handler PROC
        EXPORT  Reset_Handler
        ENTRY

        CPSID   i

        ; Enable TIMER IRQ0
        LDR     R0, =NVIC_ICPR0
        MOVS    R1, #1
        STR     R1, [R0]
        LDR     R0, =NVIC_ISER0
        STR     R1, [R0]

        ; GPIO DIR: LED[3:0]
        LDR     R0, =GPIO_BASE
        MOVS    R1, #0x0F
        STR     R1, [R0, #GPIO_DIR_OFFS]

        ; LEDs off
        MOVS    R5, #0
        STR     R5, [R0, #GPIO_DATA_OFFS]

        ; init state
        MOVS    R4, #0
        MOVS    R6, #MODE_OFF
        MOVS    R7, #0
        MOVS    R0, #0
        MOV     R8, R0               ; resume_flag = 0

        BL      Timer_Stop

        ; LCD OFF
        LDR     R1, =MsgOff1
        LDR     R2, =MsgOff2
        BL      LCD_Show_2Lines

        CPSIE   i

Main_Loop
        BL      Poll_Buttons

        ; output LED latch
        LDR     R0, =GPIO_BASE
        STR     R5, [R0, #GPIO_DATA_OFFS]

        B       Main_Loop
        ENDP


;============================================================
; Poll_Buttons
; Priority: SW0 > SW1 > SW2 > SW3
;============================================================
Poll_Buttons PROC
        PUSH    {R0-R3, LR}

        LDR     R0, =GPIO_BASE
        LDR     R1, [R0, #GPIO_DATA_OFFS]
        MOVS    R2, #0x0F
        ANDS    R1, R2						; sw = SW[3:0]

        ; rising edge
        MOV     R2, R1
        EORS    R2, R4
        ANDS    R2, R1						; pressed = (sw ^ prev_sw) & sw
        MOV     R4, R1						; prev_sw = sw

        CMP     R2, #0
        BEQ     PB_Done

        ; SW0
        MOVS    R3, #0x01
        TST     R2, R3
        BNE     PB_SW0

        ; SW1
        MOVS    R3, #0x02
        TST     R2, R3
        BNE     PB_SW1

        ; SW2
        MOVS    R3, #0x04
        TST     R2, R3
        BNE     PB_SW2

        ; SW3
        MOVS    R3, #0x08
        TST     R2, R3
        BNE     PB_SW3

        B       PB_Done

; SW0: OFF/RESET, stop timer, keep R7, allow resume
PB_SW0
        MOVS    R5, #0x01
        BL      Timer_Stop
        MOVS    R6, #MODE_OFF
        MOVS    R0, #1
        MOV     R8, R0               ; resume next time

        LDR     R1, =MsgOff1
        LDR     R2, =MsgOff2
        BL      LCD_Show_2Lines
        BL      Delay_Short
        B       PB_Done

; SW1: ON/START, stop timer, keep R7, allow resume
PB_SW1
        MOVS    R5, #0x02
        BL      Timer_Stop
        MOVS    R6, #MODE_ON
        MOVS    R0, #1
        MOV     R8, R0               ; resume next time

        LDR     R1, =MsgOn1
        LDR     R2, =MsgOn2
        BL      LCD_Show_2Lines
        BL      Delay_Short
        B       PB_Done

; SW2: COUNT UP one-shot, resume if resume_flag=1 else start at 0
PB_SW2
        MOVS    R5, #0x04
        MOVS    R6, #MODE_UP

        MOVS    R0, #0
        CMP     R8, R0
        BNE     PB_SW2_Keep
        MOVS    R7, #0
PB_SW2_Keep
        MOVS    R0, #0
        MOV     R8, R0               ; in counting mode => no resume flag

        MOV     R0, R7
        LDR     R1, =CountUpLine1
        BL      LCD_Show_CountX

        LDR     R0, =TIMER_LOAD_1S
        BL      Timer_Start

        BL      Delay_Short
        B       PB_Done

; SW3: COUNT DOWN one-shot, resume if resume_flag=1 else start at 9
PB_SW3
        MOVS    R5, #0x08
        MOVS    R6, #MODE_DOWN

        MOVS    R0, #0
        CMP     R8, R0
        BNE     PB_SW3_Keep
        MOVS    R7, #9
PB_SW3_Keep
        MOVS    R0, #0
        MOV     R8, R0

        MOV     R0, R7
        LDR     R1, =CountDownLine1
        BL      LCD_Show_CountX

        LDR     R0, =TIMER_LOAD_1S
        BL      Timer_Start

        BL      Delay_Short

PB_Done
        POP     {R0-R3, PC}
        ENDP


;============================================================
; Timer control
;============================================================
Timer_Start PROC
        PUSH    {R1-R2, LR}
        LDR     R1, =TIMER_BASE

        MOVS    R2, #0
        STR     R2, [R1, #TIMER_CTL_OFFS]

        MOVS    R2, #1
        STR     R2, [R1, #TIMER_CLR_OFFS]
        MOVS    R2, #0
        STR     R2, [R1, #TIMER_CLR_OFFS]

        STR     R0, [R1, #TIMER_LD_OFFS]

        MOVS    R2, #7
        STR     R2, [R1, #TIMER_CTL_OFFS]

        POP     {R1-R2, PC}
        ENDP

Timer_Stop PROC
        PUSH    {R1-R2, LR}
        LDR     R1, =TIMER_BASE

        MOVS    R2, #0
        STR     R2, [R1, #TIMER_CTL_OFFS]

        MOVS    R2, #1
        STR     R2, [R1, #TIMER_CLR_OFFS]
        MOVS    R2, #0
        STR     R2, [R1, #TIMER_CLR_OFFS]

        POP     {R1-R2, PC}
        ENDP

Timer_ClearIRQ PROC
        PUSH    {R1-R2, LR}
        LDR     R1, =TIMER_BASE
        MOVS    R2, #1
        STR     R2, [R1, #TIMER_CLR_OFFS]
        MOVS    R2, #0
        STR     R2, [R1, #TIMER_CLR_OFFS]
        POP     {R1-R2, PC}
        ENDP


;============================================================
; Timer IRQ handler (one-shot)
;============================================================
Timer_Handler PROC
        EXPORT  Timer_Handler

        PUSH    {R0-R3, LR}

        BL      Timer_ClearIRQ

        CMP     R6, #MODE_UP
        BEQ     TH_Up
        CMP     R6, #MODE_DOWN
        BEQ     TH_Down
        B       TH_Exit

TH_Up
        CMP     R7, #9
        BEQ     TH_Finish
        ADDS    R7, R7, #1
        B       TH_Show

TH_Down
        CMP     R7, #0
        BEQ     TH_Finish
        SUBS    R7, R7, #1
        B       TH_Show

TH_Show
        MOV     R0, R7
        CMP     R6, #MODE_UP
        BEQ     TH_LineUp
        LDR     R1, =CountDownLine1
        B       TH_DoShow
TH_LineUp
        LDR     R1, =CountUpLine1
TH_DoShow
        BL      LCD_Show_CountX
        B       TH_Exit

TH_Finish
        BL      Timer_Stop
        MOVS    R6, #MODE_ON
        MOVS    R5, #0x02

        MOVS    R0, #0
        MOV     R8, R0               ; after finish => start fresh next time

        LDR     R1, =MsgOn1
        LDR     R2, =MsgOn2
        BL      LCD_Show_2Lines

TH_Exit
        POP     {R0-R3, PC}
        ENDP


Default_Handler PROC
        EXPORT  Default_Handler
        BX      LR
        ENDP


;============================================================
; LCD helpers
;============================================================
LCD_Show_CountX PROC
        PUSH    {R2-R7, LR}

        MOVS    R2, #'0'
        ADDS    R0, R2

        BL      LCD_WaitReady

        ; line1
        LDR     R3, =LCD_BASE
        ADDS    R3, #LCD_RAM_OFFS
        MOVS    R4, #16
LCX1
        LDRB    R5, [R1]
        STRB    R5, [R3]
        ADDS    R1, #1
        ADDS    R3, #1
        SUBS    R4, R4, #1
        BNE     LCX1

        ; line2
        LDR     R2, =CountLine2Template
        LDR     R3, =LCD_BASE
        ADDS    R3, #LCD_RAM_OFFS
        ADDS    R3, #16
        MOVS    R4, #16
        MOVS    R6, #0
LCX2
        LDRB    R5, [R2]
        MOVS    R7, #7
        CMP     R6, R7
        BNE     LCX2_Store
        MOV     R5, R0
LCX2_Store
        STRB    R5, [R3]
        ADDS    R2, #1
        ADDS    R3, #1
        ADDS    R6, #1
        SUBS    R4, R4, #1
        BNE     LCX2

        ; start
        LDR     R3, =LCD_BASE
        MOVS    R1, #1
        STR     R1, [R3, #LCD_CTRL_OFFS]

        BL      LCD_WaitReady

        POP     {R2-R7, PC}
        ENDP


LCD_Show_2Lines PROC
        PUSH    {R4-R7, LR}

        BL      LCD_WaitReady

        ; line1
        LDR     R0, =LCD_BASE
        ADDS    R0, #LCD_RAM_OFFS
        MOVS    R3, #16
LCD_Copy1
        LDRB    R4, [R1]
        STRB    R4, [R0]
        ADDS    R1, #1
        ADDS    R0, #1
        SUBS    R3, R3, #1
        BNE     LCD_Copy1

        ; line2
        LDR     R0, =LCD_BASE
        ADDS    R0, #LCD_RAM_OFFS
        ADDS    R0, #16
        MOVS    R3, #16
LCD_Copy2
        LDRB    R4, [R2]
        STRB    R4, [R0]
        ADDS    R2, #1
        ADDS    R0, #1
        SUBS    R3, R3, #1
        BNE     LCD_Copy2

        ; start
        LDR     R0, =LCD_BASE
        MOVS    R1, #1
        STR     R1, [R0, #LCD_CTRL_OFFS]

        BL      LCD_WaitReady

        POP     {R4-R7, PC}
        ENDP


LCD_WaitReady PROC
        PUSH    {R0-R2, LR}
LCD_WaitLoop
        LDR     R0, =LCD_BASE
        LDR     R1, [R0, #LCD_STATUS_OFFS]
        MOVS    R2, #1
        ANDS    R1, R2
        BNE     LCD_WaitLoop
        POP     {R0-R2, PC}
        ENDP


Delay_Short PROC
        PUSH    {R0, LR}
        MOVS    R0, #0xFF
DS1
        SUBS    R0, R0, #1
        BNE     DS1
        POP     {R0, PC}
        ENDP


;============================================================
; Strings (DATA area ONLY)
;============================================================
        AREA    MyData, DATA, READONLY

MsgOff1  DCB     "SYSTEM OFF      "
MsgOff2  DCB     "                "

MsgOn1   DCB     "SYSTEM ON       "
MsgOn2   DCB     "HELLO USER      "

CountUpLine1        DCB "MODE2 COUNT UP  "
CountDownLine1      DCB "MODE3 COUNT DOWN"

CountLine2Template  DCB "COUNT: 0        "

        ALIGN   4
        END


