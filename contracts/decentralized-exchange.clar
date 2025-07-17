(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-pool-not-found (err u103))
(define-constant err-insufficient-liquidity (err u104))
(define-constant err-zero-amount (err u105))
(define-constant err-slippage-too-high (err u106))
(define-constant err-invalid-token (err u107))
(define-constant err-pool-exists (err u108))

(define-data-var fee-rate uint u300)

(define-map pools
  { token-x: principal, token-y: principal }
  {
    reserve-x: uint,
    reserve-y: uint,
    lp-token: principal,
    total-supply: uint
  }
)

(define-map user-lp-tokens
  { user: principal, token-x: principal, token-y: principal }
  { amount: uint }
)

(define-map token-balances
  { user: principal, token: principal }
  { balance: uint }
)

(define-private (get-pool-key (token-x principal) (token-y principal))
  (if (< (len (unwrap-panic (to-consensus-buff? token-x))) 
         (len (unwrap-panic (to-consensus-buff? token-y))))
      { token-x: token-x, token-y: token-y }
      { token-x: token-y, token-y: token-x }
  )
)

(define-read-only (get-pool-info (token-x principal) (token-y principal))
  (map-get? pools (get-pool-key token-x token-y))
)

(define-read-only (get-user-lp-balance (user principal) (token-x principal) (token-y principal))
  (default-to 
    { amount: u0 }
    (map-get? user-lp-tokens { user: user, token-x: token-x, token-y: token-y })
  )
)

(define-read-only (get-token-balance (user principal) (token principal))
  (default-to 
    { balance: u0 }
    (map-get? token-balances { user: user, token: token })
  )
)

(define-private (mint-tokens (to principal) (token principal) (amount uint))
  (let 
    (
      (current-balance (get balance (get-token-balance to token)))
      (new-balance (+ current-balance amount))
    )
    (map-set token-balances { user: to, token: token } { balance: new-balance })
    (ok amount)
  )
)

(define-private (burn-tokens (from principal) (token principal) (amount uint))
  (let 
    (
      (current-balance (get balance (get-token-balance from token)))
    )
    (if (>= current-balance amount)
        (begin
          (map-set token-balances { user: from, token: token } { balance: (- current-balance amount) })
          (ok amount)
        )
        err-insufficient-balance
    )
  )
)

(define-private (transfer-tokens (from principal) (to principal) (token principal) (amount uint))
  (let 
    (
      (sender-balance (get balance (get-token-balance from token)))
      (recipient-balance (get balance (get-token-balance to token)))
    )
    (if (>= sender-balance amount)
        (begin
          (map-set token-balances { user: from, token: token } { balance: (- sender-balance amount) })
          (map-set token-balances { user: to, token: token } { balance: (+ recipient-balance amount) })
          (ok amount)
        )
        err-insufficient-balance
    )
  )
)

(define-private (sqrt (n uint))
  (if (is-eq n u0)
      u0
      (if (is-eq n u1)
          u1
          (let ((guess (/ n u2)))
            (if (>= (* guess guess) n)
                guess
                (+ guess u1)
            )
          )
      )
  )
)

(define-private (min (a uint) (b uint))
  (if (< a b) a b)
)

(define-private (calculate-liquidity (reserve-x uint) (reserve-y uint) (amount-x uint) (amount-y uint) (total-supply uint))
  (if (is-eq total-supply u0)
      (sqrt (* amount-x amount-y))
      (min 
        (/ (* amount-x total-supply) reserve-x)
        (/ (* amount-y total-supply) reserve-y)
      )
  )
)

(define-public (create-pool (token-x principal) (token-y principal) (amount-x uint) (amount-y uint))
  (let 
    (
      (pool-key (get-pool-key token-x token-y))
      (existing-pool (map-get? pools pool-key))
    )
    (if (is-some existing-pool)
        err-pool-exists
        (if (or (is-eq amount-x u0) (is-eq amount-y u0))
            err-invalid-amount
            (let 
              (
                (initial-liquidity (sqrt (* amount-x amount-y)))
                (lp-token contract-caller)
              )
              (try! (transfer-tokens tx-sender (as-contract tx-sender) token-x amount-x))
              (try! (transfer-tokens tx-sender (as-contract tx-sender) token-y amount-y))
              (map-set pools pool-key {
                reserve-x: amount-x,
                reserve-y: amount-y,
                lp-token: lp-token,
                total-supply: initial-liquidity
              })
              (map-set user-lp-tokens 
                { user: tx-sender, token-x: (get token-x pool-key), token-y: (get token-y pool-key) }
                { amount: initial-liquidity }
              )
              (ok initial-liquidity)
            )
        )
    )
  )
)

