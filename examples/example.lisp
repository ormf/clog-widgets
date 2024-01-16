;;;  define the system and its dependencies:

(asdf:defsystem #:clog-widgets-example
  :depends-on (:clog-widgets))

;;; load depedencies

(asdf:operate 'asdf:load-op :clog-widgets-example)

;;; define the package and tell it to use all dependencies

(defpackage #:clog-widgets-example
  (:use #:cl #:clog #:cl-refs #:clog-widgets))

;; then select everything from here down to the end of the file and
;; complire/evaluate it.

(in-package :clog-widgets-example)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; utilities
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun rms->db (amp)
  (if (zerop amp)
      -100
      (* 20 (log amp 10))))

(defun db->rms (db)
  (expt 10 (/ db 20)))

(defun clip (val minvalue maxvalue)
  (min maxvalue (max minvalue val)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; initialization
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; define some variables

(setf *debug* nil)

(defparameter x-bang nil)
(defparameter x nil)
(defparameter x-db nil)
(defparameter radio nil)
(defparameter mslider nil)

;;;(trigger x-bang)

(progn
  (clear-bindings)
  (setf x (make-ref 0.5))
  (setf x-bang (make-bang (lambda () (set-val x 0))))
  (setf x-db
        (make-computed
         (lambda () (clip (round (rms->db (get-val x))) -40 0))
         (lambda (val) (%set-val x (clip (float (if (<= val -40) 0 (db->rms val))) 0 1)))))
  (setf radio
        (make-computed
         (lambda () (round (/ (+ 40 (get-val x-db)) 40/7)))
         (lambda (val) (%set-val x-db (- (float (* val 40/7)) 40)))))
  (setf mslider (make-array 8 :initial-contents (loop repeat 8 collect (make-ref 0))))
  (setf (aref mslider 0) x)
  nil)

;;; Define our CLOG application

(defun new-window (body)
  "On-new-window handler."
  (setf (title (html-document body)) "Gui Test")
  (let ((collection (create-collection body "1/2")))
    (create-o-numbox collection (bind-ref-to-attr x "value") 0 1 :precision 2)
    (create-o-knob collection (bind-ref-to-attr x "value") 0 1 0.01)
    (create-o-knob collection (bind-ref-to-attr x "value") 0 1 0.01)
    (create-o-knob collection (bind-ref-to-attr x-db "value") -40 0 1 :unit "dB" :precision 0)
    (create-o-bang collection (bind-ref-to-attr x-bang "bang"))
    (create-o-toggle collection (bind-ref-to-attr x "value"))
    (create-o-radio collection (bind-ref-to-attr radio "value")
                    :direction :up
                    :background '(("#444" "#888") ("orange"))
                    :labels (list (loop for num below 8 collect num)))
    (create-o-slider collection (bind-ref-to-attr x "value")
                     :background "transparent")
    (create-o-multislider collection (bind-ref-to-attr mslider "value")
                          :colors '("#8f8" "#f88" "#44f") :background "transparent")))

;;; We don't want to restart the server everytime when the new-window
;;; fun is canged thats why this proxy gets defined
(defun on-new-window (body)
  (new-window body))

;; Initialize the CLOG system with a boot file which contains the
;; static js files. For customized uses copy the "www" subdirectory of
;; the repository to your local project and adjust :static-root
;; accordingly
(defun start ()
  (clear-bindings) ;;; start from scratch
  (initialize #'on-new-window
              :port 8081
              :static-root (merge-pathnames "www/" (asdf:system-source-directory :clog-widgets))
              :boot-file "/start.html")
  ;; Open a browser to http://127.0.0.1:8080 - the default for CLOG apps
  (open-browser))

;;; (start) should start a webserver with some gui widgets that are
;;; connected

(start)