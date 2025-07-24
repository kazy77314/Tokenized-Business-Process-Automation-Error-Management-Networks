;; Error Detection Engine
;; Automated detection and classification of business process errors

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INVALID_PROCESS (err u201))
(define-constant ERR_ERROR_NOT_FOUND (err u202))
(define-constant ERR_INVALID_SEVERITY (err u203))

;; Error severity levels
(define-constant SEVERITY_LOW u1)
(define-constant SEVERITY_MEDIUM u2)
(define-constant SEVERITY_HIGH u3)
(define-constant SEVERITY_CRITICAL u4)

;; Error categories
(define-constant CATEGORY_SYSTEM u1)
(define-constant CATEGORY_DATA u2)
(define-constant CATEGORY_PROCESS u3)
(define-constant CATEGORY_INTEGRATION u4)
(define-constant CATEGORY_PERFORMANCE u5)

;; Process monitoring data
(define-map monitored-processes
  { process-id: (string-ascii 50) }
  {
    owner: principal,
    name: (string-ascii 100),
    description: (string-ascii 500),
    error-threshold: uint,
    monitoring-active: bool,
    last-check: uint,
    total-errors: uint
  }
)

;; Detected errors
(define-map detected-errors
  { error-id: uint }
  {
    process-id: (string-ascii 50),
    error-type: (string-ascii 50),
    severity: uint,
    category: uint,
    description: (string-ascii 500),
    detection-time: uint,
    detector: principal,
    status: (string-ascii 20),
    assigned-manager: (optional principal)
  }
)

;; Error patterns for detection
(define-map error-patterns
  { pattern-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    detection-rules: (string-ascii 1000),
    severity-mapping: uint,
    category: uint,
    auto-assign: bool
  }
)

;; Error detection metrics
(define-map detection-metrics
  { process-id: (string-ascii 50), period: uint }
  {
    total-detections: uint,
    false-positives: uint,
    missed-errors: uint,
    accuracy-rate: uint,
    response-time: uint
  }
)

;; Global error counter
(define-data-var error-counter uint u0)

;; Register process for monitoring
(define-public (register-process
  (process-id (string-ascii 50))
  (name (string-ascii 100))
  (description (string-ascii 500))
  (error-threshold uint))

  (let ((owner tx-sender))
    (map-set monitored-processes
      { process-id: process-id }
      {
        owner: owner,
        name: name,
        description: description,
        error-threshold: error-threshold,
        monitoring-active: true,
        last-check: block-height,
        total-errors: u0
      }
    )
    (ok process-id)
  )
)

;; Detect and report error
(define-public (detect-error
  (process-id (string-ascii 50))
  (error-type (string-ascii 50))
  (severity uint)
  (category uint)
  (description (string-ascii 500)))

  (let ((error-id (+ (var-get error-counter) u1))
        (process-info (unwrap! (map-get? monitored-processes { process-id: process-id }) ERR_INVALID_PROCESS)))

    (asserts! (and (>= severity SEVERITY_LOW) (<= severity SEVERITY_CRITICAL)) ERR_INVALID_SEVERITY)
    (asserts! (get monitoring-active process-info) ERR_INVALID_PROCESS)

    ;; Create error record
    (map-set detected-errors
      { error-id: error-id }
      {
        process-id: process-id,
        error-type: error-type,
        severity: severity,
        category: category,
        description: description,
        detection-time: block-height,
        detector: tx-sender,
        status: "detected",
        assigned-manager: none
      }
    )

    ;; Update process error count
    (map-set monitored-processes
      { process-id: process-id }
      (merge process-info {
        total-errors: (+ (get total-errors process-info) u1),
        last-check: block-height
      })
    )

    ;; Increment global counter
    (var-set error-counter error-id)

    ;; Auto-assign if critical
    (if (is-eq severity SEVERITY_CRITICAL)
      (begin
        (match (auto-assign-error error-id)
          success (ok error-id)
          error (ok error-id))
      )
      (ok error-id)
    )
  )
)

