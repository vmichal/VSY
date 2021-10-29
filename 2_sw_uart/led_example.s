; Vojtech Michal (michavo3), developed for VSY 2021, homework "SW-UART".
; for pinout overview and general documentation, please see the folder "dokumentace"
; containing detailed overview including graphs from logic analyzer.
	area mojedata, data, noinit, readwrite
	
	; stores the number of systick interrupts since system start
systemTicks space 4
bitToSend space 4
delayRemaining space 4
bitSegment space 4
	
	
	area STM32F3xx, code, readonly
	get stm32f303xe.s

	;start bit, first ASCII code and stop bit. Then again start bit, second letter and stop bit
uart_message EQU 0 :OR: ('V' :SHL: 1) :OR: (1 :SHL: 9) :OR: ('M' :SHL: 11) :OR: (1 :SHL:19)
uart_message_length EQU 2*8 + 2 + 2
bit_segments_count EQU 4
message_delay EQU uart_message_length * 2 * bit_segments_count


UART_PIN EQU 1 :SHL: 5
SYNC_PIN EQU 1 :SHL: 6
	export __main
;	export SystemInit
	export __use_two_region_memory
		
__use_two_region_memory
__main

	ENTRY
MAIN
	; zero out the data section
	mov r0, #0
	ldr r1, =bitToSend
	str r0, [r1]
	ldr r1, =delayRemaining
	str r0, [r1]
	ldr r1, =bitSegment 
	str r0, [r1]
	
	; Initialize the GPIO
	BL GPIO_INIT
	; make systick generate an interrupt every 26 us (that is baudrate 9600 after division by four)
	ldr r0, =26;
	bl SYSTICK_INIT
		
LOOP
	B LOOP;

systick_hook proc
	push {r0-r3, lr}
	ldr r0, =delayRemaining
	ldr r1, [r0]
	tst r1, r1
	beq NO_NEED_TO_WAIT 
	; we need to wait before we send the next bit...
	sub r1, #1
	str r1, [r0]
	b RETURN_FROM_HOOK	
NO_NEED_TO_WAIT
	ldr r0, =bitToSend
	ldr r0, [r0]
	cmp r0, #uart_message_length
	beq MESSAGE_FINISHED
	
	; check the bit segment
	ldr r0, =bitSegment
	ldr r2, [r0]
	add r1, r2, #1 ;increment the bit segment counter
	and r1, #3
	str r1, [r0]
	
	tst r2, r2
	beq SEND_BIT
	cmp r2, #2
	beq RAISE_SYNC
	bgt CLEAR_SYNC
	B RETURN_FROM_HOOK
	
RAISE_SYNC
	ldr r0, =GPIOA_BSRR
	ldr r1, =SYNC_PIN
	str r1, [r0]
	B RETURN_FROM_HOOK
CLEAR_SYNC
	ldr r0, =GPIOA_BRR
	ldr r1, =SYNC_PIN
	str r1, [r0]
	
	; advance the bit pointer
	ldr r0, =bitToSend
	ldr r1, [r0]
	add r1, #1
	str r1, [r0]

	B RETURN_FROM_HOOK	
SEND_BIT
	ldr r3,	=UART_PIN ;r3 = index of set bit for output pin in the GPIO_BSRR
	ldr r0, =bitToSend
	ldr r0, [r0] ;load the bit index
	
	mov r2, #1
	lsl r2, r0 ; bitmask representing the bit of message to send next
	ldr r0, =uart_message
	tst r0, r2 ; is the bit to send set or not? If not, clear the output instead of setting
	it eq
	lsleq r3, #16 ; use bit reset field in GPIOx_BSRR instead of bit set
	;now set or reset the output pin
	ldr r0, =GPIOA_BSRR
	str r3, [r0]

	
	b RETURN_FROM_HOOK
MESSAGE_FINISHED
	;restore the variables so that we can start waiting again
	ldr r0, =bitToSend
	mov r1, #0
	str r1, [r0];clear the bit index
	ldr r0, =delayRemaining
	ldr r1, =message_delay
	str r1, [r0];start delay	
	;the output pin is already high thanks to stop bit.
