
; For Pinout description, see the attached documentation PDF

		AREA    GPIO_Driver, CODE, READONLY  	; hlavicka souboru
	
		GET		stm32f303xe.s					; vlozeni souboru s pojmenovanymi adresami
		; jsou zde definovany adresy pristupu do pameti (k registrum)




    EXPORT GPIO_INIT        

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
	ORR R1, R1, #RCC_AHBENR_GPIOAEN :OR: RCC_AHBENR_GPIOCEN
	
	
	STR R1, [R0]
	
	; initialize USART and timer pins
	LDR R0, =GPIOA_MODER
	LDR R1, [R0]
	ldr r2, =(GPIO_MODER_MODER9 :OR: GPIO_MODER_MODER2 :OR: GPIO_MODER_MODER3 :OR: GPIO_MODER_MODER0 :OR: GPIO_MODER_MODER1)
	bic r1, r2
	ldr r2, =(GPIO_MODER_MODER9_1 :OR: GPIO_MODER_MODER2_1 :OR: GPIO_MODER_MODER3_1 :OR: GPIO_MODER_MODER0_1 :OR: GPIO_MODER_MODER1_1)
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
	
	;activate alternate functions on timer pins
	ldr r0, =GPIOA_AFRL
	ldr r1, [r0]
	ldr r2, =(GPIO_AFRL_AFRL0 :OR: GPIO_AFRL_AFRL1)
	bic r1, r2
	ldr r2, =(1 :SHL: GPIO_AFRL_AFRL0_Pos) :OR: (1 :SHL: GPIO_AFRL_AFRL1_Pos)
	orr r1, r2
	str r1, [r0]
	
	ldr r0, =GPIOA_AFRH
	ldr r1, [r0]
	ldr r2, =(GPIO_AFRH_AFRH1)
	bic r1, r2
	ldr r2, =(10 :SHL: GPIO_AFRH_AFRH1_Pos)
	orr r1, r2
	str r1, [r0]
	
	
	;initialize output pins
	LDR R0, =GPIOC_MODER
	LDR R1, [R0]
	ldr r2, =(GPIO_MODER_MODER0 :OR: GPIO_MODER_MODER1)
	bic r1, r2
	ldr r2, =(GPIO_MODER_MODER0_0 :OR: GPIO_MODER_MODER1_0)
	orr r1, r2
	str r1, [r0]
	
	pop {r0-r2}
	bx lr
	endp



	ALIGN
				END	