;; Classify error using pattern matching
(define-public (classify-error (error-id uint) (pattern-id uint))
  (let ((error-info (unwrap! (map-get? detected-errors { error-id: error-id }) ERR_ERROR_NOT_FOUND))
        (pattern (unwrap! (map-get? error-patterns { pattern-id: pattern-id }) ERR_ERROR_NOT_FOUND)))

    (map-set detected-errors
      { error-id: error-id }
      (merge error-info {
        severity: (get severity-mapping pattern),
        category: (get category pattern),
        status: "classified"
      })
    )

    (ok pattern-id)
  )
)

;; Auto-assign critical errors
(define-private (auto-assign-error (error-id uint))
  ;; In a real implementation, this would query the manager registry
  ;; For now, assign to contract owner
  (let ((error-info (unwrap! (map-get? detected-errors { error-id: error-id }) ERR_ERROR_NOT_FOUND)))
    (map-set detected-errors
      { error-id: error-id }
      (merge error-info {
        assigned-manager: (some CONTRACT_OWNER),
        status: "assigned"
      })
    )
    (ok CONTRACT_OWNER)
  )
)

;; Update error status
(define-public (update-error-status (error-id uint) (new-status (string-ascii 20)))
  (let ((error-info (unwrap! (map-get? detected-errors { error-id: error-id }) ERR_ERROR_NOT_FOUND)))
    (asserts! (or (is-eq tx-sender (get detector error-info))
                  (is-eq tx-sender CONTRACT_OWNER)
                  (is-eq (some tx-sender) (get assigned-manager error-info))) ERR_UNAUTHORIZED)

    (map-set detected-errors
      { error-id: error-id }
      (merge error-info { status: new-status })
    )
    (ok new-status)
  )
)

;; Add error detection pattern
(define-public (add-detection-pattern
  (pattern-id uint)
  (name (string-ascii 100))
  (description (string-ascii 500))
  (detection-rules (string-ascii 1000))
  (severity-mapping uint)
  (category uint))

  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)

    (map-set error-patterns
      { pattern-id: pattern-id }
      {
        name: name,
        description: description,
        detection-rules: detection-rules,
        severity-mapping: severity-mapping,
        category: category,
        auto-assign: (is-eq severity-mapping SEVERITY_CRITICAL)
      }
    )
    (ok pattern-id)
  )
)

;; Get error details
(define-read-only (get-error (error-id uint))
  (map-get? detected-errors { error-id: error-id })
)

;; Get process monitoring status
(define-read-only (get-process-status (process-id (string-ascii 50)))
  (map-get? monitored-processes { process-id: process-id })
)

;; Get errors by process
(define-read-only (get-process-errors (process-id (string-ascii 50)))
  ;; This would require iteration in a real implementation
  ;; Return placeholder for now
  (ok (list { error-id: u1, severity: SEVERITY_HIGH }))
)

;; Calculate detection accuracy
(define-read-only (calculate-accuracy (process-id (string-ascii 50)) (period uint))
  (match (map-get? detection-metrics { process-id: process-id, period: period })
    metrics (let ((total (get total-detections metrics))
                  (false-pos (get false-positives metrics))
                  (missed (get missed-errors metrics)))
              (if (> total u0)
                (ok (/ (* (- total false-pos) u100) (+ total missed)))
                (ok u0)))
    (ok u0)
  )
)

;; Toggle process monitoring
(define-public (toggle-monitoring (process-id (string-ascii 50)))
  (let ((process-info (unwrap! (map-get? monitored-processes { process-id: process-id }) ERR_INVALID_PROCESS)))
    (asserts! (is-eq tx-sender (get owner process-info)) ERR_UNAUTHORIZED)

    (map-set monitored-processes
      { process-id: process-id }
      (merge process-info { monitoring-active: (not (get monitoring-active process-info)) })
    )
    (ok (not (get monitoring-active process-info)))
  )
)