RETURN_FROM_HOOK
	pop {r0-r3, pc}	
	endp

;********************************************
;* Function:	WAIT
;* Brief:		This procedure waits 
;* Input:		None
;* Output:		None
;********************************************

blocking_wait_ms proc
	; takes one argument in r0 - the number of ms to wait
	push {r1,r2, r3, lr}
	ldr r1, =systemTicks
	ldr r3, [r1] ;time when we started waiting
WAITING_LOOP
	ldr r2, [r1]
	sub r2, r3
	cmp r2, r0
	; by comparing for <= instead of <, 1 ms of waiting is added.
	; this is necessary since the systick period could occur at any moment...
	ble WAITING_LOOP
	
	pop {r1, r2, r3, pc}
	
	endp
		
SYSTICK_INIT PROC
	; takes a single argument - interrupt period in us in r0
	push {r1, r2, lr}
	; assume the AHB is running at 8 MHz (RC oscillator)
	lsl r0, #3 ; multiply the frequency by 8 to convert from us to cpu cycles
	ldr r1, =STK_LOAD
	str r0, [r1]
	ldr r1, =STK_CTRL
	ldr r2, [r1]
	; enable the systick, clock it from AHB and enable interrupt
	orr r2, #(STK_CTRL_ENABLE :OR: STK_CTRL_TICKINT :OR: STK_CTRL_CLKSOURCE)
	str r2, [r1]
	
	pop {r1, r2, pc}
	
	ENDP
		
SysTick_Handler PROC
	export SysTick_Handler
	; increment value systemTicks stored in memory by one
	push {r1, r2, lr}
	
	ldr r1, =systemTicks
	ldr r2, [r1]
	add r2, #1
	str r2, [r1]	
	bl systick_hook
	
	pop {r1, r2, pc}
	bx lr
	ENDP
	
;********************************************
;* Function:	GPIO_INIT
;* Brief:		This procedure initializes GPIO
;* Input:		None
;* Output:		None
;********************************************
GPIO_INIT    PROC
	; Enable clock for the GPIOA and GPIOC port in the RCC.
	; Load the address of the RCC_AHBENR register.
	LDR R0, =RCC_AHBENR
	; Load the current value at address stored in R0 and store it in R1
	LDR R1, [R0]
	; Set the bit which enables the GPIOA clock by using OR (non destructive
	; operation in view of other bits).
	ORR R1, R1, #RCC_AHBENR_GPIOAEN
	; povoleni hodin pro GPIO:A a GPIO_C v registru RCC_AHBENR
	
	STR R1, [R0]
	
	; Configure the PA2 pin as the output
	LDR R0, =GPIOA_MODER
	LDR R1, [R0]
	; Mask the MODER group of bits which belongs to the pin 2. It is in case
	; there was a different value written in these bits, eg. "01" -> "10" so we
	; need to clear them first and then write them using binary OR. This is not
	; needed in case of configuration after reset, when these bits are all set
	; to 0, but it is needed during reconfiguration at runtime. At the system
	; reset most of the pins are configured as inputs.
	BIC R1, R1, #GPIO_MODER_MODER5 :OR: GPIO_MODER_MODER6    ; This clears the group of bits MODER5 and 6
	ORR R1, R1, #GPIO_MODER_MODER5_0 :OR: GPIO_MODER_MODER6_0  ; The final value is "01" at MODER5 and 6

	; Now the pins PA5, PA6 is configured as the general purpose output. The new value
	; to be stored back to the GPIOA_MODER register is 0xA8000020.
	STR R1, [R0]
	
	BX LR
	ENDP
	
;********************************************
;* Function:	SystemInit
;* Brief:		System initialization procedure. This function is implicitly
;*				generated by IDEs when creating new C project. It can be thrown
;*				away or the clock, GPIO, etc. configuration can be put here.
;* Input:		None
;* Output:		None
;********************************************
;SystemInit
;
;	BX LR

	ALIGN
	
	END