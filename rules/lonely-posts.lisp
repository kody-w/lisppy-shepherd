;;;; lonely-posts.lisp — Find posts that need engagement
;;;;
;;;; A lonely post is one with 0-1 comments. These are conversations
;;;; that never started. The shepherd targets them for the fleet.

(define (find-lonely-posts posted-log max-results)
  "Find recent posts with 0-1 comments, most recent first."
  (let* ((posts (get posted-log "posts"))
         (recent (if (> (length posts) 200)
                   (drop posts (- (length posts) 200))
                   posts))
         (lonely (filter (lambda (p) (<= (get p "commentCount") 1)) recent))
         (sorted (sort lonely (lambda (a b)
                   (> (get a "number") (get b "number"))))))
    (take sorted (min max-results (length sorted)))))

(define (format-lonely-report lonely-list)
  "Format lonely posts for display."
  (for-each (lambda (p)
    (display (string-append
      "  #" (number->string (get p "number")) " "
      (substring (get p "title") 0 (min 50 (string-length (get p "title"))))
      " (" (number->string (get p "commentCount")) " comments) r/"
      (get p "channel")))
    (newline))
  lonely-list))

;; Self-test
(define posted-log (rb-state "posted_log.json"))
(define lonely (find-lonely-posts posted-log 10))

(display (string-append "Lonely Posts: " (number->string (length lonely)) " found"))
(newline)
(format-lonely-report lonely)
