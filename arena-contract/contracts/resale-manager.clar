;; Resale Manager Contract
;; Manages optional resale logic, geo-restrictions, time-locks, and resale toggles

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-TICKET-NOT-FOUND (err u101))
(define-constant ERR-RESALE-NOT-ENABLED (err u102))
(define-constant ERR-INVALID-REGION (err u103))
(define-constant ERR-TIME-LOCK-ACTIVE (err u104))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u105))
(define-constant ERR-TRANSFER-FAILED (err u106))
(define-constant ERR-ALREADY-OWNED (err u107))

;; Data Variables
(define-data-var contract-owner principal CONTRACT-OWNER)
(define-data-var default-royalty-rate uint u250) ;; 2.5% in basis points

;; Data Maps
;; Core resale tracking
(define-map resale-enabled uint bool)
(define-map resale-location uint (string-utf8 32))
(define-map resale-price uint uint)
(define-map resale-time-lock uint uint) ;; Block height when resale becomes available

;; Ticket ownership and metadata
(define-map ticket-owner uint principal)
(define-map ticket-original-issuer uint principal)
(define-map ticket-royalty-rate uint uint) ;; Per-ticket royalty rate in basis points

;; Regional restrictions
(define-map allowed-regions (string-utf8 32) bool)
(define-map user-region principal (string-utf8 32))

;; Resale history
(define-map resale-count uint uint)
(define-map last-resale-price uint uint)

;; Read-only functions
(define-read-only (get-resale-status (ticket-id uint))
  (default-to false (map-get? resale-enabled ticket-id))
)

(define-read-only (get-resale-location (ticket-id uint))
  (map-get? resale-location ticket-id)
)

(define-read-only (get-resale-price (ticket-id uint))
  (map-get? resale-price ticket-id)
)

(define-read-only (get-ticket-owner (ticket-id uint))
  (map-get? ticket-owner ticket-id)
)

(define-read-only (get-time-lock (ticket-id uint))
  (map-get? resale-time-lock ticket-id)
)

(define-read-only (is-resale-allowed (ticket-id uint))
  (let (
    (enabled (default-to false (map-get? resale-enabled ticket-id)))
    (time-lock (default-to u0 (map-get? resale-time-lock ticket-id)))
  )
    (and enabled (>= block-height time-lock))
  )
)

(define-read-only (get-royalty-info (ticket-id uint) (sale-price uint))
  (let (
    (royalty-rate (default-to (var-get default-royalty-rate) (map-get? ticket-royalty-rate ticket-id)))
    (original-issuer (map-get? ticket-original-issuer ticket-id))
    (royalty-amount (/ (* sale-price royalty-rate) u10000))
  )
    {
      royalty-rate: royalty-rate,
      royalty-amount: royalty-amount,
      original-issuer: original-issuer
    }
  )
)

;; Administrative functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

(define-public (set-default-royalty-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-rate u1000) ERR-NOT-AUTHORIZED) ;; Max 10%
    (var-set default-royalty-rate new-rate)
    (ok true)
  )
)

(define-public (add-allowed-region (region (string-utf8 32)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set allowed-regions region true)
    (ok true)
  )
)

(define-public (remove-allowed-region (region (string-utf8 32)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-delete allowed-regions region)
    (ok true)
  )
)

;; Ticket management functions
(define-public (register-ticket (ticket-id uint) (owner principal) (issuer principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set ticket-owner ticket-id owner)
    (map-set ticket-original-issuer ticket-id issuer)
    (map-set resale-count ticket-id u0)
    (ok true)
  )
)

(define-public (set-user-region (user principal) (region (string-utf8 32)))
  (begin
    (asserts! (or (is-eq tx-sender user) (is-eq tx-sender (var-get contract-owner))) ERR-NOT-AUTHORIZED)
    (asserts! (default-to false (map-get? allowed-regions region)) ERR-INVALID-REGION)
    (map-set user-region user region)
    (ok true)
  )
)

