;;; proxy.scm -- Selenium WebDriver proxy.

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

;; This proxy can be used to intercept HTTP/HTTPS traffic between a browser
;; and a server and change HTTP headers.


;;; Code:

(define-module (web proxy)
  #:use-module (ice-9 threads)
  #:use-module (ice-9 receive)
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-11)
  #:use-module (srfi srfi-19)
  #:use-module (rnrs bytevectors)
  #:use-module (gnutls)
  #:use-module (oop goops)
  #:use-module (web http)
  #:use-module (web uri)
  #:use-module (web client)
  #:use-module (web driver log)
  #:use-module (web request)
  #:use-module (web response)
  #:use-module (web server)
  #:use-module (web proxy common)
  #:use-module (web proxy connection)
  #:use-module (web proxy interceptor)
  #:export (<proxy>
            proxy?
            proxy-port
            proxy-socket
            proxy-connections

            proxy-start!
            proxy-stop!

            make-key))


;; XXX: Don't parse "Date" headers because sometimes they are broken and don't
;;      match the RFC 822 definition.
;;      E.g.: "Date: Wed, 4 Oct 2023 20:2511 GMT"

(declare-opaque-header! "Date")



;; This class describes a proxy.
(define-class <proxy> ()
  ;; Proxy address to listen to.
  ;;
  ;; <number>
  (address
   #:init-value   INADDR_LOOPBACK
   #:init-keyword #:address
   #:getter       proxy-address)

  ;; Proxy TCP port to listen to.
  ;;
  ;; <number>
  (port
   #:init-value   8080
   #:init-keyword #:port
   #:getter       proxy-port)

  ;; Proxy socket.
  ;;
  ;; <socket>
  (proxy-socket
   #:init-value   #f
   #:getter       proxy-socket
   #:setter       proxy-socket-set!)

  ;; <number>
  (backlog
   #:init-value   1
   #:init-keyword #:backlog
   #:getter       proxy-backlog)

  ;; A hash table of proxy connections.
  ;;
  ;; <hash-table>
  (connections
   #:init-value   (make-hash-table 10)
   #:getter       proxy-connections)

  ;; <proxy-interceptor>
  (interceptor
   #:init-value   #f
   #:init-keyword #:interceptor
   #:getter       proxy-interceptor))



(define-method (%display (proxy <proxy>) (port <port>))
  (format port
          "#<proxy ~a:~a  ~a>"
          (proxy-address proxy)
          (proxy-port proxy)
          (object-address/hex-string proxy)))

(define-method (display (proxy <proxy>) (port <port>))
  (%display proxy port))

(define-method (write (proxy <proxy>) (port <port>))
  (%display proxy port))



(define-method (proxy? x)
  "Predicate.  Check if X is a <proxy> instance."
  (is-a? x <proxy>))



(define-method (make-key (host <string>) (port <number>))
  "Make a key for a <proxy> connections hash table."
  (string-append host ":" (number->string port)))

(define-method (proxy-connect! (proxy <proxy>)
                               (client <pair>)
                               (host <string>)
                               (tcp-port <number>))
  "Connection to a target @var{host} and @var{tcp-port} which was requested by a
@var{client}.  Return a new @code{<proxy-connection>} instance or @code{#f} on
errors."
  (let* ((connections (proxy-connections proxy))
         (s  (socket PF_INET SOCK_STREAM 0))
         (ai (car (getaddrinfo host))))
    (log-info "proxy-connect: Connecting to ~a:~a ..." host tcp-port)
    (catch #t
      (lambda ()
        (connect s
                 AF_INET
                 (sockaddr:addr (addrinfo:addr ai))
                 tcp-port)
        (log-info "proxy-connect: Connecting to ~a:~a ... done" host tcp-port)
        (let ((conn (make <proxy-connection>
                      #:host host
                      #:port tcp-port
                      #:client client
                      #:target-port s)))
          (log-info "proxy-connect: Connection: ~a" conn)
          (hash-set! connections
                     (make-key host tcp-port)
                     conn)
          conn))
      (lambda (key . args)
        (log-error "proxy-connect!: Error connecting to ~a:~a: ~a: ~a"
                   host
                   tcp-port
                   key
                   args)
        #f))))

(define-method (proxy-connection (proxy <proxy>)
                                 (host <string>)
                                 (port <number>))
  "Get a <proxy-connection> instance for a PROXY."
  (let ((connections (proxy-connections proxy)))
    (hash-ref connections (make-key host port))))

(define-method (proxy-disconnect! (proxy <proxy>)
                                  (host <string>)
                                  (port <number>))
  "Disconnect a PROXY from a HOST and a PORT.  Return value is undefined."
  (let ((conn (proxy-connection proxy host port)))
    (when conn
      (close (proxy-connection-target-port conn))
      (hash-remove! (proxy-connections proxy) (make-key host port)))))

(define-method (proxy-create-socket (proxy <proxy>))
  "Create a TCP/IP socket for a PROXY to listen to."
  (socket PF_INET SOCK_STREAM 0))

(define-method (proxy-listen! (proxy <proxy>))
  "Listen to incoming connections for a proxy.  Return value is undefined."
  (let ((s (proxy-create-socket proxy)))
    (proxy-socket-set! proxy s)
    (setsockopt s SOL_SOCKET SO_REUSEADDR 1)
    (bind s AF_INET (proxy-address proxy) (proxy-port proxy))
    (listen s (proxy-backlog proxy))))

(define-method (proxy-intercept (proxy <proxy>)
                                (connection <proxy-connection>))
  "Intercept a @var{connection} traffic coming through a @var{proxy} with the
proxy interceptor."
  (log-debug "proxy-intercept: proxy: ~a, conn: ~a" proxy connection)
  (let ((client-socket (proxy-connection-client-port connection))
        (interceptor   (proxy-interceptor proxy)))
    (log-debug "proxy-intercept: interceptor: ~a" interceptor)
    (while (not (port-closed? client-socket))
      (proxy-interceptor-run interceptor connection))))

(define-method (proxy-intercept (proxy <proxy>)
                                (connection <proxy-connection>)
                                request
                                body)
  "Intercept a @var{connection} traffic coming through a @var{proxy} with the
proxy interceptor."
  (log-debug "proxy-intercept: proxy: ~a, conn: ~a, req: ~a"
             proxy
             connection
             request)
  (let ((interceptor (proxy-interceptor proxy)))
    (log-debug "proxy-intercept: interceptor: ~a" interceptor)
    (proxy-interceptor-run interceptor connection request body)))

(define-method (transfer-data (proxy <proxy>) (connection <proxy-connection>))
  "Transfer data through a PROXY."
  (define (client-to-destination client-socket)
    (let ((buf (make-bytevector 1)))
      (call-with-new-thread
       (lambda ()
         (let loop ((tx 0))
           (catch #t
             (lambda ()
               (if (not (port-closed? client-socket))
                   (let ((count (recv! client-socket buf)))
                     (when (> count 0)
                       (send (proxy-connection-target-port connection) buf)
                       (loop (+ tx count))))
                   (log-info "transfer-data: ~a tx ~a byte(s)"
                             connection
                             tx)))
             (lambda (key . args)
               (log-error "~a: ~a" key args)
               (log-info "transfer-data: ~a tx ~a byte(s)"
                         connection
                         tx)
               (close client-socket))))))))

  (define (destination-to-client client-socket)
    (let ((buf (make-bytevector 1)))
      (let loop ((rx 0))
        (catch #t
          (lambda ()
            (if (not (port-closed? (proxy-connection-target-port connection)))
                (let ((count (recv! (proxy-connection-target-port connection)
                                    buf)))
                  (when (> count 0)
                    (send client-socket buf)
                    (loop (+ rx count))))
                (log-info "transfer-data: ~a rx ~a byte(s)"
                          connection
                          rx)))
          (lambda (key . args)
            (log-error "~a: ~a" key args)
            (log-info "transfer-data: ~a rx ~a byte(s)"
                      connection
                      rx)
            (close client-socket))))))

  (let ((client-socket (proxy-connection-client-port connection)))
    (client-to-destination client-socket)
    (destination-to-client client-socket)))

(define (forward-request proxy connection request body)
  (let* ((client-socket (proxy-connection-client-port connection))
         (headers       (request-headers request))
         (method        (request-method request))
         (uri           (request-uri request))
         (host          (symbol->string (uri-scheme uri)))
         (port          (string->number (uri-path uri)))
         (meta          (request-meta request))
         (version       (request-version request)))
    (receive (response response-body)
        (http-request uri
                      #:method  method
                      #:body    body
                      #:version version
                      #:headers headers
                      #:decode-body? #f)
      (let ((r (build-response #:version       (response-version response)
                               #:code          (response-code response)
                               #:reason-phrase (response-reason-phrase response)
                               #:headers       (response-headers response)
                               #:port          client-socket)))
        (write-response r client-socket)
        (force-output client-socket)
        (when response-body
          (write-response-body r response-body))
        (force-output client-socket)))))

(define (handle-request proxy client)
  "Accept a CONNECT request on PROXY from a CLIENT."
  (let* ((client-socket (car client))
         (request       (read-request client-socket))
         (body          (read-request-body request))
         (method        (request-method request)))
    (log-info "handle-request: request: ~a" request)
    (log-info "handle-request: method: ~a" method)
    (case method
      ((CONNECT)
       (let* ((uri        (request-uri request))
              (host       (symbol->string (uri-scheme uri)))
              (port       (string->number (uri-path uri)))
              (connection (proxy-connect! proxy client host port)))
         (if connection
             (let ((response (build-response)))
               (write-response response client-socket)
               (force-output client-socket)
               (if (proxy-interceptor proxy)
                   (proxy-intercept proxy connection)
                   (transfer-data proxy connection)))
             (let ((response (build-response
                              #:code 502
                              #:reason-phrase
                              (format #f
                                      "Could not connect to ~a:~a"
                                      host
                                      port))))
               (log-error "handle-request: Could not connect to ~a:~a" host port)
               (write-response response client-socket)
               (force-output client-socket)))))
      (else
       (let* ((uri     (request-uri request))
              (host    (uri-host uri))
              (scheme  (uri-scheme uri))
              (port    (or (uri-port uri)
                           (case scheme
                             ((http)
                              80)
                             ((https)
                              443)
                             (else
                              (error "Unknown scheme" scheme)))))
              (connection (proxy-connect! proxy client host port)))
         (if (proxy-interceptor proxy)
             (proxy-intercept proxy connection request body)
             (forward-request proxy connection request body)))))))

(define-method (proxy-handle-client (proxy <proxy>) client)
  "Handle a TCP/IP CLIENT connected to a PROXY."
  (log-info "proxy-handle-client: New client: ~a" client)
  (call-with-new-thread
   (lambda ()
     (handle-request proxy client))))

(define-method (proxy-start! (proxy <proxy>))
  "Start a PROXY.  If the PROXY is already started the procedure throws an error."
  (when (proxy-socket proxy)
    (log-error "Proxy already started: ~a" proxy)
    (error "Proxy already started" proxy))
  (log-info "proxy-start!: Starting ~a ..." proxy)
  (proxy-listen! proxy)
  (call-with-new-thread
   (lambda ()
     (while (not (port-closed? (proxy-socket proxy)))
       (catch #t
         (lambda ()
           (let ((client (accept (proxy-socket proxy))))
             (log-info "proxy-start!: Client accepted: ~a"
                       client)
             (proxy-handle-client proxy client)))
         (lambda (key . args)
           (log-error "proxy-start!: ~a: ~a" key args))))
     (log-info "proxy-start!: Port closed."))))

(define-method (proxy-stop! (proxy <proxy>))
  "Stop a PROXY."
  (hash-for-each (lambda (key connection)
                   (proxy-connection-close! connection))
                 (proxy-connections proxy))
  (close (proxy-socket proxy)))

;;; proxy.scm ends here.
