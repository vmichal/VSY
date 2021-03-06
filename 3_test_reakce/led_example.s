; Vojtech Michal (michavo3), developed for VSY 2021, homework "Tester A".
; for pinout overview and general documentation, please see the folder "dokumentace"
; containing detailed overview of the application's usage

; The code relies heavily on macros implemented by ARM assembler.
; This way it is possible to focus on the problem at hand instead
; of losing track because of the assembler boilerplate.
; see https://developer.arm.com/documentation/dui0489/g/directives-reference/assembly-control-directives/macro-and-mend for macro documentation
	
	area mojedata, data, noinit, readwrite
	
; stores the number of systick interrupts since system start
systemTicks space 4
; stores the timestamp of last state machine transition (used for precise state machine timings)
lastTransition space 4
; stores the index of current state. Shall only contain values of STATE_* listed below
currentState space 4
; time of last LED update (used to track LED blinking period etc)
last_led_update space 4
; time of last edge on button input (used to debounce the button)
last_button_update space 4
; current button state - 1 when pressed, 0 otherwise 
button_value space 4
; boolean value indicating whether the button has been released since entering BAD_REACTION state.
; without this special handling, if the user held the button for too long (did not manage to react to LED turning off),
; then the test would immediatelly restart, since the requirement of >1 s hold would be met.
; Therefore, when the user fails the test, we do not allow a transition to new test, unless he releases the button.
seen_released_button space 4
; the length of this test in ms. Shall only contain values in range [test_length_min, test_length_max]
test_length space 4
	
	area STM32F3xx, code, readonly
	get stm32f303xe.s
		
; MACROS

; 1) macros for function call with literal arguments (not registers, only values defined by 'EQU')
	
	;invokes a zero argument function
	macro
	call0 $fun
	bl $fun
	mend
	
	;invokes a single argument function with literal argument supplied in r0
	macro
	call1 $fun, $arg_a
	ldr r0, =$arg_a
	bl $fun
	mend
	
	;invokes a two argument function with literal arguments supplied in r0 and r1
	macro
	call2 $fun, $arg_a, $arg_b
	ldr r0, =$arg_a
	ldr r1, =$arg_b
	bl $fun
	mend	
	
	;invokes a three argument function with literal argument supplied in r0, r1 and r2
	macro
	call3 $fun, $arg_a, $arg_b, $arg_c
	ldr r0, =$arg_a
	ldr r1, =$arg_b
	ldr r2, =$arg_c
	bl $fun
	mend	
		
;2) Memory manipulation macros
	
	; load from given address into given register (second arg)
	macro
	load_address $address, $reg
	ldr $reg, =$address
	ldr $reg, [$reg]	
	mend
	
	; store the content of register given by second argument into memory location 'address'
	macro
	store_address $address, $reg
	push {r7}
	ldr r7, =$address
	str $reg, [r7]	
	pop {r7}	
	mend
	
	; toggle bits specified by mask 'bits' in value stored at memory location 'address'
	macro
	toggle_bits $address, $bits
	push {r6, r7}
	ldr r6, =$address
	ldr r7, [r6]
	eor r7, $bits
	str r7, [r6]
	pop {r6, r7}
	mend
	
	; load from memory, add value (used as immediate in add instruction, so it must be small) and store value back
	macro
	increment_memory $address, $value
	push {r0, r1}
	ldr r0, =$address
	ldr r1, [r0]
	add r1, $value
	str r1, [r0]
	pop {r0, r1}
	mend
	
	; test 'reg', if it is not zero, jump to 'branch'
	macro
	if_true $reg, $branch
	tst $reg, $reg
	bne $branch
	mend
	
	; test 'reg', if it is zero, jump to 'branch'
	macro
	if_false $reg, $branch
	tst $reg, $reg
	beq $branch
	mend
	
	; loads given timestamp into memory and tests, whether given ammount of time has elapsed.
	; result is stored in r0 as usual
	macro
	time_elapsed $start, $time
	load_address $start, r0
	ldr r1, =$time
	bl time_elapsed_fun
	mend
	
	; executes comparison of second and last argument and evaluates, whether the conditional suffix is fulfilled.
	; Stores 0 in destination if the comparison failed, one otherwise.
	macro
	compare$cond $destination, $lhs, $rhs
	cmp $lhs, $rhs
	mov $destination, #0
	it $cond
	mov$cond $destination, #1	
	mend
	
	; Stores 0 in destination iff 'lhs' and 'rhs' share no set bits. Stores one otherwise.
	macro
	test_bits $destination, $lhs, $rhs
	tst $lhs, $rhs
	mov $destination, #0
	it ne
	movne $destination, #1		
	mend
	
	; simplifies testing, whether some specified ammount of time has elapsed since the last state machine transition
	macro
	time_elapsed_since_transition $time
	time_elapsed lastTransition, $time
	mend
	
	; stores zero into the specified address
	macro
	zero_address $destination
	push {r0}
	mov r0, #0
	store_address $destination, r0
	pop {r0}
	mend
	
	; copies value stored in memory at address 'source' to address 'destination'
	macro
	copy $source, $destination
	push {r0,r1}
	ldr r0, =$source
	ldr r0, [r0]
	ldr r1, =$destination
	str r0, [r1]
	pop {r0,r1}
	mend

