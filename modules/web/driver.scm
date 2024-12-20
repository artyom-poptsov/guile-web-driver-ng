;;; driver.scm -- Selenium WebDriver implementation.

;; Copyright (C) 2019-2024 Michal Herko <michal.herko@disroot.org>
;; Copyright (C) 2024 Artyom V. Poptsov <poptsov.artyom@gmail.com>
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; The program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with the program.  If not, see <http://www.gnu.org/licenses/>.


;;; Commentary:

;; The main module of Selenium WebDriver for GNU Guile.


;;; Code:

(define-module (web driver)
  #:use-module (ice-9 hash-table)
  #:use-module (ice-9 iconv)
  #:use-module (ice-9 match)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 threads)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-27)
  #:use-module (json)
  #:use-module (web client)
  #:use-module (web request)
  #:use-module (web response)
  #:use-module (web server)
  #:use-module (web driver common)
  #:use-module (web driver log)
  #:use-module ((web driver error) #:prefix error:)
  #:use-module (web driver element)
  #:use-module (web driver rect)
  #:use-module (web driver javascript)
  #:use-module (web driver cookie)
  #:use-module (web driver key)
  #:use-module (web driver api)
  #:export (open-web-driver))


(define %server-address INADDR_LOOPBACK)
(define %server-port    8080)
(define %server-backlog 16)


(define web-server #f)
(define current-handler #f)



(define-public (set-web-handler! handler)
  "Sets the current handler for the testing web server listening on
localhost:8080."
  (set! current-handler handler)
  (if (not web-server)
      ;; Start listening in calling thread, so the client can connect as soon
      ;; as this procedure returns.
      (let ((server-socket (socket PF_INET SOCK_STREAM 0)))
        (setsockopt server-socket SOL_SOCKET SO_REUSEADDR 1)
        (bind server-socket AF_INET %server-address %server-port)
        (listen server-socket %server-backlog)
        (set! web-server #t)
        (call-with-new-thread
         (lambda ()
           (run-server
            (lambda (request body) (current-handler request body))
            'http
            (list #:socket server-socket)))))))

(define (close-driver-pipe pipe)
  (kill (hashq-ref port/pid-table pipe) SIGTERM)
  (close-pipe pipe))

(define (capabilities->parameters capabilities)
  `(("capabilities" .
     (("firstMatch" . #(()))
      ("alwaysMatch" . ,(to-assoc-list capabilities))))))

(define (open* driver-uri finalizer capabilities)
  ;; wait until the new process starts listening
  (find
   (lambda (try)
     (catch #t
       (lambda () (request 'GET (make-status-uri driver-uri) #f) #t)
       (lambda (key . args) (usleep (* 10 1000)) #f)))
   (iota 100))
  ;; start a new session
  (catch #t
    (lambda ()
      (let* ((uri (make-session-uri driver-uri))
             (parameters (capabilities->parameters capabilities))
             (response (request 'POST uri parameters))
             (session-id (assoc-ref response "sessionId")))
        (list 'web-driver driver-uri session-id finalizer)))
    (lambda (key . args)
      (finalizer)
      (apply throw key args))))

(define (free-listen-port)
  "Find an unused port for server to listen on it"
  (let ((s (socket PF_INET SOCK_STREAM 0)))
    (listen s 1)
    (let ((port (array-ref (getsockname s) 2)))
      (close-port s)
      port)))


(define (launch-and-open command args capabilities)
  (let* ((port (free-listen-port))
         (pipe (apply open-pipe* OPEN_WRITE command (format #f "--port=~a" port)
                      args))
         (uri (format #f "http://localhost:~a" port)))
    (open* uri (lambda () (close-driver-pipe pipe)) capabilities)))

(define %chromedriver-command "chromedriver")
(define %chromedriver-arguments '("--silent"))
(define (open-chromedriver capabilities)
  "Start chromedriver instance with the specified CAPABILITIES."
  (log-info "open-chromedriver: capabilities: ~S" capabilities)
  (launch-and-open %chromedriver-command %chromedriver-arguments capabilities))

(define %geckodriver-command "geckodriver")
(define %geckodriver-arguments '("--log" "fatal"))
(define (open-geckodriver capabilities)
  "Start geckgodriver instance with the specified CAPABILITIES."
  (log-info "open-geckgodriver: capabilities: ~S" capabilities)
  (launch-and-open %geckodriver-command %geckodriver-arguments capabilities))


(set! *random-state* (random-state-from-platform))

(define (add-firefox-headless capabilities)
  (let* ((capabilities    (or capabilities '()))
         (firefox-options (or (assoc-ref "moz:firefoxOptions" capabilities)
                              '()))
         (args            (or (assoc-ref "args" firefox-options) #()))
         (args            (list->vector (append (vector->list args)
                                                (list "-headless"))))
         (firefox-options (assoc-set! firefox-options "args" args)))
    (assoc-set! capabilities "moz:firefoxOptions" firefox-options)))

(define *default-driver* (make-thread-local-fluid))

(define* (open-web-driver #:key browser url headless capabilities)
  (log-info "open-web-driver: browser: ~s url: ~a" browser url)
  (let ((driver
         (match (list browser url)
           ((#f (? identity url))
            (when headless
              (error:not-implemented
               "#:headless not supported when connecting to an url."))
            (open* url (const #f) capabilities))
           (((or #f 'chrome 'chromium 'chromedriver) #f)
            (when headless
              (error:not-implemented
               "#:headless not supported for chromedriver."))
            (open-chromedriver capabilities))
           (((or 'firefox 'geckodriver) #f)
            (open-geckodriver (if headless
                                  (add-firefox-headless capabilities)
                                  capabilities)))
           (('headless-firefox #f)
            (open-web-driver #:browser 'firefox
                             #:headless #t
                             #:capabilities capabilities))
           (((? identity browser) (? identity url))
            (error:invalid-arguments
             "Only one of #:browser and #:url may be specified"))
           ((browser #f)
            (error:unknown-browser browser)))))
    (unless (fluid-ref *default-driver*)
      (fluid-set! *default-driver* driver))
    driver))

(define-public (web-driver? object)
  (match object
    (('web-driver driver-uri session-id finalizer) #t)
    (else #f)))

(define-public (web-driver-open? driver)
  (match driver
    (('web-driver driver-uri session-id finalizer)
     (catch #t
       (lambda () (request 'GET (make-status-uri driver-uri) #f) #t)
       (lambda (key . args) #f)))))

(define (close driver)
  (match driver
    (('web-driver driver-uri session-id finalizer)
     (session-command driver 'DELETE "")
     (finalizer))))

(define-public (close-web-driver . args)
  (log-info "close-web-driver: ~S" args)
  (let ((driver (if (null? args) (fluid-ref *default-driver*) (car args))))
    (when driver
      (close driver))
    (when (equal? driver (fluid-ref *default-driver*))
      (fluid-set! *default-driver* #f))))

(define-public (call-with-web-driver proc)
  (define driver (open-web-driver))
  (catch #t
    (lambda ()
      (let ((r (with-fluid* *default-driver* driver (lambda () (proc driver)))))
        (close-web-driver driver) r))
    (lambda args
      (close-web-driver driver) (apply throw args))))

(define-public (get-default-driver)
  (if (not (fluid-ref *default-driver*))
      (fluid-set! *default-driver* (open-web-driver)))
  (fluid-ref *default-driver*))

(define-syntax define-public-with-driver
  (syntax-rules ()
    ((define-public-with-driver (proc-name driver args* ...) body* ...)
     (define-public (proc-name . args)
       (let ((proc (lambda* (driver args* ...) body* ...)))
         (if (and (pair? args) (web-driver? (car args)))
             (apply proc args)
             (apply proc (get-default-driver) args)))))))

;;; Timeouts

(define-public-with-driver (set-script-timeout driver #:optional timeout)
  (let ((value (match timeout ((? number? n) n) (#f 30000) (#:never 'null))))
    (session-timeouts-set! driver #:script value)))

(define-public-with-driver (get-script-timeout driver)
  (match (session-timeouts/script driver)
    ((? number? n) n)
    (#nil #:never)
    ('null #:never)))

(define-public-with-driver (set-page-load-timeout driver
                                                  #:optional
                                                  (timeout 300000))
  (session-timeouts-set! driver #:page-load timeout))

(define-public-with-driver (get-page-load-timeout driver)
  (session-timeouts/page-load driver))

(define-public-with-driver (set-implicit-timeout driver
                                                 #:optional
                                                 (timeout 0))
  (session-timeouts-set! driver #:implicit timeout))

(define-public-with-driver (get-implicit-timeout driver)
  (session-timeouts/implicit driver))

;;; Navigation

(define-public-with-driver (navigate-to driver url)
  (session-url-set! driver url))

(define-public-with-driver (current-url driver)
  (session-url driver))

(define-public-with-driver (back driver)
  (session-back! driver))

(define-public-with-driver (forward driver)
  (session-forward! driver))

(define-public-with-driver (refresh driver)
  (session-refresh! driver))

(define-public-with-driver (title driver)
  (session-title driver))

;;; Windows

(define (web-driver-window driver window-object)
  (list 'web-driver-window driver window-object))

(define-public-with-driver (current-window driver)
  (web-driver-window driver (session-window driver)))

(define-public-with-driver (close-window driver)
  (session-window-delete! driver)
  ;; XXX chromedriver would keep the deleted window currect,
  ;; causing all following navigation calls to fail.
  (switch-to (first (all-windows driver))))

(define-public-with-driver (all-windows driver)
  (map
   (lambda (window-object) (web-driver-window driver window-object))
   (vector->list (session-window-handles driver))))

(define (new-window driver type)
  (log-info "new-window: driver: ~s type: ~a" driver type)
  (web-driver-window
   driver
   (assoc-ref (session-window-new! driver type) "handle")))

(define-public-with-driver (open-new-window driver)
  (new-window driver "window"))

(define-public-with-driver (open-new-tab driver)
  (new-window driver "tab"))

(define-public-with-driver (switch-to driver target)
  (log-info "new-window: driver: ~s target: ~a" driver target)
  (match target
    (('web-driver-window driver handle)
     (session-command driver 'POST "/window" `(("handle" . ,handle))))
    (('web-driver-element driver element)
     (session-command driver 'POST "/frame"
                      `(("id" . (("element-6066-11e4-a52e-4f735466cecf"
                                  . ,element))))))
    ((? number? n)
     (session-command driver 'POST "/frame" `(("id" . ,n))))))

;;; Browsing Context

(define-public-with-driver (switch-to-parent driver)
  (session-command driver 'POST "/frame/parent"))

(define-public-with-driver (switch-to-window driver)
  (session-command driver 'POST "/frame" '(("id" . null))))

;;; Resizing and Positioning Windows

(define-public-with-driver (window-rect driver)
  (result->rect (session-command driver 'GET "/window/rect")))

(define-public-with-driver (set-window-position driver x y)
  (set-window-rect driver x y 'null 'null))

(define-public-with-driver (set-window-size driver width height)
  (set-window-rect driver 'null 'null width height))

(define-public-with-driver (set-window-rect driver #:rest args)
  (match args
    ((x y width height)
     (result->rect
      (session-command driver 'POST "/window/rect"
                       `(("x" . ,x)
                         ("y" . ,y)
                         ("width" . ,width)
                         ("height" . ,height)))))
    ((($ <rect> x y width height))
     (set-window-rect driver x y width height))))

(define-public-with-driver (minimize driver)
  (session-command driver 'POST "/window/minimize"))

(define-public-with-driver (maximize driver)
  (session-command driver 'POST "/window/maximize"))

(define-public-with-driver (full-screen driver)
  (session-command driver 'POST "/window/fullscreen"))

(define-public-with-driver (restore driver)
  (set-window-rect driver 'null 'null 'null 'null))

;;; Elements

(define (element-command element method path body-scm)
  (log-info "element-command: element: ~a method: ~a path: ~a"
            element
            method
            path)
  (match element
    (('web-driver-element driver element)
     (session-command driver
                      method
                      (make-element-uri element path)
                      body-scm))))

;;; Finding Elements

(define (find-element driver using value)
  (log-info "find-element: driver: ~a using: ~a value: ~a"
            driver
            using
            value)
  (web-driver-element driver
                      (session-command driver
                                       'POST "/element"
                                       `(("using" . ,using)
                                         ("value" . ,value)))))

(define (find-element-from driver from using value)
  (web-driver-element driver
                      (element-command from
                                       'POST "/element"
                                       `(("using" . ,using)
                                         ("value" . ,value)))))

(define (find-elements driver using value)
  (map
   (lambda (element-object) (web-driver-element driver element-object))
   (vector->list
    (session-command driver
                     'POST "/elements"
                     `(("using" . ,using) ("value" . ,value))))))

(define (find-elements-from driver from using value)
  (map
   (lambda (element-object) (web-driver-element driver element-object))
   (vector->list
    (element-command from
                     'POST "/elements"
                     `(("using" . ,using) ("value" . ,value))))))

(define-syntax define-finder
  (syntax-rules ()
    ((define-finder element-by elements-by using filter)
     (begin
       (define-public-with-driver (element-by driver value #:key (from #f))
         (if from
             (find-element-from driver from using (filter value))
             (find-element driver using (filter value))))
       (define-public-with-driver (elements-by driver value #:key (from #f))
         (if from
             (find-elements-from driver from using (filter value))
             (find-elements driver using (filter value))))))
    ((define-finder element-by elements-by using)
     (define-finder element-by elements-by using identity))))

(define-finder element-by-css-selector elements-by-css-selector "css selector")

;; TODO check that the id and class name are valid They should be at least one
;; character and not contain any space characters

(define-finder element-by-id elements-by-id
  "css selector" (lambda (id) (string-append "#" id)))

(define-finder element-by-class-name elements-by-class-name
  "css selector" (lambda (class-name) (string-append "." class-name)))

(define-finder element-by-tag-name elements-by-tag-name
  "tag name")

(define-finder element-by-link-text elements-by-link-text
  "link text")

(define-finder element-by-partial-link-text elements-by-partial-link-text
  "partial link text")

(define-finder element-by-xpath elements-by-xpath
  "xpath")

(define-public-with-driver (element-by-label-text driver text #:key from)
  (element-by-xpath driver
                    (format #f
                            "//input[@id = //label[normalize-space(text())=normalize-space(~s)]/@for] |
       //textarea[@id = //label[normalize-space(text())=normalize-space(~s)]/@for] |
       //label[normalize-space(text())=normalize-space(~s)]//input |
       //label[normalize-space(text())=normalize-space(~s)]//textarea"
                            text text text text)
                    #:from from))

(define-public-with-driver (element-by-partial-label-text driver text #:key from)
  (element-by-xpath driver
                    (format #f
                            "//input[@id = //label[contains(normalize-space(text()), normalize-space(~s))]/@for] |
       //textarea[@id = //label[contains(normalize-space(text()), normalize-space(~s))]/@for] |
       //label[contains(normalize-space(text()), normalize-space(~s))]//input |
       //label[contains(normalize-space(text()), normalize-space(~s))]//textarea"
                            text text text text)
                    #:from from))

(define-public-with-driver (active-element driver)
  (web-driver-element driver (session-command driver 'GET "/element/active")))

;;; Element State

(define-public (selected? element)
  (element-command element 'GET "/selected" #f))

(define-public (attribute element name)
  (fold-null (element-command element
                              'GET
                              (make-attribute-uri name)
                              #f)))

(define-public (property element name)
  (fold-null (element-command element
                              'GET
                              (make-property-uri name)
                              #f)))

(define-public (css-value element name)
  (element-command element
                   'GET
                   (make-css-uri name)
                   #f))

(define-public-with-driver (text driver #:optional element)
  (element-command (or element (element-by-tag-name "body"))
                   'GET
                   "/text"
                   #f))

(define-public (tag-name element)
  (element-command element 'GET "/name" #f))

(define-public (rect element)
  (result->rect
   (element-command element 'GET "/rect" #f)))

(define-public (enabled? element)
  (element-command element 'GET "/enabled" #f))

;;; Interacting with elements

(define (click-xpath text)
  (format #f
          "//a[normalize-space(text())=normalize-space(~s)] |
     //button[normalize-space(text())=normalize-space(~s)] |
     //input[(@type='button' or @type='submit' or @type='reset') and @value=~s] |
     //input[@id = //label[normalize-space(text())=normalize-space(~s)]/@for] |
     //label[normalize-space(text())=normalize-space(~s)]//input"
          text text text text text))

(define-public-with-driver (click driver target)
  (define (execute-click element)
    (element-command element 'POST "/click" '()))
  (cond
   ((element? target)
    (execute-click target))
   ((string? target)
    (execute-click (element-by-xpath driver (click-xpath target))))))

(define-public (clear element)
  (element-command element 'POST "/clear" '()))

(define-public-with-driver (send-keys driver target text)
  (element-command
   (cond
    ((element? target) target)
    ((string? target) (element-by-label-text driver target))
    (else (error:invalid-arguments
           "target of send-keys must be either element or string"
           target)))
   'POST "/value" `(("text" . ,text))))

(define-public-with-driver (choose-file driver target path)
  (send-keys driver target (canonicalize-path path)))

;;; Document

(define-public-with-driver (page-source driver)
  (session-command driver 'GET "/source"))

(define (execute driver path body arguments)
  (let ((js-args (map scm->javascript arguments)))
    (javascript->scm driver
                     (session-command
                      driver 'POST path
                      `(("script" . ,body)
                        ("args" . ,(list->vector js-args)))))))

(define-public-with-driver (execute-javascript driver body #:rest arguments)
  (execute driver "/execute/sync" body arguments))

(define-public-with-driver (execute-javascript-async driver body
                                                     #:rest arguments)
  (execute driver "/execute/async" body arguments))

;;; Cookies

(define-public-with-driver (get-all-cookies driver)
  (map
   parse-cookie
   (vector->list (session-command driver 'GET "/cookie"))))

(define-public-with-driver (get-named-cookie driver name)
  (parse-cookie (session-command driver 'GET (make-cookie-uri name))))

(define-public-with-driver
  (add-cookie driver
              #:key name value path domain secure http-only expiry same-site)
  (let* ((add (lambda (key value) (if value (list (cons key value)) '())))
         (args
          (append
           (add "name" name)
           (add "value" value)
           (add "path" path)
           (add "domain" domain)
           (add "secure" secure)
           (add "httpOnly" http-only)
           (add "expiry" expiry)
           (add "samesite" same-site)))
         (cookie `(("cookie" . ,args))))
    (session-command driver 'POST "/cookie" cookie)))

(define-public-with-driver (delete-named-cookie driver name)
  (session-command driver 'DELETE (make-cookie-uri name)))

(define-public-with-driver (delete-all-cookies driver)
  (session-command driver 'DELETE "/cookie"))

;;; Actions

(define-public (key-down key) (list 'key-down (key->unicode-char key)))

(define-public (key-up key) (list 'key-up (key->unicode-char key)))

(define-public mouse-move
  (lambda* (x y #:optional duration) (list 'mouse-move x y duration)))

(define (button-index button)
  (match button
    (#:left 0)
    (#:middle 1)
    (#:right 2)
    ((? number? n) n)))

(define-public (mouse-down button) (list 'mouse-down (button-index button)))

(define-public (mouse-up button) (list 'mouse-up (button-index button)))

(define-public (wait duration) (list 'wait duration))

(define-public (release-all) (list 'release-all))

(define pause-action `(("type" . "pause")))

(define-public-with-driver (perform driver #:rest actions)
  (define (send-actions key-actions mouse-actions)
    (session-command
     driver 'POST "/actions"
     `(("actions" .
        #((("type" . "key")
           ("id" . "keyboard0")
           ("actions" . ,(list->vector key-actions)))
          (("type" . "pointer")
           ("id" . "mouse0")
           ("actions" . ,(list->vector mouse-actions))))))))
  (define (release-actions)
    (session-command driver 'DELETE "/actions"))
  (define (perform-actions key-actions mouse-actions actions)
    (define (key-action action)
      (perform-actions (cons action key-actions)
                       (cons pause-action mouse-actions)
                       (cdr actions)))
    (define (mouse-action action)
      (perform-actions (cons pause-action key-actions)
                       (cons action mouse-actions)
                       (cdr actions)))
    (define (key-action/key-down unicode-char)
      (key-action `(("type" . "keyDown") ("value" . ,unicode-char))))
    (define (key-action/key-up unicode-char)
      (key-action `(("type" . "keyUp") ("value" . ,unicode-char))))
    (define (key-action/pause duration)
      (key-action `(("type" . "pause") ("duration" . ,duration))))
    (define (mouse-action/pointer-down button)
      (mouse-action `(("type" . "pointerDown") ("button" . ,button))))
    (define (mouse-action/pointer-up button)
      (mouse-action `(("type" . "pointerUp") ("button" . ,button))))
    (define* (mouse-action/move #:key x y duration)
      (mouse-action
       `(("type" . "pointerMove") ("x" . ,x) ("y" . ,y) ("origin" . "viewport")
         ("duration" . ,(or duration 0)))))
    (if
     (null? actions)
     (send-actions (reverse key-actions) (reverse mouse-actions))
     (match (car actions)
       (('key-down unicode-char)
        (key-action/key-down unicode-char))
       (('key-up unicode-char)
        (key-action/key-up unicode-char))
       (('mouse-down button)
        (mouse-action/pointer-down button))
       (('mouse-up button)
        (mouse-action/pointer-up button))
       (('mouse-move x y duration)
        (mouse-action/move #:x x #:y y #:duration duration))
       (('wait duration)
        (key-action/pause duration))
       (('release-all)
        (perform-actions key-actions mouse-actions '())
        (release-actions)
        (apply perform driver (cdr actions))))))
  (if (not (null? actions)) (perform-actions '() '() actions)))

;;; driver.scm ends here.
