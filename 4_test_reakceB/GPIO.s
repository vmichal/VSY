				
        AREA GPIO_DATA, DATA, NOINIT, READWRITE
            
ButtonData
middlePressedStart SPACE 4
middlePressedCache SPACE 4
middleLastValidState SPACE 4
middlePressOccured space 4
	
rightPressedStart SPACE 4
rightPressedCache SPACE 4
rightLastValidState SPACE 4
rightPressOccured space 4 ; contains 1 when the button was pressed. Cleared by consumeRisingEdge
	
leftPressedStart SPACE 4
leftPressedCache SPACE 4
leftValidState SPACE 4
leftPressOccured space 4
    
ButtonDataEnd    

    
    


		AREA    GPIO_Driver, CODE, READONLY  	; hlavicka souboru
	
		GET		stm32f303xe.s					; vlozeni souboru s pojmenovanymi adresami
		; jsou zde definovany adresy pristupu do pameti (k registrum)

pressedStart_o EQU 0
pressedCache_o EQU 4
lastValidState_o EQU 8
pressOccurred_o EQU 12

ButtonStructSize EQU 4 * 4
; defines offsets into the button data structure
PressedStart_o EQU 0
PressedCache_o EQU 4 
LastValidState_o EQU 8

; maps signals to MCU pinout. LEDs are bound to GPIOC, buttons to GPIOB
BTN_RIGHT_PIN EQU 4
BTN_MIDDLE_PIN EQU 1
BTN_LEFT_PIN EQU 0
LED_RIGHT_PIN EQU 0
LED_LEFT_PIN EQU 1
	
BTN_RIGHT_PORT EQU GPIOA
BTN_MIDDLE_PORT EQU GPIOA
BTN_LEFT_PORT EQU GPIOA
LED_RIGHT_PORT EQU GPIOC
LED_LEFT_PORT EQU GPIOC

uartPort EQU GPIOA_BASE
uartTxPin EQU 2
uartRxPin EQU 3    
    
debounceDelay EQU 80 ; in ms

SIDE_MIDDLE EQU 0 ;there is no led for this side
SIDE_RIGHT EQU 1
SIDE_LEFT EQU 2

ButtonCount EQU 3

LedPorts
	DCD 0 ;account for one-based indexing
	DCD LED_RIGHT_PORT
	DCD LED_LEFT_PORT
	
LedPins
	DCD 0 ;account for one-based indexing
	DCD LED_RIGHT_PIN
	DCD LED_LEFT_PIN
		
ButtonPorts
    DCD BTN_MIDDLE_PORT
	DCD BTN_RIGHT_PORT
	DCD BTN_LEFT_PORT
        
ButtonPins
    DCD BTN_MIDDLE_PIN
	DCD BTN_RIGHT_PIN
	DCD BTN_LEFT_PIN

    EXPORT GPIO_INIT
    EXPORT buttonPressedFiltered
	export consumeButtonPress
	export buttonStable
    EXPORT buttonSample
	export led_write
    import GetTick
    import time_elapsed_fun
	import GetTick
        
