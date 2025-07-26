;; royalty-splits.clar
;; Automated royalty split manager (owner-only for split changes)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Constants & Errors
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-constant CONTRACT-NAME "royalty-splits")

(define-constant MAX-RECIPIENTS u50)
(define-constant BPS-DENOM u10000) ;; 100% in basis points

;; Error codes
(define-constant ERR-NOT-AUTHORIZED         u100)
(define-constant ERR-WORK-NOT-FOUND         u101)
(define-constant ERR-INVALID-SPLIT-LENGTH   u102)
(define-constant ERR-INVALID-BPS-SUM        u103)
(define-constant ERR-NO-BALANCE             u104)
(define-constant ERR-STX-TRANSFER-FAILED    u105)
(define-constant ERR-RECIPIENT-ALREADY-SET  u106)
(define-constant ERR-EMPTY-RECIPIENTS       u107)
(define-constant ERR-NO-SPLIT-VERSION       u108)
(define-constant ERR-NOT-WORK-OWNER         u109)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Data Vars & Storage
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-data-var admin principal tx-sender)
(define-data-var work-id-counter uint u0)

(define-map works
  uint
  {
    owner: principal,
    meta: (string-utf8 256),
    split-version: uint
  }
)

(define-map splits
  {
    work-id: uint,
    version: uint,
    recipient: principal
  }
  {
    bps: uint
  }
)

(define-map split-index
  {
    work-id: uint,
    version: uint
  }
  {
    recipients: (list MAX-RECIPIENTS principal)
  }
)

(define-map balances
  {
    work-id: uint,
    recipient: principal
  }
  uint
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Utilities
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-read-only (get-admin) (var-get admin))

(define-private (is-admin (who principal))
  (is-eq who (var-get admin))
)

(define-private (require-admin)
  (asserts! (is-admin tx-sender) (err ERR-NOT-AUTHORIZED))
)

(define-read-only (get-work (work-id uint))
  (map-get? works work-id)
)

(define-private (require-work-owner (work-id uint))
  (let ((w (map-get? works work-id)))
    (asserts! (is-some w) (err ERR-WORK-NOT-FOUND))
    (let ((wo (get owner (unwrap-panic w))))
      (asserts! (is-eq tx-sender wo) (err ERR-NOT-WORK-OWNER))
    )
  )
)

(define-private (require-work-owner-or-admin (work-id uint))
  (let ((w (map-get? works work-id)))
    (asserts! (is-some w) (err ERR-WORK-NOT-FOUND))
    (let ((wo (get owner (unwrap-panic w))))
      (asserts! (or (is-eq tx-sender wo) (is-admin tx-sender)) (err ERR-NOT-WORK-OWNER))
    )
  )
)

(define-read-only (get-current-version (work-id uint))
  (match (map-get? works work-id)
    w (ok (get split-version w))
    (err ERR-WORK-NOT-FOUND)
  )
)

(define-read-only (get-split-recipients (work-id uint) (version uint))
  (match (map-get? split-index { work-id: work-id, version: version })
    s (ok (get recipients s))
    (err ERR-NO-SPLIT-VERSION)
  )
)

(define-read-only (get-split-bps (work-id uint) (version uint) (recipient principal))
  (match (map-get? splits { work-id: work-id, version: version, recipient: recipient })
    s (ok (get bps s))
    (err ERR-NO-SPLIT-VERSION)
  )
)

