;; Entry Validator Smart Contract
;; Purpose: QR-based check-in system that marks tickets as used
;; Ensures tickets can only be used once and tracks entry validation

;; Error constants
(define-constant ERR_NOT_AUTHORIZED (err u1001))
(define-constant ERR_TICKET_NOT_FOUND (err u1002))
(define-constant ERR_TICKET_ALREADY_USED (err u1003))
(define-constant ERR_TICKET_EXPIRED (err u1004))
(define-constant ERR_INVALID_VALIDATOR (err u1005))
(define-constant ERR_EVENT_NOT_ACTIVE (err u1006))

;; Contract owner
(define-constant CONTRACT_OWNER tx-sender)

;; Data structures
(define-map tickets
  { ticket-id: uint }
  {
    owner: principal,
    event-id: uint,
    ticket-type: (string-ascii 50),
    issue-block: uint,
    expiry-block: uint,
    is-used: bool,
    used-at-block: (optional uint),
    validated-by: (optional principal)
  }
)

(define-map events
  { event-id: uint }
  {
    name: (string-ascii 100),
    start-block: uint,
    end-block: uint,
    is-active: bool,
    total-tickets: uint,
    used-tickets: uint
  }
)

(define-map authorized-validators
  { validator: principal }
  {
    is-authorized: bool,
    added-at-block: uint,
    event-permissions: (list 10 uint) ;; List of event IDs this validator can validate
  }
)

(define-map validation-logs
  { log-id: uint }
  {
    ticket-id: uint,
    validator: principal,
    validation-block: uint,
    event-id: uint,
    success: bool
  }
)

;; Data variables
(define-data-var next-ticket-id uint u1)
(define-data-var next-event-id uint u1)
(define-data-var next-log-id uint u1)

;; Authorization functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (is-authorized-validator (validator principal) (event-id uint))
  (match (map-get? authorized-validators { validator: validator })
    validator-data (and 
      (get is-authorized validator-data)
      (is-some (index-of (get event-permissions validator-data) event-id))
    )
    false
  )
)

;; Admin functions
(define-public (add-validator (validator principal) (event-permissions (list 10 uint)))
  (begin
    (asserts! (is-contract-owner) ERR_NOT_AUTHORIZED)
    (ok (map-set authorized-validators
      { validator: validator }
      {
        is-authorized: true,
        added-at-block: block-height,
        event-permissions: event-permissions
      }
    ))
  )
)

(define-public (remove-validator (validator principal))
  (begin
    (asserts! (is-contract-owner) ERR_NOT_AUTHORIZED)
    (ok (map-set authorized-validators
      { validator: validator }
      {
        is-authorized: false,
        added-at-block: block-height,
        event-permissions: (list)
      }
    ))
  )
)

(define-public (create-event (name (string-ascii 100)) (start-block uint) (end-block uint))
  (let ((event-id (var-get next-event-id)))
    (asserts! (is-contract-owner) ERR_NOT_AUTHORIZED)
    (map-set events
      { event-id: event-id }
      {
        name: name,
        start-block: start-block,
        end-block: end-block,
        is-active: true,
        total-tickets: u0,
        used-tickets: u0
      }
    )
    (var-set next-event-id (+ event-id u1))
    (ok event-id)
  )
)

(define-public (issue-ticket (owner principal) (event-id uint) (ticket-type (string-ascii 50)) (expiry-block uint))
  (let ((ticket-id (var-get next-ticket-id)))
    (asserts! (is-contract-owner) ERR_NOT_AUTHORIZED)
    (asserts! (is-some (map-get? events { event-id: event-id })) ERR_TICKET_NOT_FOUND)
    
    (map-set tickets
      { ticket-id: ticket-id }
      {
        owner: owner,
        event-id: event-id,
        ticket-type: ticket-type,
        issue-block: block-height,
        expiry-block: expiry-block,
        is-used: false,
        used-at-block: none,
        validated-by: none
      }
    )
    
    ;; Update event ticket count
    (match (map-get? events { event-id: event-id })
      event-data (map-set events
        { event-id: event-id }
        (merge event-data { total-tickets: (+ (get total-tickets event-data) u1) })
      )
      false
    )
    
    (var-set next-ticket-id (+ ticket-id u1))
    (ok ticket-id)
  )
)