;; Core resale functions
(define-public (enable-resale (ticket-id uint) (region (string-utf8 32)) (price uint) (time-lock-blocks uint))
  (let (
    (owner (unwrap! (map-get? ticket-owner ticket-id) ERR-TICKET-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender owner) ERR-NOT-AUTHORIZED)
    (asserts! (default-to false (map-get? allowed-regions region)) ERR-INVALID-REGION)
    (asserts! (> price u0) ERR-INSUFFICIENT-PAYMENT)
    
    (map-set resale-enabled ticket-id true)
    (map-set resale-location ticket-id region)
    (map-set resale-price ticket-id price)
    (map-set resale-time-lock ticket-id (+ block-height time-lock-blocks))
    
    (ok true)
  )
)

(define-public (disable-resale (ticket-id uint))
  (let (
    (owner (unwrap! (map-get? ticket-owner ticket-id) ERR-TICKET-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender owner) ERR-NOT-AUTHORIZED)
    
    (map-set resale-enabled ticket-id false)
    (map-delete resale-location ticket-id)
    (map-delete resale-price ticket-id)
    (map-delete resale-time-lock ticket-id)
    
    (ok true)
  )
)

(define-public (update-resale-price (ticket-id uint) (new-price uint))
  (let (
    (owner (unwrap! (map-get? ticket-owner ticket-id) ERR-TICKET-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender owner) ERR-NOT-AUTHORIZED)
    (asserts! (default-to false (map-get? resale-enabled ticket-id)) ERR-RESALE-NOT-ENABLED)
    (asserts! (> new-price u0) ERR-INSUFFICIENT-PAYMENT)
    
    (map-set resale-price ticket-id new-price)
    (ok true)
  )
)

;; Main resale function
(define-public (resell-ticket (ticket-id uint) (buyer principal))
  (let (
    (current-owner (unwrap! (map-get? ticket-owner ticket-id) ERR-TICKET-NOT-FOUND))
    (sale-price (unwrap! (map-get? resale-price ticket-id) ERR-RESALE-NOT-ENABLED))
    (allowed-region (unwrap! (map-get? resale-location ticket-id) ERR-RESALE-NOT-ENABLED))
    (buyer-region (unwrap! (map-get? user-region buyer) ERR-INVALID-REGION))
    (time-lock (default-to u0 (map-get? resale-time-lock ticket-id)))
    (royalty-info (get-royalty-info ticket-id sale-price))
    (royalty-amount (get royalty-amount royalty-info))
    (seller-amount (- sale-price royalty-amount))
    (current-resale-count (default-to u0 (map-get? resale-count ticket-id)))
  )
    ;; Validation checks
    (asserts! (not (is-eq buyer current-owner)) ERR-ALREADY-OWNED)
    (asserts! (default-to false (map-get? resale-enabled ticket-id)) ERR-RESALE-NOT-ENABLED)
    (asserts! (is-eq buyer-region allowed-region) ERR-INVALID-REGION)
    (asserts! (>= block-height time-lock) ERR-TIME-LOCK-ACTIVE)
    
    ;; Transfer payment to seller
    (unwrap! (stx-transfer? seller-amount tx-sender current-owner) ERR-TRANSFER-FAILED)
    
    ;; Transfer royalty to original issuer (if applicable)
    (if (and (> royalty-amount u0) (is-some (get original-issuer royalty-info)))
      (unwrap! (stx-transfer? royalty-amount tx-sender (unwrap-panic (get original-issuer royalty-info))) ERR-TRANSFER-FAILED)
      true
    )
    
    ;; Update ownership and disable resale
    (map-set ticket-owner ticket-id buyer)
    (map-set resale-enabled ticket-id false)
    (map-delete resale-location ticket-id)
    (map-delete resale-price ticket-id)
    (map-delete resale-time-lock ticket-id)
    
    ;; Update resale history
    (map-set resale-count ticket-id (+ current-resale-count u1))
    (map-set last-resale-price ticket-id sale-price)
    
    (ok {
      ticket-id: ticket-id,
      new-owner: buyer,
      previous-owner: current-owner,
      sale-price: sale-price,
      royalty-paid: royalty-amount,
      resale-count: (+ current-resale-count u1)
    })
  )
)

;; Batch operations
(define-public (enable-multiple-resales (ticket-data (list 10 {ticket-id: uint, region: (string-utf8 32), price: uint, time-lock: uint})))
  (ok (map enable-resale-batch ticket-data))
)

(define-private (enable-resale-batch (data {ticket-id: uint, region: (string-utf8 32), price: uint, time-lock: uint}))
  (enable-resale (get ticket-id data) (get region data) (get price data) (get time-lock data))
)

;; Emergency functions
(define-public (emergency-disable-resale (ticket-id uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set resale-enabled ticket-id false)
    (ok true)
  )
)

(define-public (set-ticket-royalty-rate (ticket-id uint) (rate uint))
  (let (
    (owner (unwrap! (map-get? ticket-owner ticket-id) ERR-TICKET-NOT-FOUND))
    (issuer (unwrap! (map-get? ticket-original-issuer ticket-id) ERR-TICKET-NOT-FOUND))
  )
    (asserts! (or (is-eq tx-sender owner) (is-eq tx-sender issuer) (is-eq tx-sender (var-get contract-owner))) ERR-NOT-AUTHORIZED)
    (asserts! (<= rate u1000) ERR-NOT-AUTHORIZED) ;; Max 10%
    (map-set ticket-royalty-rate ticket-id rate)
    (ok true)
  )
)