(define-read-only (get-claimable (work-id uint) (recipient principal))
  (default-to u0 (map-get? balances { work-id: work-id, recipient: recipient }))
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Admin
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (transfer-admin (new-admin principal))
  (begin
    (require-admin)
    (var-set admin new-admin)
    (ok true)
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Works
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (register-work (meta (string-utf8 256)))
  (let ((next-id (+ u1 (var-get work-id-counter))))
    (begin
      (var-set work-id-counter next-id)
      (map-set works next-id { owner: tx-sender, meta: meta, split-version: u0 })
      (ok next-id)
    )
  )
)

(define-public (transfer-work-ownership (work-id uint) (new-owner principal))
  (begin
    ;; owner OR admin can transfer ownership
    (require-work-owner-or-admin work-id)
    (let ((w (unwrap! (map-get? works work-id) (err ERR-WORK-NOT-FOUND))))
      (map-set works work-id
        {
          owner: new-owner,
          meta: (get meta w),
          split-version: (get split-version w)
        }
      )
      (ok true)
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Splits (OWNER-ONLY)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (set-splits
  (work-id uint)
  (recipients (list MAX-RECIPIENTS principal))
  (bps-list (list MAX-RECIPIENTS uint))
)
  (begin
    ;; *** changed: OWNER-ONLY (no admin override) ***
    (require-work-owner work-id)

    (asserts! (not (is-eq (len recipients) u0)) (err ERR-EMPTY-RECIPIENTS))
    (asserts! (is-eq (len recipients) (len bps-list)) (err ERR-INVALID-SPLIT-LENGTH))

    (let ((total-bps (fold bps-list u0 (lambda (b acc) (+ acc b)))))
      (asserts! (is-eq total-bps BPS-DENOM) (err ERR-INVALID-BPS-SUM))
    )

    (let (
          (w (unwrap! (map-get? works work-id) (err ERR-WORK-NOT-FOUND)))
          (new-version (+ u1 (get split-version w)))
         )
      ;; write splits
      (let ((ok? (fold recipients true
                       (lambda (recipient acc)
                         (let (
                               (pos (unwrap-panic (index-of recipients recipient)))
                               (bps (element-at? bps-list pos))
                              )
                           (begin
                             (map-set splits
                               { work-id: work-id, version: new-version, recipient: recipient }
                               { bps: (unwrap-panic bps) }
                             )
                             acc
                           )
                         )
                       ))))
        (map-set split-index { work-id: work-id, version: new-version } { recipients: recipients })
        (map-set works work-id
          {
            owner: (get owner w),
            meta: (get meta w),
            split-version: new-version
          }
        )
        (ok new-version)
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Deposits & Claims
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (deposit (work-id uint) (amount uint))
  (let (
        (w (unwrap! (map-get? works work-id) (err ERR-WORK-NOT-FOUND)))
        (version (get split-version (unwrap-panic (map-get? works work-id))))
       )
    (begin
      (unwrap! (stx-transfer? amount tx-sender (as-contract tx-sender)) (err ERR-STX-TRANSFER-FAILED))

      (let ((recipients (unwrap! (get-split-recipients work-id version) (err ERR-NO-SPLIT-VERSION))))
        (fold recipients true
          (lambda (rcp acc)
            (let (
                  (bps (unwrap! (get-split-bps work-id version rcp) (err ERR-NO-SPLIT-VERSION)))
                  (share (/ (* amount bps) BPS-DENOM))
                  (cur-bal (default-to u0 (map-get? balances { work-id: work-id, recipient: rcp })))
                 )
              (begin
                (map-set balances { work-id: work-id, recipient: rcp } (+ cur-bal share))
                acc
              )
            )
          )
        )
      )
      (ok true)
    )
  )
)

(define-public (claim (work-id uint))
  (let ((bal (get-claimable work-id tx-sender)))
    (begin
      (asserts! (> bal u0) (err ERR-NO-BALANCE))
      (map-set balances { work-id: work-id, recipient: tx-sender } u0)
      (unwrap! (stx-transfer? bal (as-contract tx-sender) tx-sender) (err ERR-STX-TRANSFER-FAILED))
      (ok bal)
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Views
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-read-only (get-work-meta (work-id uint))
  (match (map-get? works work-id)
    w (ok (get meta w))
    (err ERR-WORK-NOT-FOUND)
  )
)

(define-read-only (get-work-owner (work-id uint))
  (match (map-get? works work-id)
    w (ok (get owner w))
    (err ERR-WORK-NOT-FOUND)
  )
)

(define-read-only (get-active-version (work-id uint))
  (match (map-get? works work-id)
    w (ok (get split-version w))
    (err ERR-WORK-NOT-FOUND)
  )
)

(define-read-only (get-recipients-for-active-version (work-id uint))
  (match (get-active-version work-id)
    version (get-split-recipients work-id version)
    err err
  )
)

(define-read-only (get-split-for (work-id uint) (recipient principal))
  (let ((v (unwrap! (get-active-version work-id) (err ERR-WORK-NOT-FOUND))))
    (get-split-bps work-id v recipient)
  )
)