;enumeration of possible state machine states
STATE_PREPARATION EQU 0
STATE_TEST_START EQU 1
STATE_WAITING_FOR_REACTION EQU 2
STATE_REACTION_GOOD EQU 3
STATE_REACTION_BAD EQU 4

; fixed timing of the state machine
preparationLength EQU 15000 ; in ms
bad_reaction_led_period EQU 150
good_reaction_led_period EQU 600
; two options for button press - either short (enough to signal that the user is prepared) or long (needed to reset the state machine)
long_press EQU 1000
short_press EQU 50
; bounds for pseudorandomly generated test length
test_length_min EQU 400
test_length_max EQU 10000
;the length of interval during which the user must react to deactivated LED
max_delay EQU 600
	
; make systick generate an interrupt every 1 ms
systick_freq EQU 1000

; maps signals to MCU pinout. LEDs are bound to GPIOA, button to GPIOC
ERR_LED_PIN EQU 0 
CONTROL_LED_PIN EQU 1
GOOD_LED_PIN EQU 4
FALLBACK_LED_PIN EQU 5 ;located on board, used when the user does not want to connect more LEDs.

BUTTON_PIN EQU 13
; button is connected to PC13



	export __main
;	export SystemInit
	export __use_two_region_memory
		
__use_two_region_memory
__main

	ENTRY
MAIN
	; zero out the data section
	zero_address systemTicks
	; Initialize the GPIO
	BL GPIO_INIT
	
	call1 SYSTICK_INIT, systick_freq

	bl initialize_fsm

ENDLESS_LOOP
	bl fsm_tick
	b ENDLESS_LOOP
		
