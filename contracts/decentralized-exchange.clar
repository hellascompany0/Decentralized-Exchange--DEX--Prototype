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
(define-constant err-paused (err u117))

(define-data-var fee-rate uint u300)
(define-data-var reward-rate uint u100)
(define-data-var reward-token principal tx-sender)
(define-data-var flash-loan-fee uint u9)
(define-data-var paused bool false)

(define-map pools
  { token-x: principal, token-y: principal }
  {
    reserve-x: uint,
    reserve-y: uint,
    lp-token: principal,
    total-supply: uint
  }
)

(define-map pool-fees
  { token-x: principal, token-y: principal }
  { fee-rate: uint }
)

(define-map user-lp-tokens
  { user: principal, token-x: principal, token-y: principal }
  { amount: uint }
)

(define-map token-balances
  { user: principal, token: principal }
  { balance: uint }
)

(define-map reward-data
  { user: principal, token-x: principal, token-y: principal }
  { 
    last-claim-height: uint,
    accumulated-rewards: uint
  }
)

(define-map flash-loan-balances
  { user: principal, token: principal }
  { amount: uint }
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

(define-read-only (get-reward-info (user principal) (token-x principal) (token-y principal))
  (default-to 
    { last-claim-height: u0, accumulated-rewards: u0 }
    (map-get? reward-data { user: user, token-x: token-x, token-y: token-y })
  )
)

(define-read-only (get-flash-loan-balance (user principal) (token principal))
  (default-to 
    { amount: u0 }
    (map-get? flash-loan-balances { user: user, token: token })
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

(define-private (calculate-pending-rewards (user principal) (token-x principal) (token-y principal))
  (let 
    (
      (pool-key (get-pool-key token-x token-y))
      (user-lp-balance (get amount (get-user-lp-balance user (get token-x pool-key) (get token-y pool-key))))
      (reward-info (get-reward-info user token-x token-y))
      (last-claim (get last-claim-height reward-info))
      (current-height stacks-block-height)
      (blocks-elapsed (- current-height last-claim))
      (reward-per-block (var-get reward-rate))
    )
    (/ (* user-lp-balance reward-per-block blocks-elapsed) u10000)
  )
)

(define-private (update-rewards (user principal) (token-x principal) (token-y principal))
  (let 
    (
      (current-rewards (get accumulated-rewards (get-reward-info user token-x token-y)))
      (pending-rewards (calculate-pending-rewards user token-x token-y))
      (total-rewards (+ current-rewards pending-rewards))
    )
    (map-set reward-data 
      { user: user, token-x: token-x, token-y: token-y }
      { 
        last-claim-height: stacks-block-height,
        accumulated-rewards: total-rewards
      }
    )
  )
)

(define-private (calculate-flash-loan-fee (amount uint))
  (/ (* amount (var-get flash-loan-fee)) u10000)
)

(define-private (get-available-liquidity (token principal))
  (get balance (get-token-balance (as-contract tx-sender) token))
)

(define-private (record-flash-loan (user principal) (token principal) (amount uint))
  (map-set flash-loan-balances { user: user, token: token } { amount: amount })
)

(define-private (clear-flash-loan (user principal) (token principal))
  (map-delete flash-loan-balances { user: user, token: token })
)

(define-private (pool-exists (token-x principal) (token-y principal))
  (is-some (get-pool-info token-x token-y))
)

(define-private (calculate-output-amount (token-in principal) (token-out principal) (amount-in uint))
  (let 
    (
      (pool-key (get-pool-key token-in token-out))
      (pool-info-opt (map-get? pools pool-key))
      (fee-opt (map-get? pool-fees pool-key))
    )
    (match pool-info-opt
      pool-info
        (let 
          (
            (is-token-x (is-eq token-in (get token-x pool-key)))
            (reserve-in (if is-token-x (get reserve-x pool-info) (get reserve-y pool-info)))
            (reserve-out (if is-token-x (get reserve-y pool-info) (get reserve-x pool-info)))
            (fee (match fee-opt f (get fee-rate f) (var-get fee-rate)))
          )
          (some (get-amount-out-with-fee amount-in reserve-in reserve-out fee))
        )
      none
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
              (map-set reward-data 
                { user: tx-sender, token-x: (get token-x pool-key), token-y: (get token-y pool-key) }
                { last-claim-height: stacks-block-height, accumulated-rewards: u0 }
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
          (update-rewards tx-sender (get token-x pool-key) (get token-y pool-key))
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
          (update-rewards tx-sender (get token-x pool-key) (get token-y pool-key))
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

(define-private (get-amount-out-with-fee (amount-in uint) (reserve-in uint) (reserve-out uint) (fee uint))
  (let 
    (
      (amount-in-with-fee (- amount-in (/ (* amount-in fee) u10000)))
      (numerator (* amount-in-with-fee reserve-out))
      (denominator (+ reserve-in amount-in-with-fee))
    )
    (/ numerator denominator)
  )
)

(define-public (swap-exact-tokens-for-tokens (token-in principal) (token-out principal) (amount-in uint) (min-amount-out uint))
  (begin
    (try! (ensure-not-paused))
    (let 
    (
      (pool-key (get-pool-key token-in token-out))
      (pool-info (unwrap! (map-get? pools pool-key) err-pool-not-found))
      (is-token-x (is-eq token-in (get token-x pool-key)))
      (reserve-in (if is-token-x (get reserve-x pool-info) (get reserve-y pool-info)))
      (reserve-out (if is-token-x (get reserve-y pool-info) (get reserve-x pool-info)))
      (fee-opt (map-get? pool-fees pool-key))
      (fee (match fee-opt f (get fee-rate f) (var-get fee-rate)))
      (amount-out (get-amount-out-with-fee amount-in reserve-in reserve-out fee))
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
    (let 
      (
        (fee-opt (map-get? pool-fees pool-key))
        (fee (match fee-opt f (get fee-rate f) (var-get fee-rate)))
      )
      (ok (get-amount-out-with-fee amount-in reserve-in reserve-out fee))
    )
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

(define-read-only (get-pool-fee-rate (token-x principal) (token-y principal))
  (let
    (
      (pool-key (get-pool-key token-x token-y))
      (fee-opt (map-get? pool-fees pool-key))
    )
    (match fee-opt
      fee
        (ok (get fee-rate fee))
      (ok (var-get fee-rate))
    )
  )
)

(define-public (set-pool-fee-rate (token-x principal) (token-y principal) (new-fee uint))
  (if (is-eq tx-sender contract-owner)
      (let
        (
          (pool-key (get-pool-key token-x token-y))
        )
        (begin
          (map-set pool-fees pool-key { fee-rate: new-fee })
          (ok new-fee)
        )
      )
      err-owner-only
  )
)

(define-public (set-paused (new-paused bool))
  (if (is-eq tx-sender contract-owner)
      (begin
        (var-set paused new-paused)
        (ok new-paused)
      )
      err-owner-only
  )
)

(define-read-only (get-paused)
  (ok (var-get paused))
)

(define-private (ensure-not-paused)
  (if (var-get paused)
      err-paused
      (ok true)
  )
)

(define-public (claim-rewards (token-x principal) (token-y principal))
  (let 
    (
      (pool-key (get-pool-key token-x token-y))
      (user-lp-balance (get amount (get-user-lp-balance tx-sender (get token-x pool-key) (get token-y pool-key))))
      (reward-info (get-reward-info tx-sender token-x token-y))
      (pending-rewards (calculate-pending-rewards tx-sender token-x token-y))
      (total-rewards (+ (get accumulated-rewards reward-info) pending-rewards))
    )
    (if (is-eq total-rewards u0)
        (err u109)
        (begin
          (map-set reward-data 
            { user: tx-sender, token-x: token-x, token-y: token-y }
            { last-claim-height: stacks-block-height, accumulated-rewards: u0 }
          )
          (mint-tokens tx-sender (var-get reward-token) total-rewards)
        )
    )
  )
)

(define-public (set-reward-rate (new-rate uint))
  (if (is-eq tx-sender contract-owner)
      (begin
        (var-set reward-rate new-rate)
        (ok new-rate)
      )
      err-owner-only
  )
)

(define-public (set-reward-token (new-token principal))
  (if (is-eq tx-sender contract-owner)
      (begin
        (var-set reward-token new-token)
        (ok new-token)
      )
      err-owner-only
  )
)

(define-read-only (get-reward-rate)
  (ok (var-get reward-rate))
)

(define-read-only (get-reward-token)
  (ok (var-get reward-token))
)

(define-read-only (get-pending-rewards (user principal) (token-x principal) (token-y principal))
  (let 
    (
      (reward-info (get-reward-info user token-x token-y))
      (pending-rewards (calculate-pending-rewards user token-x token-y))
      (total-rewards (+ (get accumulated-rewards reward-info) pending-rewards))
    )
    (ok total-rewards)
  )
)

(define-public (flash-loan (token principal) (amount uint))
  (begin
    (try! (ensure-not-paused))
    (let 
    (
      (available-liquidity (get-available-liquidity token))
      (fee-amount (calculate-flash-loan-fee amount))
      (repay-amount (+ amount fee-amount))
      (current-loan (get amount (get-flash-loan-balance tx-sender token)))
    )
    (if (> current-loan u0)
        (err u110)
        (if (> amount available-liquidity)
            (err u111)
            (if (is-eq amount u0)
                (err u105)
                (begin
                  (record-flash-loan tx-sender token repay-amount)
                  (mint-tokens tx-sender token amount)
                )
            )
        )
    )
    )
  )
)

(define-public (repay-flash-loan (token principal))
  (let 
    (
      (loan-amount (get amount (get-flash-loan-balance tx-sender token)))
      (user-balance (get balance (get-token-balance tx-sender token)))
    )
    (if (is-eq loan-amount u0)
        (err u112)
        (if (< user-balance loan-amount)
            err-insufficient-balance
            (begin
              (clear-flash-loan tx-sender token)
              (burn-tokens tx-sender token loan-amount)
            )
        )
    )
  )
)

(define-public (set-flash-loan-fee (new-fee uint))
  (if (is-eq tx-sender contract-owner)
      (if (> new-fee u1000)
          (err u113)
          (begin
            (var-set flash-loan-fee new-fee)
            (ok new-fee)
          )
      )
      err-owner-only
  )
)

(define-read-only (get-flash-loan-fee)
  (ok (var-get flash-loan-fee))
)

(define-read-only (get-max-flash-loan (token principal))
  (ok (get-available-liquidity token))
)

(define-read-only (calculate-flash-loan-cost (amount uint))
  (ok (calculate-flash-loan-fee amount))
)

(define-public (swap-multi-hop (token-in principal) (token-mid principal) (token-out principal) (amount-in uint) (min-amount-out uint))
  (begin
    (try! (ensure-not-paused))
    (let 
    (
      (pool1-exists (pool-exists token-in token-mid))
      (pool2-exists (pool-exists token-mid token-out))
    )
    (if (not pool1-exists)
        (err u114)
        (if (not pool2-exists)
            (err u115)
            (if (is-eq amount-in u0)
                (err u105)
                (let 
                  (
                    (mid-amount-opt (calculate-output-amount token-in token-mid amount-in))
                  )
                  (match mid-amount-opt
                    mid-amount
                      (let 
                        (
                          (final-amount-opt (calculate-output-amount token-mid token-out mid-amount))
                        )
                        (match final-amount-opt
                          final-amount
                            (if (< final-amount min-amount-out)
                                (err u106)
                                (begin
                                  (try! (swap-exact-tokens-for-tokens token-in token-mid amount-in u0))
                                  (swap-exact-tokens-for-tokens token-mid token-out mid-amount min-amount-out)
                                )
                            )
                          (err u116)
                        )
                      )
                    (err u116)
                  )
                )
            )
        )
    )
    )
  )
)

(define-read-only (preview-multi-hop-swap (token-in principal) (token-mid principal) (token-out principal) (amount-in uint))
  (let 
    (
      (pool1-exists (pool-exists token-in token-mid))
      (pool2-exists (pool-exists token-mid token-out))
    )
    (if (not pool1-exists)
        (err u114)
        (if (not pool2-exists)
            (err u115)
            (if (is-eq amount-in u0)
                (err u105)
                (let 
                  (
                    (mid-amount-opt (calculate-output-amount token-in token-mid amount-in))
                  )
                  (match mid-amount-opt
                    mid-amount
                      (let 
                        (
                          (final-amount-opt (calculate-output-amount token-mid token-out mid-amount))
                        )
                        (match final-amount-opt
                          final-amount
                            (ok final-amount)
                          (err u116)
                        )
                      )
                    (err u116)
                  )
                )
            )
        )
    )
  )
)

(define-read-only (get-optimal-route (token-in principal) (token-out principal) (token-mid-a principal) (token-mid-b principal) (amount-in uint))
  (let 
    (
      (route-a-opt (calculate-output-amount token-in token-mid-a amount-in))
      (route-b-opt (calculate-output-amount token-in token-mid-b amount-in))
      (direct-opt (calculate-output-amount token-in token-out amount-in))
    )
    (match direct-opt
      direct-amount
        (ok { route: "direct", output: direct-amount, mid-token: token-in })
      (match route-a-opt
        mid-amount-a
          (let 
            (
              (final-a-opt (calculate-output-amount token-mid-a token-out mid-amount-a))
            )
            (match final-a-opt
              final-a
                (match route-b-opt
                  mid-amount-b
                    (let 
                      (
                        (final-b-opt (calculate-output-amount token-mid-b token-out mid-amount-b))
                      )
                      (match final-b-opt
                        final-b
                          (if (> final-a final-b)
                              (ok { route: "route-a", output: final-a, mid-token: token-mid-a })
                              (ok { route: "route-b", output: final-b, mid-token: token-mid-b })
                          )
                        (ok { route: "route-a", output: final-a, mid-token: token-mid-a })
                      )
                    )
                  (ok { route: "route-a", output: final-a, mid-token: token-mid-a })
                )
              (match route-b-opt
                mid-amount-b
                  (let 
                    (
                      (final-b-opt (calculate-output-amount token-mid-b token-out mid-amount-b))
                    )
                    (match final-b-opt
                      final-b
                        (ok { route: "route-b", output: final-b, mid-token: token-mid-b })
                      (err u117)
                    )
                  )
                (err u117)
              )
            )
          )
        (match route-b-opt
          mid-amount-b
            (let 
              (
                (final-b-opt (calculate-output-amount token-mid-b token-out mid-amount-b))
              )
              (match final-b-opt
                final-b
                  (ok { route: "route-b", output: final-b, mid-token: token-mid-b })
                (err u117)
              )
            )
          (err u117)
        )
      )
    )
  )
)

(define-read-only (find-best-path (token-in principal) (token-out principal) (amount-in uint))
  (let 
    (
      (direct-exists (pool-exists token-in token-out))
      (direct-output-opt (if direct-exists (calculate-output-amount token-in token-out amount-in) none))
    )
    (match direct-output-opt
      direct-output
        (ok { path-type: "direct", expected-output: direct-output, requires-routing: false })
      (ok { path-type: "multi-hop", expected-output: u0, requires-routing: true })
    )
  )
)
