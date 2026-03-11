;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; EcoStake-STX: Green Staking Rewards Contract
;; Functionality: Stake STX to support eco-projects & earn rewards
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; -------------------------------
;; Data Definitions
;; -------------------------------

(define-data-var contract-owner principal tx-sender)

(define-map eco-projects
  { id: uint }
  { 
    name: (string-ascii 50),
    verified: bool,
    total-staked: uint 
  }
)

(define-map user-stakes
  { staker: principal, project-id: uint }
  { 
    amount: uint, 
    reward: uint, 
    green-points: uint 
  }
)

(define-data-var project-counter uint u1)
(define-constant MINIMUM_STAKE u1000000) ;; 1 STX minimum

;; -------------------------------
;; Admin Functions
;; -------------------------------

(define-public (register-project (name (string-ascii 50)))
  (let ((pid (var-get project-counter)))
    (begin
      (asserts! (is-eq tx-sender (var-get contract-owner)) (err u100))
      (map-set eco-projects { id: pid } { name: name, verified: true, total-staked: u0 })
      (var-set project-counter (+ pid u1))
      (ok pid))))

;; -------------------------------
;; User Staking Functions
;; -------------------------------

(define-public (stake-for-project (project-id uint) (amount uint))
  (let (
    ;; Look up project or fail early
    (project (unwrap! (map-get? eco-projects { id: project-id }) (err u101)))
    ;; Look up existing stake or default to zero values
    (current-stake (default-to 
      { amount: u0, reward: u0, green-points: u0 } 
      (map-get? user-stakes { staker: tx-sender, project-id: project-id })))
  )
    (begin
      (asserts! (>= amount MINIMUM_STAKE) (err u102))
      
      ;; 1. Transfer STX from user to contract vault
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      ;; 2. Update user's stake record
      (map-set user-stakes
        { staker: tx-sender, project-id: project-id }
        { 
          amount: (+ (get amount current-stake) amount),
          reward: (get reward current-stake),
          green-points: (+ (get green-points current-stake) (/ amount u100000)) 
        })
      
      ;; 3. Update project's total cumulative staking
      (map-set eco-projects
        { id: project-id }
        (merge project { total-staked: (+ (get total-staked project) amount) }))
        
      (ok true))))

;; -------------------------------
;; Claiming Rewards & Unstaking
;; -------------------------------

(define-public (claim-reward (project-id uint))
  (let (
    (stake (unwrap! (map-get? user-stakes { staker: tx-sender, project-id: project-id }) (err u106)))
    (reward-amount (/ (get amount stake) u10)) ;; 10% reward calculation
  )
    (begin
      (asserts! (> reward-amount u0) (err u107))
      
      ;; 1. Contract vault transfers reward to user
      (try! (as-contract (stx-transfer? reward-amount (as-contract tx-sender) tx-sender)))
      
      ;; 2. Update stake record to increment total rewards claimed
      (map-set user-stakes
        { staker: tx-sender, project-id: project-id }
        (merge stake { reward: (+ (get reward stake) reward-amount) }))
      
      (ok reward-amount))))

(define-public (unstake (project-id uint))
  (let (
    (stake (unwrap! (map-get? user-stakes { staker: tx-sender, project-id: project-id }) (err u111)))
    (amount (get amount stake))
  )
    (begin
      ;; 1. Contract vault transfers principal back to user
      (try! (as-contract (stx-transfer? amount (as-contract tx-sender) tx-sender)))
      
      ;; 2. Decrease project total-staked global value
      (match (map-get? eco-projects { id: project-id })
        project (map-set eco-projects { id: project-id } 
                  (merge project { total-staked: (- (get total-staked project) amount) }))
        true)
      
      ;; 3. Wipe the user's specific stake entry
      (map-delete user-stakes { staker: tx-sender, project-id: project-id })
      (ok true))))

;; -------------------------------
;; Read-Only Functions
;; -------------------------------

(define-read-only (get-project (project-id uint))
  (map-get? eco-projects { id: project-id }))

(define-read-only (get-stake-info (user principal) (project-id uint))
  (map-get? user-stakes { staker: user, project-id: project-id }))

(define-read-only (get-total-projects)
  (var-get project-counter))