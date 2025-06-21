;; Arena Pass NFT Contract
;; SIP-009 Compliant NFT for Arena Access Tickets

;; Define the NFT
(define-non-fungible-token arena-pass uint)

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-TOKEN-OWNER (err u101))
(define-constant ERR-TOKEN-NOT-FOUND (err u102))
(define-constant ERR-TOKEN-ALREADY-EXISTS (err u103))
(define-constant ERR-INVALID-RECIPIENT (err u104))
(define-constant ERR-TRANSFER-FAILED (err u105))
(define-constant ERR-MINT-FAILED (err u106))
(define-constant ERR-BURN-FAILED (err u107))

;; Data Variables
(define-data-var last-token-id uint u0)
(define-data-var contract-uri (optional (string-utf8 256)) none)

;; Data Maps
(define-map token-metadata uint {
    name: (string-utf8 64),
    description: (string-utf8 256),
    image: (string-utf8 256),
    arena-type: (string-utf8 32),
    tier: (string-utf8 16),
    valid-until: uint,
    created-at: uint
})

(define-map authorized-minters principal bool)

;; Private Functions
(define-private (is-contract-owner)
    (is-eq tx-sender CONTRACT-OWNER))

(define-private (is-authorized-minter)
    (default-to false (map-get? authorized-minters tx-sender)))

;; Authorization Functions
(define-public (add-authorized-minter (minter principal))
    (begin
        (asserts! (is-contract-owner) ERR-OWNER-ONLY)
        (ok (map-set authorized-minters minter true))))

(define-public (remove-authorized-minter (minter principal))
    (begin
        (asserts! (is-contract-owner) ERR-OWNER-ONLY)
        (ok (map-delete authorized-minters minter))))

;; Core NFT Functions

;; Mint a new arena pass ticket
(define-public (mint-ticket 
    (recipient principal)
    (name (string-utf8 64))
    (description (string-utf8 256))
    (image (string-utf8 256))
    (arena-type (string-utf8 32))
    (tier (string-utf8 16))
    (valid-until uint))
    (let
        ((token-id (+ (var-get last-token-id) u1)))
        (begin
            (asserts! (or (is-contract-owner) (is-authorized-minter)) ERR-OWNER-ONLY)
            (asserts! (not (is-eq recipient 'SP000000000000000000002Q6VF78)) ERR-INVALID-RECIPIENT)
            (try! (nft-mint? arena-pass token-id recipient))
            (map-set token-metadata token-id {
                name: name,
                description: description,
                image: image,
                arena-type: arena-type,
                tier: tier,
                valid-until: valid-until,
                created-at: block-height
            })
            (var-set last-token-id token-id)
            (ok token-id))))

;; Transfer ticket to another principal
(define-public (transfer-ticket (ticket-id uint) (sender principal) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender sender) ERR-NOT-TOKEN-OWNER)
        (asserts! (not (is-eq recipient 'SP000000000000000000002Q6VF78)) ERR-INVALID-RECIPIENT)
        (try! (nft-transfer? arena-pass ticket-id sender recipient))
        (ok true)))

;; Burn/destroy a ticket
(define-public (burn-ticket (ticket-id uint))
    (let
        ((owner (unwrap! (nft-get-owner? arena-pass ticket-id) ERR-TOKEN-NOT-FOUND)))
        (begin
            (asserts! (or (is-eq tx-sender owner) (is-contract-owner)) ERR-NOT-TOKEN-OWNER)
            (try! (nft-burn? arena-pass ticket-id owner))
            (map-delete token-metadata ticket-id)
            (ok true))))

;; SIP-009 Required Functions

;; Get the last token ID
(define-read-only (get-last-token-id)
    (ok (var-get last-token-id)))

;; Get token URI (metadata)
(define-read-only (get-token-uri (token-id uint))
    (ok (some (concat 
        (concat 
            (concat "https://api.arenapass.com/metadata/" (uint-to-ascii token-id))
            ".json")
        ""))))

;; Get owner of a specific token
(define-read-only (get-owner (token-id uint))
    (ok (nft-get-owner? arena-pass token-id)))

;; Additional Read-Only Functions

;; Get token metadata
(define-read-only (get-token-metadata (token-id uint))
    (map-get? token-metadata token-id))

;; Check if token is valid (not expired)
(define-read-only (is-token-valid (token-id uint))
    (match (map-get? token-metadata token-id)
        metadata (> (get valid-until metadata) block-height)
        false))

;; Get total supply
(define-read-only (get-total-supply)
    (ok (var-get last-token-id)))

;; Check if principal is authorized minter
(define-read-only (is-minter-authorized (minter principal))
    (default-to false (map-get? authorized-minters minter)))

;; Get contract URI
(define-read-only (get-contract-uri)
    (ok (var-get contract-uri)))

;; Admin Functions

;; Set contract URI
(define-public (set-contract-uri (uri (string-utf8 256)))
    (begin
        (asserts! (is-contract-owner) ERR-OWNER-ONLY)
        (ok (var-set contract-uri (some uri)))))

;; Update token metadata (only owner or contract owner)
(define-public (update-token-metadata 
    (token-id uint)
    (name (string-utf8 64))
    (description (string-utf8 256))
    (image (string-utf8 256))
    (arena-type (string-utf8 32))
    (tier (string-utf8 16))
    (valid-until uint))
    (let
        ((owner (unwrap! (nft-get-owner? arena-pass token-id) ERR-TOKEN-NOT-FOUND))
         (current-metadata (unwrap! (map-get? token-metadata token-id) ERR-TOKEN-NOT-FOUND)))
        (begin
            (asserts! (or (is-eq tx-sender owner) (is-contract-owner)) ERR-NOT-TOKEN-OWNER)
            (ok (map-set token-metadata token-id {
                name: name,
                description: description,
                image: image,
                arena-type: arena-type,
                tier: tier,
                valid-until: valid-until,
                created-at: (get created-at current-metadata)
            })))))

;; Utility function to convert uint to ascii (simplified)
(define-read-only (uint-to-ascii (value uint))
    (if (is-eq value u0) "0"
    (if (is-eq value u1) "1"
    (if (is-eq value u2) "2"
    (if (is-eq value u3) "3"
    (if (is-eq value u4) "4"
    (if (is-eq value u5) "5"
    (if (is-eq value u6) "6"
    (if (is-eq value u7) "7"
    (if (is-eq value u8) "8"
    (if (is-eq value u9) "9"
    "unknown"))))))))))
)