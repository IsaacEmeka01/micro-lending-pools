;; Micro-lending Pools for Developing Countries with Reputation-based Collateral
;; A decentralized lending platform that enables peer-to-peer micro-lending
;; using reputation scores as collateral mechanism

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-loan-not-active (err u105))
(define-constant err-loan-overdue (err u106))
(define-constant err-reputation-too-low (err u107))
(define-constant err-already-exists (err u108))
(define-constant err-invalid-duration (err u109))
(define-constant err-pool-not-active (err u110))

;; Minimum reputation score required for borrowing
(define-constant min-reputation-score u50)
(define-constant max-loan-duration u365) ;; days
(define-constant reputation-decay-rate u1) ;; per missed payment

;; Data Variables
(define-data-var next-loan-id uint u1)
(define-data-var next-pool-id uint u1)
(define-data-var total-pools uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points

;; User reputation tracking
(define-map user-reputation 
  { user: principal }
  {
    score: uint,
    total-loans: uint,
    successful-repayments: uint,
    missed-payments: uint,
    total-borrowed: uint,
    total-repaid: uint,
    last-updated: uint
  }
)

;; Lending pool structure
(define-map lending-pools
  { pool-id: uint }
  {
    creator: principal,
    total-funds: uint,
    available-funds: uint,
    interest-rate: uint, ;; annual rate in basis points
    min-loan-amount: uint,
    max-loan-amount: uint,
    pool-name: (string-ascii 50),
    is-active: bool,
    created-at: uint,
    total-loans-issued: uint
  }
)

;; Pool contributors/lenders
(define-map pool-contributors
  { pool-id: uint, contributor: principal }
  {
    amount-contributed: uint,
    earnings: uint,
    join-date: uint
  }
)

;; Active loans
(define-map active-loans
  { loan-id: uint }
  {
    borrower: principal,
    pool-id: uint,
    loan-amount: uint,
    interest-rate: uint,
    duration-days: uint,
    start-date: uint,
    due-date: uint,
    amount-repaid: uint,
    total-due: uint,
    status: (string-ascii 20), ;; "active", "repaid", "defaulted", "overdue"
    collateral-reputation: uint
  }
)

;; Repayment history
(define-map repayment-history
  { loan-id: uint, payment-id: uint }
  {
    amount: uint,
    payment-date: uint,
    borrower: principal
  }
)

;; Helper Functions

;; Calculate interest for a loan
(define-private (calculate-interest (principal-amount uint) (rate uint) (days uint))
  (let ((annual-interest (/ (* principal-amount rate) u10000)))
    (/ (* annual-interest days) u365)))

;; Update user reputation based on payment behavior
(define-private (update-reputation (user principal) (payment-made bool) (amount uint))
  (let ((current-rep (default-to 
                      { score: u100, total-loans: u0, successful-repayments: u0, 
                        missed-payments: u0, total-borrowed: u0, total-repaid: u0, 
                        last-updated: u0 }
                      (map-get? user-reputation { user: user }))))
    (if payment-made
      (map-set user-reputation { user: user }
        (merge current-rep {
          score: (+ (get score current-rep) u5),
          successful-repayments: (+ (get successful-repayments current-rep) u1),
          total-repaid: (+ (get total-repaid current-rep) amount),
          last-updated: block-height
        }))
      (map-set user-reputation { user: user }
        (merge current-rep {
          score: (if (>= (get score current-rep) reputation-decay-rate)
                   (- (get score current-rep) reputation-decay-rate)
                   u0),
          missed-payments: (+ (get missed-payments current-rep) u1),
          last-updated: block-height
        })))))

;; Public Functions

;; Initialize user reputation
(define-public (initialize-reputation)
  (let ((existing-rep (map-get? user-reputation { user: tx-sender })))
    (if (is-some existing-rep)
      (err err-already-exists)
      (ok (map-set user-reputation { user: tx-sender }
            { score: u100, total-loans: u0, successful-repayments: u0,
              missed-payments: u0, total-borrowed: u0, total-repaid: u0,
              last-updated: block-height })))))

;; Create a new lending pool
(define-public (create-lending-pool 
  (pool-name (string-ascii 50))
  (interest-rate uint)
  (min-loan-amount uint)
  (max-loan-amount uint))
  (let ((pool-id (var-get next-pool-id)))
    (asserts! (> interest-rate u0) (err err-invalid-amount))
    (asserts! (> max-loan-amount min-loan-amount) (err err-invalid-amount))
    
    (map-set lending-pools { pool-id: pool-id }
      { creator: tx-sender,
        total-funds: u0,
        available-funds: u0,
        interest-rate: interest-rate,
        min-loan-amount: min-loan-amount,
        max-loan-amount: max-loan-amount,
        pool-name: pool-name,
        is-active: true,
        created-at: block-height,
        total-loans-issued: u0 })
    
    (var-set next-pool-id (+ pool-id u1))
    (var-set total-pools (+ (var-get total-pools) u1))
    (ok pool-id)))

;; Contribute funds to a lending pool
(define-public (contribute-to-pool (pool-id uint) (amount uint))
  (let ((pool (unwrap! (map-get? lending-pools { pool-id: pool-id }) (err err-not-found)))
        (existing-contribution (map-get? pool-contributors { pool-id: pool-id, contributor: tx-sender })))
    
    (asserts! (get is-active pool) (err err-pool-not-active))
    (asserts! (> amount u0) (err err-invalid-amount))
    
    ;; Transfer STX to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update pool funds
    (map-set lending-pools { pool-id: pool-id }
      (merge pool {
        total-funds: (+ (get total-funds pool) amount),
        available-funds: (+ (get available-funds pool) amount)
      }))
    
    ;; Update contributor record
    (match existing-contribution
      contrib (map-set pool-contributors { pool-id: pool-id, contributor: tx-sender }
                (merge contrib {
                  amount-contributed: (+ (get amount-contributed contrib) amount)
                }))
      (map-set pool-contributors { pool-id: pool-id, contributor: tx-sender }
        { amount-contributed: amount,
          earnings: u0,
          join-date: block-height }))
    
    (ok amount)))

;; Request a loan from a pool
(define-public (request-loan 
  (pool-id uint)
  (loan-amount uint)
  (duration-days uint))
  (let ((pool (unwrap! (map-get? lending-pools { pool-id: pool-id }) (err err-not-found)))
        (borrower-rep (unwrap! (map-get? user-reputation { user: tx-sender }) (err err-not-found)))
        (loan-id (var-get next-loan-id)))
    
    (asserts! (get is-active pool) (err err-pool-not-active))
    (asserts! (>= (get score borrower-rep) min-reputation-score) (err err-reputation-too-low))
    (asserts! (>= loan-amount (get min-loan-amount pool)) (err err-invalid-amount))
    (asserts! (<= loan-amount (get max-loan-amount pool)) (err err-invalid-amount))
    (asserts! (<= loan-amount (get available-funds pool)) (err err-insufficient-funds))
    (asserts! (and (> duration-days u0) (<= duration-days max-loan-duration)) (err err-invalid-duration))
    
    (let ((interest-amount (calculate-interest loan-amount (get interest-rate pool) duration-days))
          (total-due (+ loan-amount interest-amount))
          (due-date (+ block-height duration-days)))
      
      ;; Create loan record
      (map-set active-loans { loan-id: loan-id }
        { borrower: tx-sender,
          pool-id: pool-id,
          loan-amount: loan-amount,
          interest-rate: (get interest-rate pool),
          duration-days: duration-days,
          start-date: block-height,
          due-date: due-date,
          amount-repaid: u0,
          total-due: total-due,
          status: "active",
          collateral-reputation: (get score borrower-rep) })
      
      ;; Update pool available funds
      (map-set lending-pools { pool-id: pool-id }
        (merge pool {
          available-funds: (- (get available-funds pool) loan-amount),
          total-loans-issued: (+ (get total-loans-issued pool) u1)
        }))
      
      ;; Update borrower reputation
      (map-set user-reputation { user: tx-sender }
        (merge borrower-rep {
          total-loans: (+ (get total-loans borrower-rep) u1),
          total-borrowed: (+ (get total-borrowed borrower-rep) loan-amount)
        }))
      
      ;; Transfer loan amount to borrower
      (try! (as-contract (stx-transfer? loan-amount tx-sender (get borrower (unwrap! (map-get? active-loans { loan-id: loan-id }) (err err-not-found))))))
      
      (var-set next-loan-id (+ loan-id u1))
      (ok loan-id))))

;; Repay a loan
(define-public (repay-loan (loan-id uint) (amount uint))
  (let ((loan (unwrap! (map-get? active-loans { loan-id: loan-id }) (err err-not-found))))
    
    (asserts! (is-eq tx-sender (get borrower loan)) (err err-unauthorized))
    (asserts! (is-eq (get status loan) "active") (err err-loan-not-active))
    (asserts! (> amount u0) (err err-invalid-amount))
    
    (let ((new-amount-repaid (+ (get amount-repaid loan) amount))
          (remaining-due (- (get total-due loan) new-amount-repaid)))
      
      ;; Transfer repayment to contract
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      ;; Update loan status
      (map-set active-loans { loan-id: loan-id }
        (merge loan {
          amount-repaid: new-amount-repaid,
          status: (if (<= remaining-due u0) "repaid" "active")
        }))
      
      ;; Update reputation
      (update-reputation tx-sender true amount)
      
      ;; If loan fully repaid, update pool funds
      (if (<= remaining-due u0)
        (let ((pool (unwrap! (map-get? lending-pools { pool-id: (get pool-id loan) }) (err err-not-found))))
          (map-set lending-pools { pool-id: (get pool-id loan) }
            (merge pool {
              available-funds: (+ (get available-funds pool) (get total-due loan))
            })))
        true)
      
      (ok new-amount-repaid))))

;; Read-only Functions

;; Get user reputation
(define-read-only (get-user-reputation (user principal))
  (map-get? user-reputation { user: user }))

;; Get lending pool details
(define-read-only (get-lending-pool (pool-id uint))
  (map-get? lending-pools { pool-id: pool-id }))

;; Get loan details
(define-read-only (get-loan-details (loan-id uint))
  (map-get? active-loans { loan-id: loan-id }))

;; Get pool contribution details
(define-read-only (get-pool-contribution (pool-id uint) (contributor principal))
  (map-get? pool-contributors { pool-id: pool-id, contributor: contributor }))

;; Get total number of pools
(define-read-only (get-total-pools)
  (var-get total-pools))

;; Check if user is eligible for loan
(define-read-only (check-loan-eligibility (user principal) (amount uint))
  (match (map-get? user-reputation { user: user })
    rep (ok (>= (get score rep) min-reputation-score))
    (err err-not-found)))

;; Get platform statistics
(define-read-only (get-platform-stats)
  (ok {
    total-pools: (var-get total-pools),
    next-loan-id: (var-get next-loan-id),
    platform-fee-rate: (var-get platform-fee-rate)
  }))

;; Admin Functions (Owner only)

;; Update platform fee rate
(define-public (update-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
    (asserts! (<= new-rate u1000) (err err-invalid-amount)) ;; Max 10%
    (var-set platform-fee-rate new-rate)
    (ok new-rate)))

;; Deactivate a pool (emergency function)
(define-public (deactivate-pool (pool-id uint))
  (let ((pool (unwrap! (map-get? lending-pools { pool-id: pool-id }) (err err-not-found))))
    (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
    (map-set lending-pools { pool-id: pool-id }
      (merge pool { is-active: false }))
    (ok true)))