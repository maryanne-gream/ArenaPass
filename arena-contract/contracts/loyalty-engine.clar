;; Loyalty Engine Smart Contract
;; Rewards fans with NFTs/badges for attendance and engagement

;; Define the non-fungible token for loyalty badges
(define-non-fungible-token loyalty-badge uint)

;; Constants for badge tiers
(define-constant BRONZE-TIER u1)
(define-constant SILVER-TIER u2)
(define-constant GOLD-TIER u3)
(define-constant PLATINUM-TIER u4)

;; Attendance thresholds for each tier
(define-constant BRONZE-THRESHOLD u5)
(define-constant SILVER-THRESHOLD u15)
(define-constant GOLD-THRESHOLD u30)
(define-constant PLATINUM-THRESHOLD u50)

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-MINTED (err u101))
(define-constant ERR-INVALID-EVENT (err u102))
(define-constant ERR-INSUFFICIENT-ATTENDANCE (err u103))
(define-constant ERR-TOKEN-NOT-FOUND (err u104))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Data variables
(define-data-var next-badge-id uint u1)
(define-data-var total-events uint u0)

;; Maps
(define-map attendance-count principal uint)
(define-map user-badges principal (list 50 uint))
(define-map badge-metadata uint {
    tier: uint,
    event-count: uint,
    timestamp: uint,
    badge-name: (string-ascii 50)
})
(define-map event-attendance uint (list 1000 principal))
(define-map user-event-attendance {user: principal, event: uint} bool)

;; Private functions

;; Get the next badge ID and increment
(define-private (get-next-badge-id)
    (let ((badge-id (var-get next-badge-id)))
        (var-set next-badge-id (+ badge-id u1))
        badge-id))

;; Determine badge tier based on attendance count
(define-private (get-badge-tier (attendance uint))
    (if (>= attendance PLATINUM-THRESHOLD)
        PLATINUM-TIER
        (if (>= attendance GOLD-THRESHOLD)
            GOLD-TIER
            (if (>= attendance SILVER-THRESHOLD)
                SILVER-TIER
                BRONZE-TIER))))

;; Get badge name based on tier
(define-private (get-badge-name (tier uint))
    (if (is-eq tier PLATINUM-TIER)
        "Platinum Loyalty Badge"
        (if (is-eq tier GOLD-TIER)
            "Gold Loyalty Badge"
            (if (is-eq tier SILVER-TIER)
                "Silver Loyalty Badge"
                "Bronze Loyalty Badge"))))

;; Check if user qualifies for a new badge
(define-private (qualifies-for-badge (user principal) (attendance uint))
    (let ((current-badges (default-to (list) (map-get? user-badges user))))
        (and 
            (or 
                (and (>= attendance BRONZE-THRESHOLD) (is-none (index-of current-badges BRONZE-TIER)))
                (and (>= attendance SILVER-THRESHOLD) (is-none (index-of current-badges SILVER-TIER)))
                (and (>= attendance GOLD-THRESHOLD) (is-none (index-of current-badges GOLD-TIER)))
                (and (>= attendance PLATINUM-THRESHOLD) (is-none (index-of current-badges PLATINUM-TIER)))
            )
            true)))

;; Remove badge ID from a list of badge IDs
(define-private (remove-badge-from-list (badge-list (list 50 uint)) (badge-to-remove uint))
    (fold remove-badge-helper badge-list {target: badge-to-remove, result: (list)}))

;; Fixed helper function to receive badge-to-remove via data structure
(define-private (remove-badge-helper (badge-id uint) (data {target: uint, result: (list 50 uint)}))
    (let ((target (get target data))
          (current-result (get result data)))
        (if (is-eq badge-id target)
            {target: target, result: current-result}
            {target: target, result: (unwrap-panic (as-max-len? (append current-result badge-id) u50))})))

;; Public functions

;; Record attendance for an event
(define-public (record-attendance (event-id uint))
    (let (
        (current-attendance (default-to u0 (map-get? attendance-count tx-sender)))
        (new-attendance (+ current-attendance u1))
    )
        ;; Check if user already attended this event
        (asserts! (is-none (map-get? user-event-attendance {user: tx-sender, event: event-id})) ERR-ALREADY-MINTED)
        
        ;; Record attendance
        (map-set attendance-count tx-sender new-attendance)
        (map-set user-event-attendance {user: tx-sender, event: event-id} true)
        
        ;; Add user to event attendance list
        (let ((current-attendees (default-to (list) (map-get? event-attendance event-id))))
            (map-set event-attendance event-id (unwrap! (as-max-len? (append current-attendees tx-sender) u1000) ERR-INVALID-EVENT)))
        
        ;; Check if user qualifies for a new badge and mint if so
        ;; Fixed return type mismatch - both branches now return (response uint uint)
        (if (qualifies-for-badge tx-sender new-attendance)
            (mint-loyalty-badge tx-sender new-attendance)
            (ok u0))))