; r0 - constant identifying LED, r1 - 1 to activate, 0 to deactivate
led_write proc
	push {r1-r3, lr}
	
	ldr r2, =LedPorts
	ldr r2, [r2, r0, LSL #2]
	ldr r3, =LedPins
	ldr r3, [r3, r0, LSL #2]
	
	tst r1, r1
	ite eq
	moveq r1, #(1 :SHL: 16) ; get one in bit 0 or 16 for GPIO_BSRR
	movne r1, #1 ;make sure there is one written in the r1
	lsl r1, r3
	
	str r1, [r2, #0x18] ;write to GPIO_BSRR
	pop {r1-r3, pc}
	endp

;********************************************
;* Function:	GPIO_INIT
;* Brief:		This procedure initializes GPIO
;* Input:		None
;* Output:		None
;********************************************
GPIO_INIT    PROC
	push {r0-r2}
	; Enable clock for the GPIOA and GPIOC port in the RCC.
	; Load the address of the RCC_AHBENR register.
	LDR R0, =RCC_AHBENR
	; Load the current value at address stored in R0 and store it in R1
	LDR R1, [R0]
	ORR R1, R1, #RCC_AHBENR_GPIOAEN :OR: RCC_AHBENR_GPIOBEN :OR: RCC_AHBENR_GPIOCEN
	
	
	STR R1, [R0]
	
	; initialize USART pins
	LDR R0, =GPIOA_MODER
	LDR R1, [R0]
	ldr r2, =(GPIO_MODER_MODER2 :OR: GPIO_MODER_MODER3)
	bic r1, r2
	ldr r2, =(GPIO_MODER_MODER2_1 :OR: GPIO_MODER_MODER3_1)
	orr r1, r2
	str r1, [r0]
	
	;activate alternate functions on USART pins
	ldr r0, =GPIOA_AFRL
	ldr r1, [r0]
	ldr r2, =(GPIO_AFRL_AFRL2 :OR: GPIO_AFRL_AFRL3)
	bic r1, r2
	ldr r2, =((7 :SHL: GPIO_AFRL_AFRL2_Pos):OR: (7 :SHL: GPIO_AFRL_AFRL3_Pos))
	orr r1, r2
	str r1, [r0]
	
	;initialize button pins
	LDR R0, =GPIOA_MODER
	LDR R1, [R0]
	ldr r2, =(GPIO_MODER_MODER0 :OR: GPIO_MODER_MODER1 :OR: GPIO_MODER_MODER4)
	bic r1, r2
	str r1, [r0]
	
	;initialize LED pins
	LDR R0, =GPIOC_MODER
	LDR R1, [R0]
	ldr r2, =(GPIO_MODER_MODER0 :OR: GPIO_MODER_MODER1)
	bic r1, r2
	ldr r2, =(GPIO_MODER_MODER0_0 :OR: GPIO_MODER_MODER1_0)
	orr r1, r2
	str r1, [r0]
	
	; activate pullup resistor on button input pins
	ldr r0, = GPIOA_PUPDR
	ldr r1, [r0]
	ldr r2, =(GPIO_PUPDR_PUPDR0 :OR: GPIO_PUPDR_PUPDR1 :OR: GPIO_PUPDR_PUPDR4)
	bic r1, r2
	ldr r2, =(GPIO_PUPDR_PUPDR0_0 :OR: GPIO_PUPDR_PUPDR1_0 :OR: GPIO_PUPDR_PUPDR4_0)
	orr r1, r2
	str r1, [r0]
	
	;initialize variables
    ldr r0, = ButtonData
	ldr r1, =ButtonDataEnd
    mov r2, #0
                
LOOP
    str r2, [r0], #4
    cmp r0, r1
    blt LOOP
	
	pop {r0-r2}
	bx lr
	endp


;**************************************************************************************************
;* Jmeno funkce		: startPressedRaw
;* Popis			: 
;* Vstup			: r0 .. constant denoting a single button
;* Vystup			: r0 .. 1 iff button is currently presseed
;**************************************************************************************************

buttonPressedRaw proc
    push {r1-r3, lr}
    ldr r2, =ButtonPorts
    ldr r3, =ButtonPins
    
    ldr r2, [r2, r0, LSL #2] ;buttons port
    ldr r3, [r3, r0, LSL #2] ; buttons pin
    ldr r0, [r2, #0x10] ;load GPIOx_IDR
    mvn r0, r0 ;pressed buttons have value 1
	mov r1, #1
	lsl r1, r3; get one in position representing the pin;
	tst r0, r1
	ite eq
	moveq r0, #0
	movne r0, #1    
    pop {r1-r3, pc}
    endp
		
;**************************************************************************************************
;* Jmeno funkce		: startPressed
;* Popis			: 
;* Vstup			: r0 .. constant denoting a single button
;* Vystup			: r0 .. 1 iff button is presseed (filtered from many previous measurements)
;**************************************************************************************************
buttonPressedFiltered								 proc
    push {r1, lr}
	ldr r1, =ButtonStructSize
	mul r1, r0
	ldr r0, =ButtonData + lastValidState_o
	ldr r0, [r1, r0]
	
    pop {r1, pc}
	endp
	
; r0 = contant identifying the button	
; clears the press flag of given button and returns the state (1 for pressed, 0 for released) in r0
consumeButtonPress proc
	push {r1, r2}
	ldr r1, =ButtonStructSize
	mul r0, r1
	ldr r1, =ButtonData + pressOccurred_o ;offset of PressEdgeOccured field
	add r1, r0; address to read from
	ldr r0, [r1]
	
	;clear the rising edge flag
	mov r2, #0
	str r2, [r1]	
	
	pop {r1, r2}
	bx lr
	endp
		  
; takes constant denoting a button in r0
; returns boolean in r0 indicating, whether the given button is stable
buttonStable proc
	push {r1-r2, lr}
	ldr r1, =ButtonData + pressedStart_o
	mov r2, #ButtonStructSize
	mul r0, r2
	ldr r0, [r1, r0] ; the time of last transition
    mov r1, #debounceDelay ;debounce delay in ms
    bl time_elapsed_fun
	pop {r1-r2, pc}
	endp		  
;**************************************************************************************************
;* Jmeno funkce		: startSample
;* Popis			: 
;* Vstup			: r0 .. constant denoting a single button
;* Vystup			: none
;**************************************************************************************************
sampleOne proc
    push {r1-r7, lr}
    mov r3, r0
		
	ldr r2, =ButtonData
	mov r1, #ButtonStructSize
	mul r1, r0
	add r1, r2 ;start of data for this button
	
	ldr r2, [r1, #pressedCache_o] ; previous state of button
	bl buttonPressedRaw
    	
    cmp r0, r2
    
    beq SAME
DIFFERENT ;if the current state differs from the previous, store the new state
    str r0, [r1, #pressedCache_o] ;stores one if the button is currently pressed
	bl GetTick
	str r0, [r1, #pressedStart_o] ;store the current time as the start time for press
    
    pop {r1-r7, pc}

SAME ; if the state has been stable for long enough, save it
	ldr r4, [r1, #lastValidState_o]
	cmp r0, r4
	beq RETURN_FROM_SAMPLE ; return early if the button has already been marked as stable

	mov r4, r0
	mov r0, r3
	bl buttonStable
    
    tst r0, r0
    ; if r0 != 0 then the button has been stable for a while. Otherwise return the other option
    beq RETURN_FROM_SAMPLE ; return iff the button has not been stable
	
	B SKIP_DEBUG
	import print_string
	import print_char
	import print_header
	import get_side_name


strPressed
	DCB " pressed.\r\n", 0
strReleased
	DCB " released.\r\n", 0
	ALIGN
SKIP_DEBUG
	bl print_header
	mov r0, r3
	bl get_side_name
	bl print_string
	
	tst r4, r4
	ldrne r0, =strPressed
	ldreq r0, =strReleased
	bl print_string

    str r4, [r1, #lastValidState_o] ; store the current button state to lastValidState
	tst r4, r4
	beq RETURN_FROM_SAMPLE ;return when the button is not pressed anymore
	
	; if r4 is true (button is pressed) and we are here (value is different)
	; that means we have an edge -> button has just been pressed
	mov r0, #1
	str r0, [r1, #pressOccurred_o] ; set the press occured flag
RETURN_FROM_SAMPLE
    pop {r1-r7, pc}; return
	endp


		
buttonSample proc
    push {r0-r1, lr}
    mov r1, #0
NEXT_BUTTON
	mov r0, r1
    bl sampleOne
    
    add r1, #1
    cmp r1, #ButtonCount
    bne NEXT_BUTTON
    
    pop {r0-r1, pc}
    endp

	ALIGN
				END	
