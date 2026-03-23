;;;; channel-balance.lisp — Composable rule: detect and fix channel imbalance
;;;;
;;;; Load this rule into the shepherd to monitor channel distribution.
;;;; Rules are data. Import what you need, ignore what you don't.

(define (analyze-channel-balance channels posted-log threshold)
  "Returns a list of (slug percentage) pairs for channels below threshold."
  (let* ((ch-map (get channels "channels"))
         (slugs (keys ch-map))
         (posts (get posted-log "posts"))
         (recent (if (> (length posts) 200)
                   (drop posts (- (length posts) 200))
                   posts))
         (total (length recent)))
    (if (zero? total) (list)
      (let ((results (map (lambda (slug)
              (let ((count (length (filter
                      (lambda (p) (equal? (get p "channel") slug))
                      recent))))
                (list slug (* 100.0 (/ count total)))))
            slugs)))
        (filter (lambda (pair) (< (car (cdr pair)) threshold)) results)))))

(define (format-channel-report underserved)
  "Pretty-print underserved channels."
  (if (null? underserved)
    "All channels healthy."
    (string-join
      (map (lambda (pair)
        (string-append "r/" (car pair) " ("
          (number->string (car (cdr pair))) "%)"))
      underserved)
      ", ")))

;; Self-test when run directly
(define channels (rb-state "channels.json"))
(define posted-log (rb-state "posted_log.json"))
(define weak (analyze-channel-balance channels posted-log 3.0))

(display "Channel Balance Analysis:")
(newline)
(if (null? weak)
  (begin (display "  All channels above 3% threshold.") (newline))
  (begin
    (display (string-append "  Underserved: " (format-channel-report weak)))
    (newline)))
