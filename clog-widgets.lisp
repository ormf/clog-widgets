;;;; clog-widgets.lisp
;;;
;;; **********************************************************************
;;; Copyright (c) 2024 Orm Finnendahl
;;; <orm.finnendahl@selma.hfmdk-frankfurt.de>
;;;
;;; Revision history: See git repository.
;;;
;;; This program is free software; you can redistribute it and/or
;;; modify it under the terms of the Gnu Public License, version 2 or
;;; later. See https://www.gnu.org/licenses/gpl-2.0.html for the text
;;; of this agreement.
;;; 
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;;; GNU General Public License for more details.
;;;
;;; **********************************************************************

(in-package #:clog-widgets)

;;; clog extension to integrate reactive with clog.
;;;
;;; A binding establishes a relation between a ref object <refvar> and
;;; an attribute name <attr> using #'bind-ref-to-attr. This function
;;; creates the binding and calls the watch function, which creates a
;;; ref object containing the refvar in its update fn. Adding a clog
;;; element to the b-elist of the binding will result in an update of
;;; the attribue whenever the state of the <refvar> object changes.
;;;
;;; Note: There is no handle to the update function created by watch,
;;; but the watch function returns an unwatch function which removes
;;; the ref object created in #'bind-ref-to-attr and all its
;;; dependencies. This function is stored in the unwatch slot of the
;;; binding to facilitate unbinding.

; On initialization of a clog gui element, a
; the element is pushed to the elist of the binding.

(defvar *bindings* (make-hash-table :test 'equal))

(defun clear-bindings ()
  (maphash (lambda (name binding) ;;; remove watch functions
             (declare (ignore name))
             (funcall (b-unwatch binding)))
           *bindings*)
  (setf *bindings* (make-hash-table :test 'equal)))

(defclass binding ()
  ((ref :initarg :ref :accessor b-ref)
   (attr :initarg :attr :accessor b-attr)
   (elist :initarg :elist :initform '() :accessor b-elist)
   (map :initarg :map :accessor b-map)
   (unwatch :initarg :unwatch :initform '() :accessor b-unwatch)))

(defun binding-name (refvar attr)
  (concatenate 'string (ref-id refvar) "-" attr))

(defun make-binding (&rest args)
  (apply #'make-instance 'binding args))

;;; (trigger x-bang)

(defgeneric define-watch (refvar attr new)
  (:method ((refvar ref-object) attr new)
    (watch ;;; watch registers an on-update function
     (lambda ()
       (let ((val (get-val refvar)))
         (if *debug* (format t "~&~%elist: ~a~%" (b-elist new)))
         (if *debug* (format t "~&~%seen: ~a~%" (obj-print *refs-seen*)))
         (dolist (obj (b-elist new)) ;;; iterate through all bound html elems
           (unless (member obj *refs-seen*)
             (if *debug* (format t "~&~%watch update: ~a~%-> ~a ~a~%" (obj-print *refs-seen*) obj val))
             (push obj *refs-seen*)
             (setf (attribute obj attr) val)))))))
  (:method ((refvar bang-object) attr new)
    (watch ;;; watch registers an on-update function
     (lambda ()
       (let ((val (get-val refvar))) ;; we read val only to register
                                      ;; the watch function in the
                                      ;; listeners of the bang
       (declare (ignore val))
       (if *debug* (format t "~&~%elist: ~a~%" (b-elist new)))
       (if *debug* (format t "~&~%seen: ~a~%" (obj-print *refs-seen*)))
       (dolist (obj (b-elist new)) ;;; iterate through all bound html elems
         (unless (member obj *refs-seen*)
           (if *debug* (format t "~&~%watch update: ~a~%-> ~a~%" (obj-print *refs-seen*) obj))
           (push obj *refs-seen*)
           (js-execute obj (format nil "~A.bang()" (script-id obj)))
           )))))))

(defgeneric bind-ref-to-attr (refvar attr &optional map)
  (:method ((refvar ref-object-super) attr &optional (map (lambda (val) val)))
    (let ((name (binding-name refvar attr)))
      (or (gethash name *bindings*) ;;; or returns the first non-nil argument and skips evaluating the rest of its args.
          (let ((new (make-binding :ref refvar :attr attr :map map)))
            (setf (b-unwatch new) (define-watch refvar attr new))
            (setf (gethash name *bindings*) new)))))
  (:method ((refvar-array simple-array) attr &optional (map (lambda (val) val)))
    (let ((binding-array (make-array (length refvar-array))))
      (loop for refvar across refvar-array
            for idx from 0
            do (setf (aref binding-array idx)
                     (let ((name (binding-name refvar attr)))
                       (or (gethash name *bindings*) ;;; or returns the first non-nil argument and skips evaluating the rest of its args.
                           (let ((new (make-binding :ref refvar :attr attr :map map)))
                             (setf (b-unwatch new) (define-watch refvar attr new))
                             (setf (gethash name *bindings*) new)))))
            finally (return binding-array))))
  (:documentation "bind a ref (or an array of refs) to an attr of a html element. This
will establish a watch function, which will automatically set the attr
of all registered html elements on state change of the
refvar. Registering html elements is done by pushing the html element
to the b-elist slot of the binding (normally done in the creation
function of the html element)."))

 ;;; (setf (gethash...) ) returns the value which got set (new in this case).

(defun obj-print (seq)
  (format nil "(~{~a~^ ~})"
          (mapcar (lambda (x)
                    (cond
                      ((functionp x) (format nil "<function {~a}>" (sb-kernel:get-lisp-obj-address x)))
                      (:else (format nil "~a" x))))
                  seq)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                       clog part                                          ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


; little clog extension to allow simple data transport js -> lisp

(defparameter *data-event-script*
  "+ JSON.stringify(data)")

(defun parse-data-event (data)
  (yason:parse data))

(defmethod set-on-data ((obj clog-obj) handler)
   (clog::set-event
    obj "data"
    (when handler
      (lambda (data)
        (unless (string= data "undefined")
          (funcall handler obj (parse-data-event data)))))
    :call-back-script *data-event-script*))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; creation functions for gui widgets
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; custom html element also defined in js:

(defun create-o-knob (parent binding min max step &key (unit "") (precision 2))
  (let ((var (b-ref binding))
        (attr (b-attr binding))
        (element (create-child
                  parent
                  (format nil "<o-knob min=\"~a\" max=\"~a\" step=\"~a\" value=\"~a\" precision=\"~a\" unit=\"~a\"></o-knob>"
                          min max step (get-val (b-ref binding)) precision unit)))) ;;; the get-val automagically registers the ref
    (push element (b-elist binding)) ;;; register the browser page's html elem for value updates.
    (set-on-data element ;;; react to changes in the browser page
                 (lambda (obj data)
		   (declare (ignore obj))
                   (let ((*refs-seen* (list element)))
                     (if *debug* (format t "~&~%clog event from ~a: ~a~%" element
                                         (or (if (gethash "close" data) "close")
                                             (gethash attr data))))
                     (if (gethash "close" data)
                         (progn
                           (format t "closing knob~%")
                           (setf (b-elist binding) (remove element (b-elist binding)))) ;;; cleanup: unregister elem.
                         (%set-val var (gethash attr data)) ;; otherwise set value.
                         ))))))

(defun create-o-numbox (parent binding min max &key (precision 2))
  (let ((var (b-ref binding))
        (attr (b-attr binding))
        (element (create-child
                  parent
                  (format nil "<input is=\"o-numbox\" min=\"~a\" max=\"~a\" value=\"~a\" precision=\"~a\">"
                          min max (get-val (b-ref binding)) precision)))) ;;; the get-val automagically registers the ref
    (push element (b-elist binding)) ;;; register the browser page's html elem for value updates.
    (set-on-data element ;;; react to changes in the browser page
                 (lambda (obj data)
		   (declare (ignore obj))
                   (let ((*refs-seen* (list element)))
                     (if *debug* (format t "~&~%clog event from ~a: ~a~%" element
                                         (or (if (gethash "close" data) "close")
                                             (gethash attr data))))
                     (if (gethash "close" data)
                         (progn
                           (format t "closing numbox~%")
                           (setf (b-elist binding) (remove element (b-elist binding)))) ;;; cleanup: unregister elem.
                         (%set-val var (gethash attr data))))))))

(defmacro option-main (option)
  `(if (listp ,option)
       (first ,option)
       ,option))

(defmacro option-second (option)
  `(if (listp ,option)
       (or (second ,option) (first ,option))
       ,option))

(defun opt-format-attr (attr val)
  (when val (format nil "~a='~(~a~)'" attr val)))

(defun create-o-bang (parent binding &key label (background '("transparent" "orange")) color flash-time)
  (let ((var (b-ref binding))
        (attr (b-attr binding))
        (element (create-child
                  parent
                  (format nil "<o-bang ~{~@[~a ~]~}>~@[~a~]</o-bang>"
                          (list
                           (opt-format-attr "label-off" (option-main label))
                           (opt-format-attr "label-on" (option-second label))
                           (opt-format-attr "background-off" (option-main background))
                           (opt-format-attr "background-on" (option-second background))
                           (opt-format-attr "color-off" (option-main color))
                           (opt-format-attr "color-on" (option-second color))
                           (opt-format-attr "flash-time" flash-time))
                          (or (option-main label) "")))))
    (push element (b-elist binding)) ;;; register the browser page's html elem for value updates.
    (set-on-data element ;;; react to changes in the browser page
                 (lambda (obj data)
                   (let ((*refs-seen* (list element)))
                     (if *debug* (format t "~&~%clog event from ~a: ~a~%" element
                                         (or (if (gethash "close" data) "close")
                                             (gethash attr data))))
                     (cond ((gethash "close" data)
                            (progn
                              (format t "closing bang~%")
                              (setf (b-elist binding) (remove element (b-elist binding))))) ;;; cleanup: unregister elem.
                           ((gethash "bang" data)
                            (let ((*refs-seen* (list obj)))
                              (%trigger var)))))))))

(defun array->attr (arr)
  (format nil "[~{~a~^, ~}]" (coerce arr 'list)))

(defun create-o-toggle (parent binding &key label (background '("transparent" "orange")) color flash-time values)
  (let* ((var (b-ref binding))
         (attr (b-attr binding))
         (element (create-child
                   parent
                   (format nil "<o-toggle ~{~@[~a ~]~}>~@[~a~]</o-toggle>"
                           (list
                            (opt-format-attr "value" (get-val var))
                            (opt-format-attr "label-off" (option-main label))
                            (opt-format-attr "label-on" (option-second label))
                            (opt-format-attr "background-off" (option-main background))
                            (opt-format-attr "background-on" (option-second background))
                            (opt-format-attr "color-off" (option-main color))
                            (opt-format-attr "color-on" (option-second color))
                            (opt-format-attr "flash-time" flash-time)
                            (opt-format-attr "value-off" (or (first values) 0))
                            (opt-format-attr "value-on" (or (second values) 1)))
                           (or (option-main label) "")))))
    (push element (b-elist binding)) ;;; register the browser page's html elem for value updates.
    (set-on-data element ;;; react to changes in the browser page
                 (lambda (obj data)
                   (declare (ignore obj))
                   (let ((*refs-seen* (list element)))
                     (if *debug* (format t "~&~%clog event from ~a: ~a~%" element
                                         (or (if (gethash "close" data) "close")
                                             (gethash attr data))))
                     (cond ((gethash "close" data)
                            (progn
                              (format t "closing toggle~%")
                              (setf (b-elist binding) (remove element (b-elist binding)))))
                           (t (%set-val var (read-from-string (gethash attr data))))
                           ))))))

(defun create-o-radio (parent binding &key labels label (background '("transparent" "orange")) color flash-time values
                                        (num 8) (direction :right))
  (declare (type (member :up :right :down :left) direction))
  (let* ((var (b-ref binding))
         (attr (b-attr binding)) ;;; format nil "~{~a~^,~}"
         (element (create-child
                   parent
                   (format nil "<o-radio ~{~@[~a ~]~}>~@[~a~]</o-radio>"
                           (list
                            (opt-format-attr "value" (round (get-val var)))
                            (opt-format-attr "label-off" (if (option-main labels)
                                                             (format nil "~{~a~^,~}" (option-main labels))))
                            (opt-format-attr "label-on" (if (option-second labels)
                                                            (format nil "~{~a~^,~}" (option-second labels))))
                            (opt-format-attr "background-off" (if (option-main background)
                                                                  (format nil "~{~a~^,~}" (option-main background))))
                            (opt-format-attr "background-on" (if (option-second background)
                                                                 (format nil "~{~a~^,~}" (option-second background))))
                            (opt-format-attr "color-off" (if (option-main color)
                                                             (format nil "~{~a~^,~}" (option-main color))))
                            (opt-format-attr "color-on" (if (option-second color)
                                                            (format nil "~{~a~^,~}" (option-second color))))
                            (opt-format-attr "flash-time" flash-time)
                            (opt-format-attr "value-off" (or (first values) 0))
                            (opt-format-attr "value-on" (or (second values) 1))
                            (opt-format-attr "data-num" (or num 8))
                            (opt-format-attr "direction" direction))
                           (or (option-main label) "")))))
    (push element (b-elist binding)) ;;; register the browser page's html elem for value updates.
    (set-on-data element ;;; react to changes in the browser page
                 (lambda (obj data)
                   (declare (ignore obj))
                   (let ((*refs-seen* (list element)))
                     (if *debug* (format t "~&~%clog event from ~a: ~a~%" element
                                         (or (if (gethash "close" data) "close")
                                             (gethash attr data))))
                     (cond ((gethash "close" data)
                            (progn
                              (format t "closing radio~%")
                              (setf (b-elist binding) (remove element (b-elist binding)))))
                           (t (%set-val var (gethash attr data)))))))))

(defun format-style (css)
  (format nil "style=\"~@[~{~(~A~): ~(~a~);~}~]\"" css))


(defun create-o-slider (parent binding &key (direction :up) (min 0) (max 1)
                                         label background thumb-color bar-color
                                         (mapping :lin) (clip-zero nil)
                                         (width "1em") (height "8em") padding css)
  (declare (type (member :lin :log) mapping)
           (type (member :up :right :down :left) direction))
  (let* ((var (b-ref binding))
         (attr (b-attr binding)) ;;; format nil "~{~a~^,~}"
         (element (create-child
                   parent
                   (format nil "<o-slider ~{~@[~a ~]~}>~@[~a~]</o-slider>"
                           (list
                            (format-style (append `(:width ,width :height ,height :padding ,padding) css))
                            (opt-format-attr "direction" direction)
                            (opt-format-attr "value" (float (get-val var) 1.0))
                            (opt-format-attr "min" min)
                            (opt-format-attr "max" max)
                            (opt-format-attr "label" label)
                            (opt-format-attr "background" (or background "white"))
                            (opt-format-attr "thumb-color" (or thumb-color "black"))
                            (opt-format-attr "bar-color" (or bar-color "transparent") )
                            (opt-format-attr "mapping" mapping )
                            (opt-format-attr "clip-zero" clip-zero ))
                           (or (option-main label) "")))))
    (push element (b-elist binding)) ;;; register the browser page's html elem for value updates.
    (set-on-data element ;;; react to changes in the browser page
                 (lambda (obj data)
                   (declare (ignore obj))
                   (let ((*refs-seen* (list element))) ;;; set context for %set-val below
                     (if *debug* (format t "~&~%clog event from ~a: ~a~%" element
                                         (or (if (gethash "close" data) "close")
                                             (gethash attr data))))
                     (cond ((gethash "close" data)
                            (progn
                              (format t "closing slider~%")
                              (setf (b-elist binding) (remove element (b-elist binding)))))
                           (t (%set-val var (gethash attr data)))))))))

;;; min, max, mapping, clip-zero, thumb-color, bar-color

(defun create-o-multislider (parent binding-array
                             &key (direction :up) (value 0) (min 0) (max 1)
                               label background colors (thumb-color "transparent")
                               (mapping :lin) (clip-zero nil))
  (declare (type (member :lin :log) mapping)
           (type (member :up :right :down :left) direction))
  (let* ((num-sliders (length binding-array))
         (element (create-child
                      parent
                      (format nil "<o-multislider ~{~@[~a ~]~}>~@[~a~]</o-multislider>"
                              (list
                               (opt-format-attr "num-sliders" num-sliders)
                               (opt-format-attr "direction" direction)
                               (opt-format-attr "value" value)
                               (opt-format-attr "min" min)
                               (opt-format-attr "max" max)
                               (opt-format-attr "label" label)
                               (opt-format-attr "background" (or background "white"))
                               (opt-format-attr "colors" (if colors (format nil "~{~a~^,~}" colors)))
                               (opt-format-attr "mapping" mapping )
                               (opt-format-attr "clip-zero" clip-zero ))
                              (or (option-main label) "")))))
    (loop for binding across binding-array
          collect (create-o-slider element binding :thumb-color (or thumb-color "transparent") :direction direction))
    (execute element (format nil "initSliders(~a)" num-sliders) )
;;    (js-execute element (format nil "slider(~A, { \"thumb\": '~(~a~)'})" (jquery element) "false"))
))



;; array as attribute: <div id="demo" data-stuff='["some", "string", "here"]'></div>

;; <div id="storageElement" data-storeIt="stuff,more stuff"></div> and use string.split.

;;; this is just how I would structure such a dynamic website. With a 12 column layout with collection of input elements

(defun create-collection (parent width)
  (create-child parent (format nil "<div data-width='~a' class='collection'></div>" width)))