;; Mint a loyalty badge for a user
(define-private (mint-loyalty-badge (user principal) (attendance uint))
    (let (
        (badge-id (get-next-badge-id))
        (tier (get-badge-tier attendance))
        (badge-name (get-badge-name tier))
        (current-badges (default-to (list) (map-get? user-badges user)))
    )
        ;; Mint the NFT
        (try! (nft-mint? loyalty-badge badge-id user))
        
        ;; Store badge metadata
        (map-set badge-metadata badge-id {
            tier: tier,
            event-count: attendance,
            timestamp: block-height,
            badge-name: badge-name
        })
        
        ;; Update user's badge list
        (map-set user-badges user (unwrap! (as-max-len? (append current-badges badge-id) u50) ERR-INVALID-EVENT))
        
        (ok badge-id)))

;; Admin function to manually mint badge
(define-public (admin-mint-badge (user principal) (tier uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (let (
            (badge-id (get-next-badge-id))
            (badge-name (get-badge-name tier))
            (current-badges (default-to (list) (map-get? user-badges user)))
            (user-attendance (default-to u0 (map-get? attendance-count user)))
        )
            ;; Mint the NFT
            (try! (nft-mint? loyalty-badge badge-id user))
            
            ;; Store badge metadata
            (map-set badge-metadata badge-id {
                tier: tier,
                event-count: user-attendance,
                timestamp: block-height,
                badge-name: badge-name
            })
            
            ;; Update user's badge list
            (map-set user-badges user (unwrap! (as-max-len? (append current-badges badge-id) u50) ERR-INVALID-EVENT))
            
            (ok badge-id))))

;; Transfer badge to another user
(define-public (transfer-badge (badge-id uint) (sender principal) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
        (try! (nft-transfer? loyalty-badge badge-id sender recipient))
        
        ;; Update badge ownership in user lists
        (let (
            (sender-badges (default-to (list) (map-get? user-badges sender)))
            (recipient-badges (default-to (list) (map-get? user-badges recipient)))
            ;; Extract result from the data structure returned by remove function
            (updated-sender-badges (get result (remove-badge-from-list sender-badges badge-id)))
        )
            ;; Remove from sender's list using our helper function
            (map-set user-badges sender updated-sender-badges)
            ;; Add to recipient's list
            (map-set user-badges recipient (unwrap! (as-max-len? (append recipient-badges badge-id) u50) ERR-INVALID-EVENT)))
        
        (ok true)))

;; Read-only functions

;; Get user's attendance count
(define-read-only (get-attendance-count (user principal))
    (default-to u0 (map-get? attendance-count user)))

;; Get user's badges
(define-read-only (get-user-badges (user principal))
    (default-to (list) (map-get? user-badges user)))

;; Get badge metadata
(define-read-only (get-badge-metadata (badge-id uint))
    (map-get? badge-metadata badge-id))

;; Get badge owner
(define-read-only (get-badge-owner (badge-id uint))
    (nft-get-owner? loyalty-badge badge-id))

;; Get user's highest tier
(define-read-only (get-user-highest-tier (user principal))
    (let ((attendance (get-attendance-count user)))
        (get-badge-tier attendance)))

;; Check if user attended specific event
(define-read-only (did-attend-event (user principal) (event-id uint))
    (default-to false (map-get? user-event-attendance {user: user, event: event-id})))

;; Get event attendees
(define-read-only (get-event-attendees (event-id uint))
    (default-to (list) (map-get? event-attendance event-id)))

;; Get total number of events
(define-read-only (get-total-events)
    (var-get total-events))

;; Get next badge ID
(define-read-only (get-next-badge-id-preview)
    (var-get next-badge-id))

;; Check user's progress to next tier
(define-read-only (get-progress-to-next-tier (user principal))
    (let ((attendance (get-attendance-count user)))
        (if (< attendance BRONZE-THRESHOLD)
            {current-tier: u0, next-tier: BRONZE-TIER, events-needed: (- BRONZE-THRESHOLD attendance)}
            (if (< attendance SILVER-THRESHOLD)
                {current-tier: BRONZE-TIER, next-tier: SILVER-TIER, events-needed: (- SILVER-THRESHOLD attendance)}
                (if (< attendance GOLD-THRESHOLD)
                    {current-tier: SILVER-TIER, next-tier: GOLD-TIER, events-needed: (- GOLD-THRESHOLD attendance)}
                    (if (< attendance PLATINUM-THRESHOLD)
                        {current-tier: GOLD-TIER, next-tier: PLATINUM-TIER, events-needed: (- PLATINUM-THRESHOLD attendance)}
                        {current-tier: PLATINUM-TIER, next-tier: u0, events-needed: u0}))))))

;; Get user statistics
(define-read-only (get-user-stats (user principal))
    (let (
        (attendance (get-attendance-count user))
        (badges (get-user-badges user))
        (highest-tier (get-user-highest-tier user))
        (progress (get-progress-to-next-tier user))
    )
        {
            attendance-count: attendance,
            total-badges: (len badges),
            badges: badges,
            highest-tier: highest-tier,
            progress-to-next-tier: progress
        }))