;; Core validation function
(define-public (validate-entry (ticket-id uint))
  (let (
    (ticket (unwrap! (map-get? tickets { ticket-id: ticket-id }) ERR_TICKET_NOT_FOUND))
    (event-id (get event-id ticket))
    (event-data (unwrap! (map-get? events { event-id: event-id }) ERR_TICKET_NOT_FOUND))
    (log-id (var-get next-log-id))
  )
    ;; Check if validator is authorized for this event
    (asserts! (is-authorized-validator tx-sender event-id) ERR_INVALID_VALIDATOR)
    
    ;; Check if ticket is already used
    (asserts! (not (get is-used ticket)) ERR_TICKET_ALREADY_USED)
    
    ;; Check if ticket is expired
    (asserts! (<= block-height (get expiry-block ticket)) ERR_TICKET_EXPIRED)
    
    ;; Check if event is active and within time bounds
    (asserts! (get is-active event-data) ERR_EVENT_NOT_ACTIVE)
    (asserts! (and 
      (>= block-height (get start-block event-data))
      (<= block-height (get end-block event-data))
    ) ERR_EVENT_NOT_ACTIVE)
    
    ;; Mark ticket as used
    (map-set tickets
      { ticket-id: ticket-id }
      (merge ticket {
        is-used: true,
        used-at-block: (some block-height),
        validated-by: (some tx-sender)
      })
    )
    
    ;; Update event used ticket count
    (map-set events
      { event-id: event-id }
      (merge event-data { used-tickets: (+ (get used-tickets event-data) u1) })
    )
    
    ;; Log the validation
    (map-set validation-logs
      { log-id: log-id }
      {
        ticket-id: ticket-id,
        validator: tx-sender,
        validation-block: block-height,
        event-id: event-id,
        success: true
      }
    )
    
    (var-set next-log-id (+ log-id u1))
    (ok true)
  )
)

;; Read-only functions
(define-read-only (is-used (ticket-id uint))
  (match (map-get? tickets { ticket-id: ticket-id })
    ticket (get is-used ticket)
    false
  )
)

(define-read-only (get-ticket-info (ticket-id uint))
  (map-get? tickets { ticket-id: ticket-id })
)

(define-read-only (get-event-info (event-id uint))
  (map-get? events { event-id: event-id })
)

(define-read-only (get-validator-info (validator principal))
  (map-get? authorized-validators { validator: validator })
)

(define-read-only (is-ticket-valid (ticket-id uint))
  (match (map-get? tickets { ticket-id: ticket-id })
    ticket (and
      (not (get is-used ticket))
      (<= block-height (get expiry-block ticket))
      (match (map-get? events { event-id: (get event-id ticket) })
        event-data (and
          (get is-active event-data)
          (>= block-height (get start-block event-data))
          (<= block-height (get end-block event-data))
        )
        false
      )
    )
    false
  )
)

(define-read-only (get-event-stats (event-id uint))
  (match (map-get? events { event-id: event-id })
    event-data (some {
      total-tickets: (get total-tickets event-data),
      used-tickets: (get used-tickets event-data),
      remaining-tickets: (- (get total-tickets event-data) (get used-tickets event-data)),
      usage-percentage: (if (> (get total-tickets event-data) u0)
        (/ (* (get used-tickets event-data) u100) (get total-tickets event-data))
        u0
      )
    })
    none
  )
)

(define-read-only (get-validation-log (log-id uint))
  (map-get? validation-logs { log-id: log-id })
)

;; Utility functions for frontend integration
(define-read-only (can-validate (validator principal) (ticket-id uint))
  (match (map-get? tickets { ticket-id: ticket-id })
    ticket (and
      (is-authorized-validator validator (get event-id ticket))
      (is-ticket-valid ticket-id)
    )
    false
  )
)

(define-read-only (get-ticket-owner (ticket-id uint))
  (match (map-get? tickets { ticket-id: ticket-id })
    ticket (some (get owner ticket))
    none
  )
)