(define-public (add-liquidity (token-x principal) (token-y principal) (amount-x uint) (amount-y uint))
  (let 
    (
      (pool-key (get-pool-key token-x token-y))
      (pool-info (unwrap! (map-get? pools pool-key) err-pool-not-found))
    )
    (if (or (is-eq amount-x u0) (is-eq amount-y u0))
        err-invalid-amount
        (let 
          (
            (reserve-x (get reserve-x pool-info))
            (reserve-y (get reserve-y pool-info))
            (total-supply (get total-supply pool-info))
            (liquidity (calculate-liquidity reserve-x reserve-y amount-x amount-y total-supply))
            (current-lp-balance (get amount (get-user-lp-balance tx-sender (get token-x pool-key) (get token-y pool-key))))
          )
          (try! (transfer-tokens tx-sender (as-contract tx-sender) token-x amount-x))
          (try! (transfer-tokens tx-sender (as-contract tx-sender) token-y amount-y))
          (map-set pools pool-key {
            reserve-x: (+ reserve-x amount-x),
            reserve-y: (+ reserve-y amount-y),
            lp-token: (get lp-token pool-info),
            total-supply: (+ total-supply liquidity)
          })
          (map-set user-lp-tokens 
            { user: tx-sender, token-x: (get token-x pool-key), token-y: (get token-y pool-key) }
            { amount: (+ current-lp-balance liquidity) }
          )
          (ok liquidity)
        )
    )
  )
)

(define-public (remove-liquidity (token-x principal) (token-y principal) (liquidity uint))
  (let 
    (
      (pool-key (get-pool-key token-x token-y))
      (pool-info (unwrap! (map-get? pools pool-key) err-pool-not-found))
      (user-lp-balance (get amount (get-user-lp-balance tx-sender (get token-x pool-key) (get token-y pool-key))))
    )
    (if (> liquidity user-lp-balance)
        err-insufficient-liquidity
        (let 
          (
            (reserve-x (get reserve-x pool-info))
            (reserve-y (get reserve-y pool-info))
            (total-supply (get total-supply pool-info))
            (amount-x (/ (* liquidity reserve-x) total-supply))
            (amount-y (/ (* liquidity reserve-y) total-supply))
          )
          (try! (transfer-tokens (as-contract tx-sender) tx-sender token-x amount-x))
          (try! (transfer-tokens (as-contract tx-sender) tx-sender token-y amount-y))
          (map-set pools pool-key {
            reserve-x: (- reserve-x amount-x),
            reserve-y: (- reserve-y amount-y),
            lp-token: (get lp-token pool-info),
            total-supply: (- total-supply liquidity)
          })
          (map-set user-lp-tokens 
            { user: tx-sender, token-x: (get token-x pool-key), token-y: (get token-y pool-key) }
            { amount: (- user-lp-balance liquidity) }
          )
          (ok { amount-x: amount-x, amount-y: amount-y })
        )
    )
  )
)

(define-private (get-amount-out (amount-in uint) (reserve-in uint) (reserve-out uint))
  (let 
    (
      (amount-in-with-fee (- amount-in (/ (* amount-in (var-get fee-rate)) u10000)))
      (numerator (* amount-in-with-fee reserve-out))
      (denominator (+ reserve-in amount-in-with-fee))
    )
    (/ numerator denominator)
  )
)

(define-public (swap-exact-tokens-for-tokens (token-in principal) (token-out principal) (amount-in uint) (min-amount-out uint))
  (let 
    (
      (pool-key (get-pool-key token-in token-out))
      (pool-info (unwrap! (map-get? pools pool-key) err-pool-not-found))
      (is-token-x (is-eq token-in (get token-x pool-key)))
      (reserve-in (if is-token-x (get reserve-x pool-info) (get reserve-y pool-info)))
      (reserve-out (if is-token-x (get reserve-y pool-info) (get reserve-x pool-info)))
      (amount-out (get-amount-out amount-in reserve-in reserve-out))
    )
    (if (< amount-out min-amount-out)
        err-slippage-too-high
        (if (is-eq amount-in u0)
            err-zero-amount
            (begin
              (try! (transfer-tokens tx-sender (as-contract tx-sender) token-in amount-in))
              (try! (transfer-tokens (as-contract tx-sender) tx-sender token-out amount-out))
              (map-set pools pool-key {
                reserve-x: (if is-token-x (+ (get reserve-x pool-info) amount-in) (- (get reserve-x pool-info) amount-out)),
                reserve-y: (if is-token-x (- (get reserve-y pool-info) amount-out) (+ (get reserve-y pool-info) amount-in)),
                lp-token: (get lp-token pool-info),
                total-supply: (get total-supply pool-info)
              })
              (ok amount-out)
            )
        )
    )
  )
)

(define-public (get-amount-out-preview (token-in principal) (token-out principal) (amount-in uint))
  (let 
    (
      (pool-key (get-pool-key token-in token-out))
      (pool-info (unwrap! (map-get? pools pool-key) err-pool-not-found))
      (is-token-x (is-eq token-in (get token-x pool-key)))
      (reserve-in (if is-token-x (get reserve-x pool-info) (get reserve-y pool-info)))
      (reserve-out (if is-token-x (get reserve-y pool-info) (get reserve-x pool-info)))
    )
    (ok (get-amount-out amount-in reserve-in reserve-out))
  )
)

(define-public (deposit-token (token principal) (amount uint))
  (if (is-eq amount u0)
      err-zero-amount
      (mint-tokens tx-sender token amount)
  )
)

(define-public (withdraw-token (token principal) (amount uint))
  (if (is-eq amount u0)
      err-zero-amount
      (burn-tokens tx-sender token amount)
  )
)

(define-public (set-fee-rate (new-fee-rate uint))
  (if (is-eq tx-sender contract-owner)
      (begin
        (var-set fee-rate new-fee-rate)
        (ok new-fee-rate)
      )
      err-owner-only
  )
)

(define-read-only (get-fee-rate)
  (ok (var-get fee-rate))
)