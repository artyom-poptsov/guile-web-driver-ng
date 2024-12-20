;;; request.scm -- Guile-WebDriver-NG HTTP requests.

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

;; This module defines HTTP request-related procedures for working with
;; Selenium API.


;;; Code:

(define-module (web driver api)
  #:use-module (ice-9 match)
  #:use-module (json)
  #:use-module (web client)
  #:use-module (web request)
  #:use-module (web response)
  #:use-module (web driver log)
  #:use-module ((web driver error) #:prefix error:)
  #:use-module (web driver common)
  #:export (request
            session-command

            session-timeouts
            session-timeouts/implicit
            session-timeouts/page-load
            session-timeouts/script
            session-timeouts-set!
            session-url
            session-url-set!
            session-back!
            session-forward!
            session-refresh!
            session-title
            session-window
            session-window-delete!
            session-window-handles
            session-window-new!

            make-session-uri
            make-status-uri
            make-element-uri
            make-attribute-uri
            make-property-uri
            make-cookie-uri
            make-css-uri))



(define make-session-uri
  (case-lambda
    ((driver-uri)
     (format #f "~a/session" driver-uri))
    ((driver-uri session-id path)
     (format #f "~a/session/~a~a" driver-uri session-id path))))

(define (make-status-uri driver-uri)
  (format #f "~a/status" driver-uri))

(define (make-element-uri element path)
  (format #f "/element/~a~a" element path))

(define (make-attribute-uri name)
  (format #f "/attribute/~a" name))

(define (make-property-uri name)
  (format #f "/property/~a" name))

(define (make-cookie-uri name)
  (format #f "/cookie/~a" name))

(define (make-css-uri name)
  (format #f "/css/~a" name))


(define (request method uri body-scm)
  (log-debug "request: method: ~a uri: ~a"
             method
             uri)
  (let* ((body-string (scm->json-string body-scm))
         (body-bytevector (and body-scm
                               (request-body->bytevector body-string))))
    (call-with-values
        (lambda ()
          (http-request uri #:method method #:body body-bytevector))
      (lambda (response body)
        (let ((value (assoc-ref (json-bytevector->scm body) "value")))
          (log-debug "request: response-code: ~a" (response-code response))
          (if (equal? 200 (response-code response))
              value
              (let ((error (assoc-ref value "error"))
                    (message (assoc-ref value "message")))
                (error:web-driver-error
                 "~a ~a.\nRequest: ~a ~a\nBody: ~a\nError: ~a\nMessage: ~a\n"
                 (response-code response)
                 (response-reason-phrase response)
                 method
                 uri
                 body-string
                 error
                 message))))))))



(define* (session-command driver method path #:optional (body-scm '()))
  (log-debug "session-command: driver: ~s method: ~a path: ~a"
             driver
             method
             path)
  (match driver
    (('web-driver driver-uri session-id finalizer)
     (request method
              (make-session-uri driver-uri session-id path)
              body-scm))))


;; See <https://developer.mozilla.org/en-US/docs/Web/WebDriver/Timeouts>

(define %timeouts-path      "/timeouts")
(define %timeouts:page-load "pageLoad")
(define %timeouts:implicit  "implicit")
(define %timeouts:script    "script")

(define (session-timeouts driver)
  "Get session timeouts for a DRIVER."
  (session-command driver 'GET %timeouts-path #f))

(define (session-timeouts/page-load driver)
  "Get the session page load timeout for a DRIVER."
  (assoc-ref (session-timeouts driver) %timeouts:page-load))

(define (session-timeouts/implicit driver)
  "Get the session implicit timeout for a DRIVER."
  (assoc-ref (session-timeouts driver) %timeouts:implicit))

(define (session-timeouts/script driver)
  "Get the session script timeout for a DRIVER."
  (assoc-ref (session-timeouts driver) %timeouts:script))

(define* (session-timeouts-set! driver
                                #:key
                                page-load
                                implicit
                                script)
  (let* ((data '())
         (data (if page-load
                   (cons `(,%timeouts:page-load . ,page-load) data)
                   data))
         (data (if implicit
                   (cons `(,%timeouts:implicit . ,implicit) data)
                   data))
         (data (if script
                   (cons `(,%timeouts:script . ,script) data)
                   data)))
    (when (null? data)
      (error:web-driver-error "No timeouts provided"))
  (session-command driver 'POST %timeouts-path data)))



(define %url-path "/url")
(define %url:url  "url")

(define (session-url-set! driver url)
  "Set the session URL for a DRIVER."
  (session-command driver 'POST %url-path `((,%url:url . ,url))))

(define (session-url driver)
  "Get the session URL for a DRIVER."
  (session-command driver 'GET %url-path))

(define %back-path "/back")
(define (session-back! driver)
  "Go back one page."
  (session-command driver 'POST %back-path))

(define %forward-path "/forward")
(define (session-forward! driver)
  (session-command driver 'POST %forward-path))

(define %refresh-path "/refresh")
(define (session-refresh! driver)
  (session-command driver 'POST %refresh-path))

(define %title-path "/title")
(define (session-title driver)
  (session-command driver 'GET %title-path))



(define %window-path         "/window")
(define %window-handles-path "/window/handles")
(define %window-new-path     "/window/new")
(define (session-window driver)
  (session-command driver 'GET %window-path))

(define (session-window-delete! driver)
  (session-command driver 'DELETE %window-path '()))

(define (session-window-handles driver)
  (session-command driver 'GET %window-handles-path))

(define (session-window-new! driver type)
  (session-command driver
                   'POST
                   %window-new-path
                   `(("type" . ,type))))

;;; request.scm ends here.
