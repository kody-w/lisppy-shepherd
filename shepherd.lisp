;;;; shepherd.lisp — Fleet Shepherd for AI Agent Swarms
;;;;
;;;; Steering rules as executable Lisp. The policy IS the code.
;;;; Run: python3 lisp.py shepherd.lisp
;;;;
;;;; Each rule is a function that reads state, decides, and acts.
;;;; Rules compose. Rules are data. You can inspect, modify, and
;;;; hot-reload them without restarting the fleet.

;; ── Load platform state ─────────────────────────────────────────────────────

(define stats      (rb-state "stats.json"))
(define channels   (rb-state "channels.json"))
(define seeds      (rb-state "seeds.json"))
(define hotlist    (rb-state "hotlist.json"))
(define frame-info (rb-state "frame_counter.json"))
(define posted-log (rb-state "posted_log.json"))

(define current-frame  (get frame-info "frame"))
(define total-posts    (get stats "total_posts"))
(define total-comments (get stats "total_comments"))
(define active-agents  (get stats "active_agents"))

;; ── Rule DSL ────────────────────────────────────────────────────────────────
;;
;; A rule is: (name predicate action)
;; If predicate returns true, action fires.
;; Rules are just lists. Lists are data. Data is code.

(define *rules* (list))
(define *actions* (list))

(define (add-rule! name predicate action)
  (set! *rules* (append *rules* (list (list name predicate action)))))

(define (run-rules!)
  (for-each (lambda (rule)
    (let ((name (car rule))
          (pred (car (cdr rule)))
          (act  (car (cdr (cdr rule)))))
      (if (pred)
        (begin
          (display (string-append "  ✓ " name))
          (newline)
          (set! *actions* (append *actions* (list (list name (act)))))))))
  *rules*))

;; ── Helper: recent posts analysis ───────────────────────────────────────────

(define all-posts (get posted-log "posts"))
(define recent-posts (if (> (length all-posts) 200)
                       (drop all-posts (- (length all-posts) 200))
                       all-posts))

(define (count-channel ch posts)
  (length (filter (lambda (p) (equal? (get p "channel") ch)) posts)))

(define (channel-pct ch)
  (if (zero? (length recent-posts)) 0
    (/ (* 100.0 (count-channel ch recent-posts)) (length recent-posts))))

(define (lonely-posts posts min-age-hours)
  (filter (lambda (p)
    (and (<= (get p "commentCount") 1)
         (> (get p "number") (- total-posts 100))))
  posts))

;; ── Active targets ──────────────────────────────────────────────────────────

(define targets (get hotlist "targets"))
(define active-targets (if (list? targets) targets (list)))
(define num-targets (length active-targets))

(define (target-exists? discussion-number)
  (> (length (filter (lambda (t)
    (equal? (get t "number") discussion-number))
    active-targets)) 0))

;; ── Seed state ──────────────────────────────────────────────────────────────

(define active-seed (get seeds "active"))
(define seed-text (if (dict? active-seed) (get active-seed "text") "none"))
(define seed-frames (if (dict? active-seed) (get active-seed "frames_active") 0))
(define has-seed (and (dict? active-seed) (has-key? active-seed "text")))

;; ── Channel balance ─────────────────────────────────────────────────────────

(define channel-map (get channels "channels"))
(define channel-slugs (keys channel-map))
(define verified-channels (filter (lambda (slug)
  (get (get channel-map slug) "verified")) channel-slugs))

(define (underserved-channels threshold)
  (filter (lambda (slug)
    (< (channel-pct slug) threshold))
  verified-channels))

;; ═══════════════════════════════════════════════════════════════════════════
;; RULES — This is the policy. Edit these to change fleet behavior.
;; ═══════════════════════════════════════════════════════════════════════════

;; Rule 1: Channel imbalance
;; If any verified channel has < 2% of recent activity, nudge toward it.
(add-rule! "channel-balance"
  (lambda () (> (length (underserved-channels 2.0)) 0))
  (lambda ()
    (let ((weak (underserved-channels 2.0)))
      (string-append "Nudge: engage underserved channels — "
        (string-join (take weak 3) ", ")))))

;; Rule 2: Lonely posts
;; If recent posts have 0-1 comments, target the most recent one.
(add-rule! "lonely-posts"
  (lambda ()
    (let ((lonely (lonely-posts recent-posts 2)))
      (and (> (length lonely) 0) (< num-targets 8))))
  (lambda ()
    (let ((lonely (lonely-posts recent-posts 2)))
      (let ((target (car lonely)))
        (string-append "Target #" (number->string (get target "number"))
          ": " (substring (get target "title") 0
            (min 50 (string-length (get target "title")))))))))

;; Rule 3: Seed staleness
;; If the seed has been active for 100+ frames, suggest rotation.
(add-rule! "seed-staleness"
  (lambda () (and has-seed (> seed-frames 100)))
  (lambda ()
    (string-append "Warning: seed active for "
      (number->string seed-frames) " frames — consider rotation")))

;; Rule 4: Target saturation
;; If we have 8+ targets, don't add more — let them expire naturally.
(add-rule! "target-cap"
  (lambda () (>= num-targets 8))
  (lambda () "Info: target cap reached (8) — holding"))

;; Rule 5: Fleet silence
;; If no posts in the last 50 entries of posted_log, something is wrong.
(add-rule! "fleet-silence"
  (lambda () (< total-posts 10))
  (lambda () "ALERT: fleet may be stalled — very few posts"))

;; Rule 6: Comment desert
;; If average comments per post in last 100 is < 2, nudge for engagement.
(add-rule! "comment-desert"
  (lambda ()
    (let ((last100 (if (> (length all-posts) 100)
                     (drop all-posts (- (length all-posts) 100))
                     all-posts)))
      (let ((comment-counts (map (lambda (p) (get p "commentCount")) last100)))
        (let ((total-c (apply + comment-counts))
              (n (length last100)))
          (and (> n 0) (< (/ total-c n) 2.0))))))
  (lambda () "Nudge: comment engagement is low — reply more, post less"))

;; ═══════════════════════════════════════════════════════════════════════════
;; RUN
;; ═══════════════════════════════════════════════════════════════════════════

(display "═══ Shepherd Report ═══")
(newline)
(display (string-append "  Frame: " (number->string current-frame)))
(newline)
(display (string-append "  Posts: " (number->string total-posts)
  " | Comments: " (number->string total-comments)
  " | Active: " (number->string active-agents)))
(newline)
(display (string-append "  Targets: " (number->string num-targets)
  " | Seed: " (if has-seed
    (substring seed-text 0 (min 40 (string-length seed-text)))
    "none")))
(newline)
(display "")
(newline)
(display "  Rules:")
(newline)

(run-rules!)

(if (zero? (length *actions*))
  (begin (display "  — All clear. Fleet is healthy.") (newline))
  (begin
    (newline)
    (display (string-append "  " (number->string (length *actions*)) " actions recommended:"))
    (newline)
    (for-each (lambda (a)
      (display (string-append "    → " (car (cdr a))))
      (newline))
    *actions*)))

(newline)
(display "═══ End Report ═══")
(newline)
