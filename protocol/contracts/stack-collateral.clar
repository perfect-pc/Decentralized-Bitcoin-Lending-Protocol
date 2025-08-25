;; BitFi Stacking Collateral Contract
;; Allows users to use Stacked STX as collateral for borrowing

;; -----------------
;; Error constants
;; -----------------
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-AUTHORIZED (err u101))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u102))
(define-constant ERR-VAULT-NOT-FOUND (err u103))
(define-constant ERR-VAULT-ALREADY-EXISTS (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-LIQUIDATION-THRESHOLD-EXCEEDED (err u106))

;; -----------------
;; Parameters
;; -----------------
;; Minimum collateralization ratio (150%)
(define-constant MIN-COLLATERAL-RATIO u150)

;; (Optional) set your admin principal here before deploy (replace with your address)
;; Example testnet literal: 'ST2J...123
(define-constant CONTRACT-OWNER 'ST000000000000000000002AMW42H) ;; <-- replace with your principal

;; -----------------
;; Data Vars
;; -----------------
(define-data-var next-vault-id uint u1)
(define-data-var total-collateral uint u0)
(define-data-var total-borrowed uint u0)
;; Price in micro-STX per USD (8 decimals)
(define-data-var stx-price uint u100000000)

;; -----------------
;; Data Maps
;; -----------------
(define-map vaults
  { vault-id: uint }
  {
    owner: principal,
    stx-collateral: uint,
    borrowed-amount: uint,
    stacking-cycle: uint,
    created-at: uint,
    last-updated: uint
  }
)

(define-map user-vaults
  { user: principal }
  { vault-ids: (list 10 uint) }
)

(define-map stacking-rewards
  { vault-id: uint, cycle: uint }
  { reward-amount: uint, claimed: bool }
)

;; Authorization map for liquidation engine
(define-map authorized-contracts principal bool)

;; -----------------
;; Helpers
;; -----------------
(define-read-only (contract-principal)
  ;; safely get the contract principal
  (as-contract tx-sender)
)

;; -----------------
;; Read-only functions
;; -----------------
(define-read-only (get-vault (vault-id uint))
  (map-get? vaults { vault-id: vault-id })
)

(define-read-only (get-user-vaults (user principal))
  ;; Empty list literal `(list)` is typed by context -> (list 10 uint)
  (default-to { vault-ids: (list) } (map-get? user-vaults { user: user }))
)

(define-read-only (get-collateral-ratio (vault-id uint))
  (match (get-vault vault-id)
    vault-data
    (let
      (
        (collateral-value (* (get stx-collateral vault-data) (var-get stx-price)))
        (borrowed-amount (get borrowed-amount vault-data))
      )
      (if (is-eq borrowed-amount u0)
        (ok u0)
        (ok (/ (* collateral-value u100) borrowed-amount))
      )
    )
    ERR-VAULT-NOT-FOUND
  )
)

(define-read-only (get-max-borrowable (vault-id uint))
  (match (get-vault vault-id)
    vault-data
    (let
      (
        (collateral-value (* (get stx-collateral vault-data) (var-get stx-price)))
        (max-borrow (/ (* collateral-value u100) MIN-COLLATERAL-RATIO))
      )
      (ok max-borrow)
    )
    ERR-VAULT-NOT-FOUND
  )
)

(define-read-only (is-vault-liquidatable (vault-id uint))
  (match (get-collateral-ratio vault-id)
    ratio
      (ok (< ratio MIN-COLLATERAL-RATIO)) ;; success branch
    err-code
      (err err-code) ;; error branch, wrapped properly
  )
)


(define-read-only (get-total-stats)
  {
    total-collateral: (var-get total-collateral),
    total-borrowed: (var-get total-borrowed),
    stx-price: (var-get stx-price)
  }
)

;; -----------------
;; Private functions
;; -----------------
(define-private (add-vault-to-user (user principal) (vault-id uint))
  (let
    (
      (current-vaults (get vault-ids (get-user-vaults user)))
      ;; IMPORTANT: pass error constant directly; do NOT wrap with (err ...)
      (updated-vaults (unwrap! (as-max-len? (append current-vaults vault-id) u10) ERR-INVALID-AMOUNT))
    )
    (map-set user-vaults { user: user } { vault-ids: updated-vaults })
    (ok true)
  )
)

;; -----------------
;; Public functions
;; -----------------
(define-public (create-vault (stx-amount uint) (stacking-cycle uint))
  (let
    (
      (vault-id (var-get next-vault-id))
      (current-block stacks-block-height)
    )
    (asserts! (> stx-amount u0) ERR-INVALID-AMOUNT)

    ;; Transfer STX to contract as collateral
    (try! (stx-transfer? stx-amount tx-sender (contract-principal)))

    ;; Create vault
    (map-set vaults
      { vault-id: vault-id }
      {
        owner: tx-sender,
        stx-collateral: stx-amount,
        borrowed-amount: u0,
        stacking-cycle: stacking-cycle,
        created-at: current-block,
        last-updated: current-block
      }
    )

    ;; Add vault to user's vault list
    (try! (add-vault-to-user tx-sender vault-id))

    ;; Update global state
    (var-set next-vault-id (+ vault-id u1))
    (var-set total-collateral (+ (var-get total-collateral) stx-amount))

    (ok vault-id)
  )
)

(define-public (add-collateral (vault-id uint) (stx-amount uint))
  (let
    (
      (vault-data (unwrap! (get-vault vault-id) ERR-VAULT-NOT-FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq (get owner vault-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> stx-amount u0) ERR-INVALID-AMOUNT)

    ;; Transfer additional STX to contract
    (try! (stx-transfer? stx-amount tx-sender (contract-principal)))

    ;; Update vault (no `merge` in Clarity rebuild record)
    (map-set vaults
      { vault-id: vault-id }
      {
        owner: (get owner vault-data),
        stx-collateral: (+ (get stx-collateral vault-data) stx-amount),
        borrowed-amount: (get borrowed-amount vault-data),
        stacking-cycle: (get stacking-cycle vault-data),
        created-at: (get created-at vault-data),
        last-updated: current-block
      }
    )

    ;; Update global collateral
    (var-set total-collateral (+ (var-get total-collateral) stx-amount))

    (ok true)
  )
)

(define-public (borrow (vault-id uint) (amount uint))
  (let
    (
      (vault-data (unwrap! (get-vault vault-id) ERR-VAULT-NOT-FOUND))
      (max-borrowable (unwrap! (get-max-borrowable vault-id) ERR-VAULT-NOT-FOUND))
      (new-borrowed-amount (+ (get borrowed-amount vault-data) amount))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq (get owner vault-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= new-borrowed-amount max-borrowable) ERR-INSUFFICIENT-COLLATERAL)

    ;; Update vault
    (map-set vaults
      { vault-id: vault-id }
      {
        owner: (get owner vault-data),
        stx-collateral: (get stx-collateral vault-data),
        borrowed-amount: new-borrowed-amount,
        stacking-cycle: (get stacking-cycle vault-data),
        created-at: (get created-at vault-data),
        last-updated: current-block
      }
    )

    ;; Update global borrowed amount
    (var-set total-borrowed (+ (var-get total-borrowed) amount))

    ;; Emit event (token transfer handled elsewhere)
    (print {
      event: "borrow",
      vault-id: vault-id,
      user: tx-sender,
      amount: amount,
      new-total-borrowed: new-borrowed-amount
    })

    (ok amount)
  )
)

(define-public (repay (vault-id uint) (amount uint))
  (let
    (
      (vault-data (unwrap! (get-vault vault-id) ERR-VAULT-NOT-FOUND))
      (current-borrowed (get borrowed-amount vault-data))
      (repay-amount (if (<= amount current-borrowed) amount current-borrowed))
      (new-borrowed-amount (- current-borrowed repay-amount))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq (get owner vault-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> current-borrowed u0) ERR-INVALID-AMOUNT)

    ;; Update vault
    (map-set vaults
      { vault-id: vault-id }
      {
        owner: (get owner vault-data),
        stx-collateral: (get stx-collateral vault-data),
        borrowed-amount: new-borrowed-amount,
        stacking-cycle: (get stacking-cycle vault-data),
        created-at: (get created-at vault-data),
        last-updated: current-block
      }
    )

    ;; Update global borrowed amount
    (var-set total-borrowed (- (var-get total-borrowed) repay-amount))

    (print {
      event: "repay",
      vault-id: vault-id,
      user: tx-sender,
      amount: repay-amount,
      remaining-debt: new-borrowed-amount
    })

    (ok repay-amount)
  )
)

(define-public (withdraw-collateral (vault-id uint) (amount uint))
  (let
    (
      (vault-data (unwrap! (get-vault vault-id) ERR-VAULT-NOT-FOUND))
      (current-collateral (get stx-collateral vault-data))
      (borrowed-amount (get borrowed-amount vault-data))
      (new-collateral (- current-collateral amount))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq (get owner vault-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= amount current-collateral) ERR-INSUFFICIENT-COLLATERAL)

    ;; Maintain min collateral ratio if there is debt
    (if (> borrowed-amount u0)
      (let
        (
          (new-collateral-value (* new-collateral (var-get stx-price)))
          (new-ratio (/ (* new-collateral-value u100) borrowed-amount))
        )
        (asserts! (>= new-ratio MIN-COLLATERAL-RATIO) ERR-LIQUIDATION-THRESHOLD-EXCEEDED)
      )
      true
    )

    ;; Update vault
    (map-set vaults
      { vault-id: vault-id }
      {
        owner: (get owner vault-data),
        stx-collateral: new-collateral,
        borrowed-amount: (get borrowed-amount vault-data),
        stacking-cycle: (get stacking-cycle vault-data),
        created-at: (get created-at vault-data),
        last-updated: current-block
      }
    )

    ;; Update global collateral
    (var-set total-collateral (- (var-get total-collateral) amount))

    ;; Transfer STX back to user (from contract principal)
    (try! (stx-transfer? amount (contract-principal) (get owner vault-data)))

    (ok amount)
  )
)

;; Liquidation function (only callable by authorized contracts)
(define-public (liquidate-vault (vault-id uint) (liquidator principal))
  (let
    (
      (vault-data (unwrap! (get-vault vault-id) ERR-VAULT-NOT-FOUND))
      (is-liquidatable (unwrap! (is-vault-liquidatable vault-id) ERR-VAULT-NOT-FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (default-to false (map-get? authorized-contracts tx-sender)) ERR-NOT-AUTHORIZED)
    (asserts! is-liquidatable ERR-LIQUIDATION-THRESHOLD-EXCEEDED)

    ;; Reset vault (simplified full liquidation)
    (map-set vaults
      { vault-id: vault-id }
      {
        owner: (get owner vault-data),
        stx-collateral: u0,
        borrowed-amount: u0,
        stacking-cycle: (get stacking-cycle vault-data),
        created-at: (get created-at vault-data),
        last-updated: current-block
      }
    )

    ;; Update global state
    (var-set total-collateral (- (var-get total-collateral) (get stx-collateral vault-data)))
    (var-set total-borrowed (- (var-get total-borrowed) (get borrowed-amount vault-data)))

    ;; Transfer collateral to liquidator from contract principal
    (try! (stx-transfer? (get stx-collateral vault-data) (contract-principal) liquidator))

    (print {
      event: "liquidation",
      vault-id: vault-id,
      liquidator: liquidator,
      collateral-seized: (get stx-collateral vault-data),
      debt-cleared: (get borrowed-amount vault-data)
    })

    (ok true)
  )
)

;; -----------------
;; Admin functions
;; -----------------
(define-public (set-stx-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set stx-price new-price)
    (ok true)
  )
)

(define-public (authorize-contract (contract principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (map-set authorized-contracts contract true)
    (ok true)
  )
)

(define-public (revoke-contract (contract principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (map-delete authorized-contracts contract)
    (ok true)
  )
)
