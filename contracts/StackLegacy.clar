;; No trait import needed for direct contract calls

(define-map wills
  { will-id: uint }
  {
    owner: principal,
    beneficiary: principal,
    amount: uint,
    asset: principal, ;; SIP-010 token contract or native STX
    unlock-block: uint,
    is-confirmed: bool,
    is-claimed: bool
  }
)

(define-data-var will-counter uint u0)

(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALREADY_CLAIMED (err u101))
(define-constant ERR_NOT_CONFIRMED (err u102))
(define-constant ERR_TOO_EARLY (err u103))
(define-constant ERR_DOES_NOT_EXIST (err u104))
(define-constant ERR_ALREADY_EXISTS (err u105))

;; Create a new will
(define-public (create-will (beneficiary principal) (amount uint) (unlock-block uint))
  (let ((sender tx-sender)
        (id (+ (var-get will-counter) u1)))
    (begin
      (var-set will-counter id)
      (map-set wills
        {will-id: id}
        {
          owner: sender,
          beneficiary: beneficiary,
          amount: amount,
          asset: .stx-token, ;; Using .stx-token trait for native STX
          unlock-block: unlock-block,
          is-confirmed: false,
          is-claimed: false
        }
      )
      (stx-transfer? amount sender (as-contract tx-sender))
    )
  )
)

;; Confirm the owner's "death"
(define-public (confirm-death (will-id uint))
  (begin
    (match (map-get? wills {will-id: will-id})
      will
      (begin
        (map-set wills
          {will-id: will-id}
          (merge will { is-confirmed: true })
        )
        (ok true)
      )
      ERR_DOES_NOT_EXIST
    )
  )
)

;; Beneficiary claims the inheritance
(define-public (release-assets (will-id uint))
  (let ((current-block stacks-block-height))
    (match (map-get? wills {will-id: will-id})
      will
      (if (or (get is-claimed will) (not (get is-confirmed will)))
          (if (get is-claimed will) ERR_ALREADY_CLAIMED ERR_NOT_CONFIRMED)
          (if (< current-block (get unlock-block will))
              ERR_TOO_EARLY
              (begin
                (map-set wills
                  {will-id: will-id}
                  (merge will { is-claimed: true })
                )
                (stx-transfer? (get amount will) (as-contract tx-sender) (get beneficiary will))
              )
          )
      )
      ERR_DOES_NOT_EXIST
    )
  )
)

;; Cancel a will (only by creator, before it's claimed)
(define-public (cancel-will (will-id uint))
  (match (map-get? wills {will-id: will-id})
    will
    (if (and (is-eq tx-sender (get owner will)) (not (get is-claimed will)))
        (begin
          (map-delete wills {will-id: will-id})
          (stx-transfer? (get amount will) (as-contract tx-sender) (get owner will))
        )
        ERR_UNAUTHORIZED
    )
    ERR_DOES_NOT_EXIST
  )
)