; one tick of the state machine logic.
; reads inputs, transitions between states etc
fsm_tick proc
	push {r0-r3, lr}
	bl sample_button
	load_address currentState, r0
	ldr r1, =FSM_CASE_TABLE
	tbh [r1, r0, lsl #1]
FSM_HANDLE_PREP
	time_elapsed lastTransition, preparationLength
	if_true r0, INCORRECT_REACTION
	bl is_button_pressed
	if_false r0, RETURN_FROM_TICK ; the button is not pressed, the user is not ready yet
	call1 button_stable_for, short_press
	if_false r0, RETURN_FROM_TICK ;the button is pressed, but not yet stable
	; the button is stable and pressed -> start the test
	bl calculate_test_length
	store_address test_length, r0
	call1 fsm_transition, STATE_TEST_START
	B RETURN_FROM_TICK
FSM_HANDLE_TEST_START
	load_address test_length, r1
	load_address lastTransition, r0
	bl time_elapsed_fun
	if_true r0, START_WAITING
	bl is_button_pressed
	if_true r0, RETURN_FROM_TICK ; button is still pressed, no change 
	; button is not pressed anymore. Debounce it
	call1 button_stable_for, short_press
	if_false r0, RETURN_FROM_TICK ; not yet stable (still bouncing)
	; the button has been released too early -> error
	b INCORRECT_REACTION
FSM_HANDLE_WAITING_FOR_REACTION
	time_elapsed lastTransition, max_delay
	if_true r0, INCORRECT_REACTION
	;the user still has time to react
	bl is_button_pressed
	if_true r0, RETURN_FROM_TICK ;the button is still pressed, no big deal
	; the button has been released!
	call1 button_stable_for, short_press
	if_false r0, RETURN_FROM_TICK ;not yet stable
	; the button is stable! The user did it correctly!
	call1 fsm_transition, STATE_REACTION_GOOD
	B RETURN_FROM_TICK
FSM_HANDLE_REACTION_GOOD
	time_elapsed last_led_update, good_reaction_led_period
	if_false r0, CHECK_FSM_RESET
	toggle_bits GPIOA_ODR, #(1 :SHL: GOOD_LED_PIN) :OR: (1 :SHL: FALLBACK_LED_PIN) ; toggle the GOOD_LED
	copy systemTicks, last_led_update
	B CHECK_FSM_RESET
FSM_HANDLE_REACTION_BAD
	time_elapsed last_led_update, bad_reaction_led_period
	if_false r0, CHECK_FSM_RESET
	toggle_bits GPIOA_ODR, #(1 :SHL: ERR_LED_PIN) :OR: (1 :SHL: FALLBACK_LED_PIN) ; toggle the ERR_LED
	copy systemTicks, last_led_update
	b CHECK_FSM_RESET
INCORRECT_REACTION
	ldr r0, =(1 :SHL: CONTROL_LED_PIN) :OR: (1 :SHL: FALLBACK_LED_PIN)
	store_address GPIOA_BRR, r0
	call1 fsm_transition, STATE_REACTION_BAD
	B RETURN_FROM_TICK
BUTTON_RELEASED
	mov r1, #1
	store_address seen_released_button, r1
RETURN_FROM_TICK
	pop {r0-r3, pc}	
START_WAITING
	ldr r1, =(1 :SHL: CONTROL_LED_PIN) :OR: (1 :SHL: FALLBACK_LED_PIN)
	store_address GPIOA_BRR, r1 ; turn off control LED (the user shall respond now!)	
	call1 fsm_transition, STATE_WAITING_FOR_REACTION
	B RETURN_FROM_TICK

CHECK_FSM_RESET
	load_address button_value, r0
	if_false r0, BUTTON_RELEASED ; return if the button is not pressed
	load_address seen_released_button, r0
	if_false r0, RETURN_FROM_TICK ; the button has not been released yet. Ignore it.
	call1 button_stable_for, long_press
	if_false r0, RETURN_FROM_TICK 
	;if the button has been pressed for long time, reinitialize the FSM
	bl initialize_fsm
	b RETURN_FROM_TICK

	


	endp
		
	ALIGN
		
FSM_CASE_TABLE
	DCW (FSM_HANDLE_PREP - FSM_HANDLE_PREP)/2
	DCW (FSM_HANDLE_TEST_START - FSM_HANDLE_PREP)/2
	DCW (FSM_HANDLE_WAITING_FOR_REACTION - FSM_HANDLE_PREP)/2
	DCW (FSM_HANDLE_REACTION_GOOD - FSM_HANDLE_PREP)/2
	DCW (FSM_HANDLE_REACTION_BAD - FSM_HANDLE_PREP)/2
	
	ALIGN
	
initialize_fsm proc
	push {lr}
	zero_address last_led_update
	zero_address button_value
	zero_address last_button_update
	zero_address seen_released_button
	zero_address test_length
	call1 fsm_transition, STATE_PREPARATION
	ldr r1, =(1 :SHL: CONTROL_LED_PIN) :OR: (1 :SHL: FALLBACK_LED_PIN) :OR: (1 :SHL: (ERR_LED_PIN + 16)) :OR: (1 :SHL: (GOOD_LED_PIN + 16))
	store_address GPIOA_BSRR, r1 ; turn the control LED on (the user shall get prepared!) and deactivate other ones
	pop {pc}
	endp
	
;calculate the test length for the next test	
calculate_test_length proc
	push {r1, r2}
	;does not work, because the loop appears to be somehow synchronized with systick period...
	;load_address STK_VAL, r0 ; take the current value of systick counter 
	load_address systemTicks, r0
	ldr r1, =(test_length_max - test_length_min) ; prepare the range of possible test lengths and calculate modulo
	; r0 = r0 % r1
	udiv r2, r0, r1
	mul r2, r1
	sub r0, r2; r0 = systemTicks % (test_length_max - test_length_min)
	; for the other solution with systick
	;load_address STK_LOAD, r1
	;udiv r0, r1 ; r0 = STK_VAL / STK_LOAD * (test_length_max - test_length_min) + lest_length_min
	;return STK_VAL / STK_LOAD * (test_length_max - test_length_min) + lest_length_min
	ldr r1, =test_length_min
	add r0, r1		
	pop {r1, r2}
	bx lr
	endp
	
; takes a single argument in r0 - enumerator representing the nest state
; transitions the state machine to the next state, keeping record of the transition time
fsm_transition proc
	store_address currentState, r0
	copy systemTicks, lastTransition
	bx lr
	endp
		
; return zero in r0 iff the butotn is released, 1 if pressed
is_button_pressed proc
	load_address GPIOC_IDR, r0
	mvn r0, r0
	test_bits r0, r0, #(1 :SHL: BUTTON_PIN)
	
	bx lr
	endp
		
sample_button proc
	push {r0, r2, lr}
	bl is_button_pressed
	load_address button_value, r2
	cmp r0, r2
	beq BUTTON_SAME
	store_address button_value, r0
	copy systemTicks, last_button_update
BUTTON_SAME
	pop {r0, r2, pc}	
	endp
		
; returns 1 on r0 iff the button has been stable for given time
button_stable_for proc
	push {r1, lr}
	mov r1, r0
	load_address last_button_update, r0
	bl time_elapsed_fun
	pop {r1, pc}
	endp

systick_hook proc
	increment_memory systemTicks, #1
	bx lr	
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
		
; takes two arguments in r0, the starting timestamp
; and r1, the number of ms that should have elapsed
; returns in r0: non-zero value if the time elapsed, zero otherwise
time_elapsed_fun proc
	push {r2}
	load_address systemTicks, r2
	sub r2, r0
	comparege r0, r2, r1
	pop {r2}
	bx lr
	endp
		
SYSTICK_INIT PROC
	; takes a single argument - interrupt period in us in r0
	push {r2, lr}
	; assume the AHB is running at 8 MHz (RC oscillator)
	lsl r0, #3 ; multiply the frequency by 8 to convert from us to cpu cycles
	store_address STK_LOAD, r0
	load_address STK_CTRL, r2
	; enable the systick, clock it from AHB and enable interrupt
	orr r2, #(STK_CTRL_ENABLE :OR: STK_CTRL_TICKINT :OR: STK_CTRL_CLKSOURCE)
	store_address STK_CTRL, r2
	
	pop {r2, pc}
	
	ENDP
		
SysTick_Handler PROC
	export SysTick_Handler
	; increment value systemTicks stored in memory by one
	push {lr}
	increment_memory systemTicks, #1
	bl systick_hook
	
	pop {pc}
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
	ORR R1, R1, #RCC_AHBENR_GPIOAEN :OR: RCC_AHBENR_GPIOCEN
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
	ldr r2, =(GPIO_MODER_MODER0 :OR: GPIO_MODER_MODER1 :OR: GPIO_MODER_MODER4 :OR: GPIO_MODER_MODER5)
	BIC R1, R1, r2    ; This clears the group of bits MODER0,1,4, 5
	ldr r2, =(GPIO_MODER_MODER0_0 :OR: GPIO_MODER_MODER1_0 :OR: GPIO_MODER_MODER4_0 :OR: GPIO_MODER_MODER5_0)
	ORR R1, R1, r2 ; The final value is "01" at MODER0,1,4,5

	; Now the pins PA5, PA6 is configured as the general purpose output. The new value
	; to be stored back to the GPIOA_MODER register is 0xA8000020.
	STR R1, [R0]
	
	; PC13 is in input floating already, so no change there
	
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