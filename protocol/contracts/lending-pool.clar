;; BitFi Lending Pool Contract
;; Manages the lending pool and interest calculations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u200))
(define-constant ERR-INSUFFICIENT-FUNDS (err u201))
(define-constant ERR-INVALID-AMOUNT (err u202))

;; Base interest rate (5% APY in basis points)
(define-constant BASE-INTEREST-RATE u500)
;; Optimal utilization rate (80%)
(define-constant OPTIMAL-UTILIZATION u80)
;; Maximum interest rate (25% APY in basis points)
(define-constant MAX_INTEREST_RATE u2500)

;; Data Variables
(define-data-var total-deposits uint u0)
(define-data-var total-borrows uint u0)
(define-data-var reserve-factor uint u1000) ;; 10% in basis points
(define-data-var last-update-block uint u0)

;; Interest rate calculation
(define-read-only (get-utilization-rate)
  (let
    (
      (deposits (var-get total-deposits))
      (borrows (var-get total-borrows))
    )
    (if (is-eq deposits u0)
      u0
      (/ (* borrows u100) deposits)
    )
  )
)

(define-read-only (get-borrow-rate)
  (let
    (
      (utilization (get-utilization-rate))
    )
    (if (<= utilization OPTIMAL-UTILIZATION)
      ;; Below optimal: linear increase
      (+ BASE-INTEREST-RATE (/ (* utilization BASE-INTEREST-RATE) OPTIMAL-UTILIZATION))
      ;; Above optimal: steep increase
      (let
        (
          (excess-utilization (- utilization OPTIMAL-UTILIZATION))
          (excess-rate (/ (* excess-utilization (- MAX_INTEREST_RATE BASE-INTEREST-RATE)) (- u100 OPTIMAL-UTILIZATION)))
        )
        (+ BASE-INTEREST-RATE excess-rate)
      )
    )
  )
)

(define-read-only (get-supply-rate)
  (let
    (
      (borrow-rate (get-borrow-rate))
      (utilization (get-utilization-rate))
      (reserve-factor-rate (var-get reserve-factor))
    )
    (/ (* borrow-rate utilization (- u10000 reserve-factor-rate)) u1000000)
  )
)

;; Pool stats
(define-read-only (get-pool-stats)
  {
    total-deposits: (var-get total-deposits),
    total-borrows: (var-get total-borrows),
    utilization-rate: (get-utilization-rate),
    borrow-rate: (get-borrow-rate),
    supply-rate: (get-supply-rate),
    reserve-factor: (var-get reserve-factor)
  }
)

;; Admin functions
(define-public (set-reserve-factor (new-factor uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= new-factor u5000) ERR-INVALID-AMOUNT) ;; Max 50%
    (var-set reserve-factor new-factor)
    (ok true)
  )
)

(define-public (update-pool-state (new-deposits uint) (new-borrows uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set total-deposits new-deposits)
    (var-set total-borrows new-borrows)
    (var-set last-update-block stacks-block-height)
    (ok true)
  )
)
