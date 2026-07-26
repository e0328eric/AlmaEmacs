;;; msgpack-mod.el --- Paired JSON and hex editor for MessagePack -*- lexical-binding: t; -*-

;; Author: AlmaEmacs contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: data tools

;;; Commentary:

;; `msgpack-mod' visits a MessagePack file without character conversion and
;; opens two synchronized views.  The left window contains editable JSON and
;; the right window uses Emacs's built-in `hexl-mode' for byte-level editing.
;;
;; In either view, `C-c C-c' applies that view to the other one and `C-x C-s'
;; synchronizes the most recently edited view before saving the binary file.
;; Edits are also synchronized after `msgpack-mod-sync-delay' seconds of idle
;; time.  `C-c C-j' and `C-c C-h' select the JSON and hex views, respectively;
;; `C-c C-r' reloads the file from disk.
;;
;; JSON cannot directly express MessagePack binary values, extension values,
;; non-string map keys, duplicate map keys, or non-finite floats.  This mode
;; represents those values with a reserved object of the following form:
;;
;;   {"$msgpack":{"type":"binary","hex":"00ff"}}
;;   {"$msgpack":{"type":"extension","extensionType":1,"hex":"abcd"}}
;;   {"$msgpack":{"type":"map","entries":[[key,value], ...]}}
;;   {"$msgpack":{"type":"float","value":"nan",
;;                 "width":32,"bits":"7fc00000"}}
;;
;; Ordinary maps containing the reserved key "$msgpack" are automatically
;; emitted with the tagged map representation so that they round-trip safely.
;; If a semantic JSON value changes, the containing value is regenerated in
;; canonical form: integers use their shortest representation and finite
;; floats use float64.  A formatting-only/no-op JSON edit preserves the exact
;; original bytes.

;;; Code:

(require 'cl-lib)
(require 'hexl)
(require 'json)
(require 'js)
(require 'subr-x)

(defgroup msgpack-mod nil
  "Edit MessagePack files through synchronized JSON and hex views."
  :group 'data
  :prefix "msgpack-mod-")

(defcustom msgpack-mod-sync-delay 0.35
  "Idle seconds before an edited JSON or hex view is synchronized.

Set this to nil to disable automatic synchronization.  The explicit
`msgpack-mod-apply-json', `msgpack-mod-refresh-json', and
`msgpack-mod-save' commands continue to work."
  :type '(choice (const :tag "Only synchronize explicitly" nil)
                 (number :tag "Idle seconds"))
  :group 'msgpack-mod)

(defcustom msgpack-mod-max-depth 512
  "Maximum nested collection depth accepted by the MessagePack codec."
  :type 'natnum
  :group 'msgpack-mod)

(define-error 'msgpack-mod-error "MessagePack error")

(defconst msgpack-mod--null (make-symbol "msgpack-null"))
(defconst msgpack-mod--false (make-symbol "msgpack-false"))

(cl-defstruct (msgpack-mod--map
               (:constructor msgpack-mod--make-map (entries)))
  entries)

(cl-defstruct (msgpack-mod--binary
               (:constructor msgpack-mod--make-binary (data)))
  data)

(cl-defstruct (msgpack-mod--extension
               (:constructor msgpack-mod--make-extension (type data)))
  type data)

(cl-defstruct (msgpack-mod--nonfinite
               (:constructor msgpack-mod--make-nonfinite
                             (kind width bits)))
  kind width bits)

(cl-defstruct (msgpack-mod--reader
               (:constructor msgpack-mod--make-reader (data)))
  data
  (position 0))

(cl-defstruct (msgpack-mod--session
               (:constructor msgpack-mod--make-session (owner)))
  owner json hex timer display-timer pending-source status closing)

(defvar msgpack-mod--syncing nil
  "Non-nil while msgpack-mod is changing a synchronized buffer.")

(defvar-local msgpack-mod--session nil
  "The MessagePack editing session associated with the current buffer.")

(defun msgpack-mod--fail (format-string &rest arguments)
  "Signal `msgpack-mod-error' using FORMAT-STRING and ARGUMENTS."
  (signal 'msgpack-mod-error
          (list (apply #'format format-string arguments))))

(defun msgpack-mod--unibyte (string)
  "Return STRING as a unibyte string."
  (if (multibyte-string-p string)
      (encode-coding-string string 'raw-text t)
    string))

(defun msgpack-mod--bytes (value width)
  "Encode unsigned VALUE in WIDTH big-endian bytes."
  (let ((result (make-string width 0)))
    (dotimes (index width)
      (aset result (- width index 1) (logand value #xff))
      (setq value (ash value -8)))
    (msgpack-mod--unibyte result)))

(defun msgpack-mod--tagged-bytes (tag value width)
  "Encode TAG followed by unsigned VALUE in WIDTH bytes."
  (concat (unibyte-string tag) (msgpack-mod--bytes value width)))

(defun msgpack-mod--encode-length (length fixed-limit fixed-base
                                          tag8 tag16 tag32)
  "Encode a collection LENGTH using the supplied MessagePack tags.

FIXED-LIMIT and FIXED-BASE describe the fixed-size tag family.  TAG8,
TAG16, and TAG32 may be nil when the corresponding form does not exist."
  (cond
   ((and fixed-limit (< length fixed-limit))
    (unibyte-string (+ fixed-base length)))
   ((and tag8 (<= length #xff))
    (msgpack-mod--tagged-bytes tag8 length 1))
   ((and tag16 (<= length #xffff))
    (msgpack-mod--tagged-bytes tag16 length 2))
   ((and tag32 (<= length #xffffffff))
    (msgpack-mod--tagged-bytes tag32 length 4))
   (t
    (msgpack-mod--fail "Collection is too large for MessagePack: %d" length))))

(defun msgpack-mod--float-infinite-p (value)
  "Return non-nil when floating-point VALUE is positive or negative infinity."
  (and (not (isnan value)) (isnan (- value value))))

(defun msgpack-mod--float64-bits (value)
  "Return the IEEE-754 binary64 bit pattern for finite float VALUE."
  (let* ((negative (< (copysign 1.0 value) 0.0))
         (sign (if negative (ash 1 63) 0))
         (absolute (abs value)))
    (cond
     ((isnan value) (logior sign #x7ff8000000000000))
     ((msgpack-mod--float-infinite-p value)
      (logior sign #x7ff0000000000000))
     ((zerop absolute) sign)
     (t
      (pcase-let ((`(,mantissa . ,binary-exponent) (frexp absolute)))
        (let ((unbiased-exponent (1- binary-exponent)))
          (if (< unbiased-exponent -1022)
              ;; Every native subnormal binary64 value is an integer multiple
              ;; of 2^-1074, so this scaling is exact.
              (logior sign (round (ldexp absolute 1074)))
            (let* ((exponent (+ unbiased-exponent 1023))
                   (significand (round (ldexp mantissa 53)))
                   (fraction (- significand (ash 1 52))))
              (logior sign (ash exponent 52) fraction)))))))))

(defun msgpack-mod--encode-integer (value)
  "Encode integer VALUE with the shortest MessagePack integer form."
  (cond
   ((and (>= value 0) (<= value #x7f))
    (unibyte-string value))
   ((and (< value 0) (>= value -32))
    (unibyte-string (logand value #xff)))
   ((and (>= value 0) (<= value #xff))
    (msgpack-mod--tagged-bytes #xcc value 1))
   ((and (>= value 0) (<= value #xffff))
    (msgpack-mod--tagged-bytes #xcd value 2))
   ((and (>= value 0) (<= value #xffffffff))
    (msgpack-mod--tagged-bytes #xce value 4))
   ((and (>= value 0) (<= value #xffffffffffffffff))
    (msgpack-mod--tagged-bytes #xcf value 8))
   ((and (< value 0) (>= value -128))
    (msgpack-mod--tagged-bytes #xd0 (logand value #xff) 1))
   ((and (< value 0) (>= value -32768))
    (msgpack-mod--tagged-bytes #xd1 (logand value #xffff) 2))
   ((and (< value 0) (>= value -2147483648))
    (msgpack-mod--tagged-bytes #xd2 (logand value #xffffffff) 4))
   ((and (< value 0) (>= value -9223372036854775808))
    (msgpack-mod--tagged-bytes #xd3
                               (logand value #xffffffffffffffff) 8))
   (t
    (msgpack-mod--fail "Integer is outside MessagePack's 64-bit range: %s"
                       value))))

(defun msgpack-mod--encode-extension (extension)
  "Encode MessagePack EXTENSION."
  (let* ((type (msgpack-mod--extension-type extension))
         (data (msgpack-mod--unibyte
                (msgpack-mod--extension-data extension)))
         (length (length data))
         (header
          (pcase length
            (1 (unibyte-string #xd4))
            (2 (unibyte-string #xd5))
            (4 (unibyte-string #xd6))
            (8 (unibyte-string #xd7))
            (16 (unibyte-string #xd8))
            (_ (msgpack-mod--encode-length length nil 0 #xc7 #xc8 #xc9)))))
    (unless (and (integerp type) (<= -128 type) (<= type 127))
      (msgpack-mod--fail "Extension type must be between -128 and 127: %s"
                         type))
    (concat header (unibyte-string (logand type #xff)) data)))

(defun msgpack-mod--encode-nonfinite (value)
  "Encode a non-finite float wrapper VALUE, preserving its bit pattern."
  (let ((width (msgpack-mod--nonfinite-width value))
        (bits (msgpack-mod--nonfinite-bits value)))
    (pcase width
      (32 (concat (unibyte-string #xca) (msgpack-mod--bytes bits 4)))
      (64 (concat (unibyte-string #xcb) (msgpack-mod--bytes bits 8)))
      (_ (msgpack-mod--fail "Unsupported floating-point width: %s" width)))))

(defun msgpack-mod--encode-value (value depth)
  "Encode internal MessagePack VALUE recursively at DEPTH."
  (when (> depth msgpack-mod-max-depth)
    (msgpack-mod--fail "MessagePack nesting exceeds %d levels"
                       msgpack-mod-max-depth))
  (cond
   ((eq value msgpack-mod--null) (unibyte-string #xc0))
   ((eq value msgpack-mod--false) (unibyte-string #xc2))
   ((eq value t) (unibyte-string #xc3))
   ((integerp value) (msgpack-mod--encode-integer value))
   ((floatp value)
    (concat (unibyte-string #xcb)
            (msgpack-mod--bytes (msgpack-mod--float64-bits value) 8)))
   ((stringp value)
    (let* ((data (msgpack-mod--unibyte
                  (encode-coding-string value 'utf-8 t)))
           (header (msgpack-mod--encode-length
                    (length data) 32 #xa0 #xd9 #xda #xdb)))
      (concat header data)))
   ((vectorp value)
    (let ((header (msgpack-mod--encode-length
                   (length value) 16 #x90 nil #xdc #xdd)))
      (concat header
              (mapconcat (lambda (element)
                           (msgpack-mod--encode-value element (1+ depth)))
                         value ""))))
   ((msgpack-mod--map-p value)
    (let* ((entries (msgpack-mod--map-entries value))
           (header (msgpack-mod--encode-length
                    (length entries) 16 #x80 nil #xde #xdf)))
      (concat
       header
       (mapconcat
        (lambda (entry)
          (concat (msgpack-mod--encode-value (car entry) (1+ depth))
                  (msgpack-mod--encode-value (cdr entry) (1+ depth))))
        entries ""))))
   ((msgpack-mod--binary-p value)
    (let* ((data (msgpack-mod--unibyte
                  (msgpack-mod--binary-data value)))
           (header (msgpack-mod--encode-length
                    (length data) nil 0 #xc4 #xc5 #xc6)))
      (concat header data)))
   ((msgpack-mod--extension-p value)
    (msgpack-mod--encode-extension value))
   ((msgpack-mod--nonfinite-p value)
    (msgpack-mod--encode-nonfinite value))
   (t
    (msgpack-mod--fail "Cannot encode Lisp value as MessagePack: %S" value))))

(defun msgpack-mod-encode (value)
  "Encode internal MessagePack VALUE as a unibyte string.

This is primarily useful to callers that use the tagged internal value
types defined by msgpack-mod.  JSON buffers are converted to this model by
`msgpack-mod--from-json' before encoding."
  (msgpack-mod--unibyte (msgpack-mod--encode-value value 0)))

(defun msgpack-mod--reader-remaining (reader)
  "Return the number of unread bytes in READER."
  (- (length (msgpack-mod--reader-data reader))
     (msgpack-mod--reader-position reader)))

(defun msgpack-mod--read-byte (reader)
  "Read one unsigned byte from READER."
  (when (< (msgpack-mod--reader-remaining reader) 1)
    (msgpack-mod--fail "Unexpected end of MessagePack data at byte %d"
                       (msgpack-mod--reader-position reader)))
  (prog1 (aref (msgpack-mod--reader-data reader)
               (msgpack-mod--reader-position reader))
    (cl-incf (msgpack-mod--reader-position reader))))

(defun msgpack-mod--read-bytes (reader length)
  "Read LENGTH raw bytes from READER."
  (when (> length (msgpack-mod--reader-remaining reader))
    (msgpack-mod--fail
     "Value at byte %d declares %d bytes, but only %d remain"
     (msgpack-mod--reader-position reader) length
     (msgpack-mod--reader-remaining reader)))
  (let ((start (msgpack-mod--reader-position reader)))
    (cl-incf (msgpack-mod--reader-position reader) length)
    (substring (msgpack-mod--reader-data reader) start (+ start length))))

(defun msgpack-mod--read-uint (reader width)
  "Read a big-endian unsigned integer from READER using WIDTH bytes."
  (let ((value 0))
    (dotimes (_ width value)
      (setq value (logior (ash value 8) (msgpack-mod--read-byte reader))))))

(defun msgpack-mod--signed (value bits)
  "Interpret unsigned VALUE as a two's-complement integer of BITS bits."
  (if (not (zerop (logand value (ash 1 (1- bits)))))
      (- value (ash 1 bits))
    value))

(defun msgpack-mod--decode-float-bits (bits width)
  "Decode IEEE-754 BITS of WIDTH 32 or 64."
  (let* ((fraction-width (if (= width 32) 23 52))
         (exponent-width (if (= width 32) 8 11))
         (bias (if (= width 32) 127 1023))
         (sign (not (zerop (logand bits (ash 1 (1- width))))))
         (fraction-mask (1- (ash 1 fraction-width)))
         (fraction (logand bits fraction-mask))
         (exponent (logand (ash bits (- fraction-width))
                           (1- (ash 1 exponent-width))))
         (maximum-exponent (1- (ash 1 exponent-width))))
    (cond
     ((= exponent maximum-exponent)
      (msgpack-mod--make-nonfinite
       (cond
        ((not (zerop fraction)) 'nan)
        (sign '-infinity)
        (t '+infinity))
       width bits))
     ((and (zerop exponent) (zerop fraction))
      (if sign (copysign 0.0 -1.0) 0.0))
     (t
      (let ((number
             (if (zerop exponent)
                 (ldexp (float fraction) (- 1 bias fraction-width))
               (ldexp (float (+ (ash 1 fraction-width) fraction))
                      (- exponent bias fraction-width)))))
        (if sign (- number) number))))))

(defun msgpack-mod--decode-string (reader length)
  "Read a UTF-8 string of LENGTH bytes from READER."
  (let* ((bytes (msgpack-mod--read-bytes reader length))
         (decoded (decode-coding-string bytes 'utf-8)))
    ;; `decode-coding-string' replaces malformed input on some Emacs builds.
    ;; A round trip makes MessagePack's UTF-8 requirement strict.
    (unless (and (not (cl-some (lambda (character)
                                 (eq (char-charset character) 'eight-bit))
                               decoded))
                 (equal bytes
                        (msgpack-mod--unibyte
                         (encode-coding-string decoded 'utf-8 t))))
      (msgpack-mod--fail "Invalid UTF-8 MessagePack string ending at byte %d"
                         (msgpack-mod--reader-position reader)))
    decoded))

(defun msgpack-mod--decode-array (reader length depth)
  "Decode an array of LENGTH values from READER at DEPTH."
  (when (> length (msgpack-mod--reader-remaining reader))
    (msgpack-mod--fail "Impossible array length %d at byte %d"
                       length (msgpack-mod--reader-position reader)))
  (let ((array (make-vector length nil))
        (position 0))
    (while (< position length)
      (aset array position (msgpack-mod--decode-value reader (1+ depth)))
      (setq position (1+ position)))
    array))

(defun msgpack-mod--decode-map (reader length depth)
  "Decode a map of LENGTH pairs from READER at DEPTH."
  (when (> (* length 2) (msgpack-mod--reader-remaining reader))
    (msgpack-mod--fail "Impossible map length %d at byte %d"
                       length (msgpack-mod--reader-position reader)))
  (let (entries)
    (dotimes (_ length)
      (push (cons (msgpack-mod--decode-value reader (1+ depth))
                  (msgpack-mod--decode-value reader (1+ depth)))
            entries))
    (msgpack-mod--make-map (nreverse entries))))

(defun msgpack-mod--decode-extension (reader length)
  "Decode an extension with LENGTH data bytes from READER."
  (let ((type (msgpack-mod--signed (msgpack-mod--read-byte reader) 8)))
    (msgpack-mod--make-extension type
                                (msgpack-mod--read-bytes reader length))))

(defun msgpack-mod--decode-value (reader depth)
  "Decode one value from READER recursively at DEPTH."
  (when (> depth msgpack-mod-max-depth)
    (msgpack-mod--fail "MessagePack nesting exceeds %d levels"
                       msgpack-mod-max-depth))
  (let ((tag (msgpack-mod--read-byte reader)))
    (cond
     ((<= tag #x7f) tag)
     ((<= #x80 tag #x8f)
      (msgpack-mod--decode-map reader (logand tag #x0f) depth))
     ((<= #x90 tag #x9f)
      (msgpack-mod--decode-array reader (logand tag #x0f) depth))
     ((<= #xa0 tag #xbf)
      (msgpack-mod--decode-string reader (logand tag #x1f)))
     ((>= tag #xe0) (- tag 256))
     (t
      (pcase tag
        (#xc0 msgpack-mod--null)
        (#xc1 (msgpack-mod--fail "Reserved MessagePack tag 0xc1 at byte %d"
                                 (1- (msgpack-mod--reader-position reader))))
        (#xc2 msgpack-mod--false)
        (#xc3 t)
        (#xc4 (msgpack-mod--make-binary
               (msgpack-mod--read-bytes reader
                                        (msgpack-mod--read-uint reader 1))))
        (#xc5 (msgpack-mod--make-binary
               (msgpack-mod--read-bytes reader
                                        (msgpack-mod--read-uint reader 2))))
        (#xc6 (msgpack-mod--make-binary
               (msgpack-mod--read-bytes reader
                                        (msgpack-mod--read-uint reader 4))))
        (#xc7 (msgpack-mod--decode-extension
               reader (msgpack-mod--read-uint reader 1)))
        (#xc8 (msgpack-mod--decode-extension
               reader (msgpack-mod--read-uint reader 2)))
        (#xc9 (msgpack-mod--decode-extension
               reader (msgpack-mod--read-uint reader 4)))
        (#xca (msgpack-mod--decode-float-bits
               (msgpack-mod--read-uint reader 4) 32))
        (#xcb (msgpack-mod--decode-float-bits
               (msgpack-mod--read-uint reader 8) 64))
        (#xcc (msgpack-mod--read-uint reader 1))
        (#xcd (msgpack-mod--read-uint reader 2))
        (#xce (msgpack-mod--read-uint reader 4))
        (#xcf (msgpack-mod--read-uint reader 8))
        (#xd0 (msgpack-mod--signed (msgpack-mod--read-uint reader 1) 8))
        (#xd1 (msgpack-mod--signed (msgpack-mod--read-uint reader 2) 16))
        (#xd2 (msgpack-mod--signed (msgpack-mod--read-uint reader 4) 32))
        (#xd3 (msgpack-mod--signed (msgpack-mod--read-uint reader 8) 64))
        (#xd4 (msgpack-mod--decode-extension reader 1))
        (#xd5 (msgpack-mod--decode-extension reader 2))
        (#xd6 (msgpack-mod--decode-extension reader 4))
        (#xd7 (msgpack-mod--decode-extension reader 8))
        (#xd8 (msgpack-mod--decode-extension reader 16))
        (#xd9 (msgpack-mod--decode-string
               reader (msgpack-mod--read-uint reader 1)))
        (#xda (msgpack-mod--decode-string
               reader (msgpack-mod--read-uint reader 2)))
        (#xdb (msgpack-mod--decode-string
               reader (msgpack-mod--read-uint reader 4)))
        (#xdc (msgpack-mod--decode-array
               reader (msgpack-mod--read-uint reader 2) depth))
        (#xdd (msgpack-mod--decode-array
               reader (msgpack-mod--read-uint reader 4) depth))
        (#xde (msgpack-mod--decode-map
               reader (msgpack-mod--read-uint reader 2) depth))
        (#xdf (msgpack-mod--decode-map
               reader (msgpack-mod--read-uint reader 4) depth))
        (_ (msgpack-mod--fail "Unknown MessagePack tag 0x%02x" tag)))))))

(defun msgpack-mod-decode (data)
  "Decode exactly one MessagePack value from unibyte string DATA.

Signal `msgpack-mod-error' if DATA is malformed or has trailing bytes."
  (let* ((bytes (msgpack-mod--unibyte data))
         (reader (msgpack-mod--make-reader bytes))
         (value (msgpack-mod--decode-value reader 0))
         (remaining (msgpack-mod--reader-remaining reader)))
    (unless (zerop remaining)
      (msgpack-mod--fail "Trailing data starts at byte %d"
                         (msgpack-mod--reader-position reader)))
    value))

(defun msgpack-mod--hex-string (bytes)
  "Return lowercase hexadecimal text for BYTES."
  (mapconcat (lambda (byte) (format "%02x" byte)) bytes ""))

(defun msgpack-mod--parse-hex (text)
  "Parse hexadecimal TEXT into a unibyte string."
  (unless (and (stringp text)
               (zerop (% (length text) 2))
               (string-match-p "\\`[[:xdigit:]]*\\'" text))
    (msgpack-mod--fail "Expected an even-length hexadecimal string"))
  (let* ((length (/ (length text) 2))
         (result (make-string length 0)))
    (dotimes (index length)
      (aset result index
            (string-to-number (substring text (* index 2) (+ (* index 2) 2))
                              16)))
    (msgpack-mod--unibyte result)))

(defun msgpack-mod--json-field (name object)
  "Return the cons cell for NAME in JSON alist OBJECT."
  (and (listp object) (assoc name object)))

(defun msgpack-mod--json-wrapper (fields)
  "Wrap JSON alist FIELDS in the reserved $msgpack object."
  (list (cons "$msgpack" fields)))

(defun msgpack-mod--map-json-compatible-p (entries)
  "Return non-nil when map ENTRIES can be represented as a JSON object."
  (let ((seen (make-hash-table :test #'equal))
        compatible)
    (setq compatible t)
    (dolist (entry entries compatible)
      (let ((key (car entry)))
        (when (or (not (stringp key))
                  (string= key "$msgpack")
                  (gethash key seen))
          (setq compatible nil))
        (when (stringp key)
          (puthash key t seen))))))

(defun msgpack-mod--to-json (value)
  "Convert internal MessagePack VALUE to a JSON-serializable value."
  (cond
   ((or (eq value msgpack-mod--null)
        (eq value msgpack-mod--false)
        (eq value t)
        (integerp value))
    value)
   ((floatp value)
    (if (or (isnan value) (msgpack-mod--float-infinite-p value))
        (let* ((bits (msgpack-mod--float64-bits value))
               (kind (cond ((isnan value) "nan")
                           ((< value 0.0) "-infinity")
                           (t "+infinity"))))
          (msgpack-mod--json-wrapper
           `(("type" . "float") ("value" . ,kind) ("width" . 64)
             ("bits" . ,(format "%016x" bits)))))
      value))
   ((stringp value) value)
   ((vectorp value)
    (apply #'vector (mapcar #'msgpack-mod--to-json value)))
   ((msgpack-mod--map-p value)
    (let ((entries (msgpack-mod--map-entries value)))
      (if (msgpack-mod--map-json-compatible-p entries)
          (mapcar (lambda (entry)
                    (cons (car entry) (msgpack-mod--to-json (cdr entry))))
                  entries)
        (msgpack-mod--json-wrapper
         `(("type" . "map")
           ("entries" .
            ,(apply
              #'vector
              (mapcar
               (lambda (entry)
                 (vector (msgpack-mod--to-json (car entry))
                         (msgpack-mod--to-json (cdr entry))))
               entries))))))))
   ((msgpack-mod--binary-p value)
    (msgpack-mod--json-wrapper
     `(("type" . "binary")
       ("hex" . ,(msgpack-mod--hex-string
                   (msgpack-mod--binary-data value))))))
   ((msgpack-mod--extension-p value)
    (msgpack-mod--json-wrapper
     `(("type" . "extension")
       ("extensionType" . ,(msgpack-mod--extension-type value))
       ("hex" . ,(msgpack-mod--hex-string
                   (msgpack-mod--extension-data value))))))
   ((msgpack-mod--nonfinite-p value)
    (let ((kind (pcase (msgpack-mod--nonfinite-kind value)
                  ('nan "nan") ('-infinity "-infinity")
                  (_ "+infinity")))
          (width (msgpack-mod--nonfinite-width value))
          (bits (msgpack-mod--nonfinite-bits value)))
      (msgpack-mod--json-wrapper
       `(("type" . "float") ("value" . ,kind) ("width" . ,width)
         ("bits" . ,(format (if (= width 32) "%08x" "%016x") bits))))))
   (t
    (msgpack-mod--fail "Cannot represent MessagePack value as JSON: %S"
                       value))))

(defun msgpack-mod--wrapper-type (value)
  "Return VALUE's recognized $msgpack wrapper type, or nil."
  (when (and (listp value) (= (length value) 1))
    (let* ((wrapper-cell (msgpack-mod--json-field "$msgpack" value))
           (wrapper (cdr-safe wrapper-cell))
           (type-cell (msgpack-mod--json-field "type" wrapper))
           (type (cdr-safe type-cell)))
      (and (member type '("binary" "extension" "map" "float")) type))))

(defun msgpack-mod--from-json-wrapper (value type depth)
  "Convert tagged JSON VALUE of TYPE at DEPTH to an internal value."
  (let* ((wrapper (cdr (msgpack-mod--json-field "$msgpack" value)))
         (hex-cell (msgpack-mod--json-field "hex" wrapper)))
    (pcase type
      ("binary"
       (unless (and hex-cell (stringp (cdr hex-cell)))
         (msgpack-mod--fail "Binary wrapper requires a string field named hex"))
       (msgpack-mod--make-binary (msgpack-mod--parse-hex (cdr hex-cell))))
      ("extension"
       (let ((type-cell (msgpack-mod--json-field "extensionType" wrapper)))
         (unless (and type-cell (integerp (cdr type-cell))
                      (<= -128 (cdr type-cell)) (<= (cdr type-cell) 127))
           (msgpack-mod--fail
            "Extension wrapper requires extensionType between -128 and 127"))
         (unless (and hex-cell (stringp (cdr hex-cell)))
           (msgpack-mod--fail
            "Extension wrapper requires a string field named hex"))
         (msgpack-mod--make-extension
          (cdr type-cell) (msgpack-mod--parse-hex (cdr hex-cell)))))
      ("map"
       (let* ((entries-cell (msgpack-mod--json-field "entries" wrapper))
              (entries (cdr-safe entries-cell)))
         (unless (vectorp entries)
           (msgpack-mod--fail "Map wrapper requires an array field named entries"))
         (msgpack-mod--make-map
          (mapcar
           (lambda (entry)
             (unless (and (vectorp entry) (= (length entry) 2))
               (msgpack-mod--fail
                "Each tagged map entry must be a two-element array"))
             (cons (msgpack-mod--from-json (aref entry 0) (1+ depth))
                   (msgpack-mod--from-json (aref entry 1) (1+ depth))))
           entries))))
      ("float"
       (let* ((value-cell (msgpack-mod--json-field "value" wrapper))
              (width-cell (msgpack-mod--json-field "width" wrapper))
              (bits-cell (msgpack-mod--json-field "bits" wrapper))
              (kind-name (cdr-safe value-cell))
              (width (or (cdr-safe width-cell) 64))
              (kind (pcase kind-name
                      ("nan" 'nan) ("-infinity" '-infinity)
                      ("+infinity" '+infinity)
                      (_ nil))))
         (unless (and kind (memq width '(32 64)))
           (msgpack-mod--fail
            "Float wrapper requires value nan/+infinity/-infinity and width 32/64"))
         (let* ((default-bits
                  (pcase (cons kind width)
                    (`(nan . 32) #x7fc00000)
                    (`(nan . 64) #x7ff8000000000000)
                    (`(-infinity . 32) #xff800000)
                    (`(-infinity . 64) #xfff0000000000000)
                    (`(+infinity . 32) #x7f800000)
                    (_ #x7ff0000000000000)))
                (bits
                 (if bits-cell
                     (let ((text (cdr bits-cell)))
                       (unless (and (stringp text)
                                    (= (length text) (if (= width 32) 8 16))
                                    (string-match-p "\\`[[:xdigit:]]+\\'" text))
                         (msgpack-mod--fail
                          "Float bits must contain exactly %d hex digits"
                          (if (= width 32) 8 16)))
                       (string-to-number text 16))
                   default-bits))
                (decoded (msgpack-mod--decode-float-bits bits width)))
           (unless (and (msgpack-mod--nonfinite-p decoded)
                        (eq kind (msgpack-mod--nonfinite-kind decoded)))
             (msgpack-mod--fail
              "Float bits do not encode the wrapper's declared value"))
           decoded))))))

(defun msgpack-mod--from-json (value depth)
  "Convert parsed JSON VALUE at DEPTH to the internal MessagePack model."
  (when (> depth msgpack-mod-max-depth)
    (msgpack-mod--fail "JSON nesting exceeds %d levels" msgpack-mod-max-depth))
  (let ((wrapper-type (msgpack-mod--wrapper-type value)))
    (cond
     (wrapper-type
      (msgpack-mod--from-json-wrapper value wrapper-type depth))
     ((eq value msgpack-mod--null) msgpack-mod--null)
     ((eq value msgpack-mod--false) msgpack-mod--false)
     ((eq value t) t)
     ((or (integerp value) (floatp value) (stringp value)) value)
     ((vectorp value)
      (apply #'vector
             (mapcar (lambda (element)
                       (msgpack-mod--from-json element (1+ depth)))
                     value)))
     ((listp value)
      (msgpack-mod--make-map
       (mapcar (lambda (entry)
                 (unless (and (consp entry) (stringp (car entry)))
                   (msgpack-mod--fail "Invalid JSON object member: %S" entry))
                 (cons (car entry)
                       (msgpack-mod--from-json (cdr entry) (1+ depth))))
               value)))
     (t
     (msgpack-mod--fail "Unsupported JSON value: %S" value)))))

(defun msgpack-mod--json-native-tree (value)
  "Convert JSON model VALUE to containers accepted by `json-serialize'.

Native JSON serialization requires alist keys to be symbols.  Hash tables
let this mode keep arbitrary JSON keys as strings without interning them."
  (cond
   ((vectorp value)
    (apply #'vector
           (mapcar #'msgpack-mod--json-native-tree value)))
   ((listp value)
    (let ((object (make-hash-table :test #'equal)))
      (dolist (entry value object)
        (puthash (car entry)
                 (msgpack-mod--json-native-tree (cdr entry))
                 object))))
   (t value)))

(defun msgpack-mod--json-string (value)
  "Return pretty JSON text representing internal MessagePack VALUE."
  (with-temp-buffer
    (insert (json-serialize
             (msgpack-mod--json-native-tree (msgpack-mod--to-json value))
                            :null-object msgpack-mod--null
                            :false-object msgpack-mod--false))
    (json-pretty-print-buffer)
    (unless (bolp) (insert "\n"))
    (buffer-string)))

(defun msgpack-mod--parse-json-buffer ()
  "Parse the current JSON buffer into the internal MessagePack model.

Preserve point whether parsing succeeds or signals an error."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      ;; The native parser interns alist keys.  The legacy parser's dynamic
      ;; `json-key-type' option preserves arbitrary keys as strings and also
      ;; retains duplicate members, both of which matter for a data editor.
      (let ((json-object-type 'alist)
            (json-array-type 'vector)
            (json-key-type 'string)
            (json-null msgpack-mod--null)
            (json-false msgpack-mod--false))
        (let ((value (json-read)))
          (skip-chars-forward " \t\r\n")
          (unless (eobp)
            (msgpack-mod--fail
             "Trailing JSON content at character %d" (point)))
          (msgpack-mod--from-json value 0))))))

(defun msgpack-mod--owner-bytes (session)
  "Return a copy of the raw bytes held by SESSION's owner buffer."
  (let ((owner (msgpack-mod--session-owner session)))
    (unless (buffer-live-p owner)
      (user-error "The MessagePack file buffer is no longer live"))
    (with-current-buffer owner
      (msgpack-mod--unibyte
       (buffer-substring-no-properties (point-min) (point-max))))))

(defun msgpack-mod--hexlify (bytes)
  "Return a `hexl-mode' display string for raw BYTES."
  (if (string-empty-p bytes)
      ""
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (setq-local buffer-file-coding-system 'no-conversion)
      (insert bytes)
      (let ((buffer-undo-list t))
        (hexlify-buffer))
      (buffer-substring-no-properties (point-min) (point-max)))))

(defun msgpack-mod--dehexlify-current-buffer ()
  "Return raw bytes represented by the current `hexl-mode' buffer."
  (if (zerop (buffer-size))
      ""
    (let ((display (buffer-substring-no-properties (point-min) (point-max))))
      (with-temp-buffer
        (set-buffer-multibyte nil)
        (setq-local buffer-file-coding-system 'no-conversion)
        (insert display)
        (let ((buffer-undo-list t))
          (dehexlify-buffer))
        (buffer-substring-no-properties (point-min) (point-max))))))

(defun msgpack-mod--set-owner-bytes (session bytes)
  "Replace SESSION's owner contents with raw BYTES when they differ."
  (let ((owner (msgpack-mod--session-owner session)))
    (unless (buffer-live-p owner)
      (user-error "The MessagePack file buffer is no longer live"))
    (with-current-buffer owner
      (unless (equal bytes (buffer-substring-no-properties
                            (point-min) (point-max)))
        (let ((inhibit-read-only t)
              (msgpack-mod--syncing t))
          (erase-buffer)
          (insert bytes))))))

(defun msgpack-mod--replace-hex (session bytes)
  "Replace SESSION's hex display with BYTES."
  (let ((hex-buffer (msgpack-mod--session-hex session)))
    (when (buffer-live-p hex-buffer)
      (with-current-buffer hex-buffer
        (let* ((old-address (and (eq major-mode 'hexl-mode)
                                 (> (buffer-size) 0)
                                 (ignore-errors (hexl-current-address))))
               (display (msgpack-mod--hexlify bytes))
               (inhibit-read-only t)
               (msgpack-mod--syncing t))
          (erase-buffer)
          (insert display)
          (setq hexl-max-address (1- (length bytes)))
          (when (> (length bytes) 0)
            (ignore-errors
              (hexl-goto-address (min (or old-address 0)
                                      hexl-max-address))))
          (set-buffer-modified-p nil))))))

(defun msgpack-mod--diagnostic-json (error-message)
  "Return an intentionally non-JSON diagnostic for ERROR-MESSAGE."
  (format (concat "/* MessagePack decode error:\n   %s\n\n"
                  "Edit the raw hex pane and press C-c C-c after "
                  "repairing the bytes.\n*/\n")
          (replace-regexp-in-string "[\n\r]+" " " error-message)))

(defun msgpack-mod--replace-json-text (session text)
  "Replace SESSION's JSON buffer with TEXT without scheduling a sync."
  (let ((json-buffer (msgpack-mod--session-json session)))
    (when (buffer-live-p json-buffer)
      (with-current-buffer json-buffer
        (let ((inhibit-read-only t)
              (msgpack-mod--syncing t)
              (point-offset (point)))
          (erase-buffer)
          (insert text)
          (goto-char (min point-offset (point-max)))
          (set-buffer-modified-p nil))))))

(defun msgpack-mod--replace-json-from-bytes (session bytes)
  "Decode BYTES and replace SESSION's JSON view.

Return nil on success.  On failure, install a diagnostic and return the
human-readable error string."
  (condition-case error-data
      (progn
        (msgpack-mod--replace-json-text
         session (msgpack-mod--json-string (msgpack-mod-decode bytes)))
        nil)
    (error
     (let ((message (error-message-string error-data)))
       (msgpack-mod--replace-json-text
        session (msgpack-mod--diagnostic-json message))
       message))))

(defun msgpack-mod--set-status (session text)
  "Set SESSION status to TEXT and refresh its mode lines."
  (setf (msgpack-mod--session-status session) text)
  (dolist (buffer (list (msgpack-mod--session-json session)
                        (msgpack-mod--session-hex session)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (force-mode-line-update t)))))

(defun msgpack-mod--status-text (session prefix)
  "Return status text for SESSION starting with PREFIX."
  (let ((owner (msgpack-mod--session-owner session)))
    (format "%s%s"
            prefix
            (if (and (buffer-live-p owner)
                     (buffer-modified-p owner))
                " — file has unsaved changes"
              " — file is saved"))))

(defun msgpack-mod--cancel-timer (session)
  "Cancel SESSION's pending idle timer."
  (let ((timer (msgpack-mod--session-timer session)))
    (when (timerp timer)
      (cancel-timer timer))
    (setf (msgpack-mod--session-timer session) nil)))

(defun msgpack-mod--cancel-display-timer (session)
  "Cancel SESSION's deferred view-opening timer."
  (let ((timer (msgpack-mod--session-display-timer session)))
    (when (timerp timer)
      (cancel-timer timer))
    (setf (msgpack-mod--session-display-timer session) nil)))

(defun msgpack-mod--sync-json-source (session source)
  "Apply JSON SOURCE to SESSION's owner and hex buffers."
  (let (bytes value)
    (with-current-buffer source
      (setq value (msgpack-mod--parse-json-buffer)))
    (let ((original-bytes (msgpack-mod--owner-bytes session)))
      ;; Formatting-only JSON edits should not canonicalize an otherwise
      ;; untouched MessagePack encoding (for example float32 into float64).
      (setq bytes
            (if (condition-case nil
                    (equal value (msgpack-mod-decode original-bytes))
                  (error nil))
                original-bytes
              (msgpack-mod-encode value))))
    (msgpack-mod--set-owner-bytes session bytes)
    ;; Refresh even when BYTES equal the owner: a forced JSON resolution must
    ;; still discard an independently edited hex companion.
    (msgpack-mod--replace-hex session bytes)
    (with-current-buffer source (set-buffer-modified-p nil))
    (msgpack-mod--set-status
     session (msgpack-mod--status-text session "JSON applied"))))

(defun msgpack-mod--sync-hex-source (session source)
  "Apply raw hex SOURCE to SESSION's owner and JSON buffers."
  (let (bytes decode-error)
    (with-current-buffer source
      (setq bytes (msgpack-mod--dehexlify-current-buffer)))
    (msgpack-mod--set-owner-bytes session bytes)
    (setq decode-error (msgpack-mod--replace-json-from-bytes session bytes))
    (with-current-buffer source (set-buffer-modified-p nil))
    (msgpack-mod--set-status
     session
     (if decode-error
         (format "Raw bytes applied; JSON unavailable: %s" decode-error)
       (msgpack-mod--status-text session "Raw bytes applied")))))

(defun msgpack-mod--transient-json-input-error-p
    (session source error-data)
  "Return non-nil when ERROR-DATA describes invalid JSON input in SOURCE.

SESSION identifies the JSON companion.  JSON syntax errors and errors raised
while converting the JSON representation to MessagePack are expected while a
user is in the middle of editing and should be quiet during automatic sync."
  (and (eq source (msgpack-mod--session-json session))
       (let ((conditions (get (car-safe error-data) 'error-conditions)))
         (or (memq 'json-error conditions)
             (memq 'msgpack-mod-error conditions)))))

(defun msgpack-mod--sync-source (session source &optional quiet force)
  "Synchronize SESSION from SOURCE.

When QUIET is non-nil, report errors in the session status instead of
signaling them.  When FORCE is non-nil, discard edits in the other view."
  (msgpack-mod--cancel-timer session)
  (condition-case error-data
      (progn
        (unless (buffer-live-p source)
          (user-error "The edited MessagePack view was closed"))
        (let ((other (if (eq source (msgpack-mod--session-json session))
                         (msgpack-mod--session-hex session)
                       (msgpack-mod--session-json session))))
          (when (and (not force)
                     (buffer-live-p other) (buffer-modified-p other))
            (user-error
             (concat "Both MessagePack views were edited; use C-u C-c C-c "
                     "in the view whose contents you want to keep"))))
        (let ((msgpack-mod--syncing t))
          (cond
           ((eq source (msgpack-mod--session-json session))
            (msgpack-mod--sync-json-source session source))
           ((eq source (msgpack-mod--session-hex session))
            (msgpack-mod--sync-hex-source session source))
           (t (user-error "Buffer is not part of this MessagePack session"))))
        (setf (msgpack-mod--session-pending-source session) nil)
        t)
    (error
     (msgpack-mod--set-status
      session
      (if (and quiet
               (msgpack-mod--transient-json-input-error-p
                session source error-data))
          "Waiting for valid JSON"
        (format "Not synchronized: %s"
                (error-message-string error-data))))
     (unless quiet
       (signal (car error-data) (cdr error-data)))
     nil)))

(defun msgpack-mod--idle-sync (session source)
  "Idle-timer callback that synchronizes SESSION from SOURCE."
  (when (and (msgpack-mod--session-p session)
             (buffer-live-p source)
             (eq source (msgpack-mod--session-pending-source session)))
    (setf (msgpack-mod--session-timer session) nil)
    (msgpack-mod--sync-source session source t)))

(defun msgpack-mod--after-change (&rest _ignored)
  "Schedule synchronization after an edit in a companion view."
  (unless msgpack-mod--syncing
    (let ((session msgpack-mod--session)
          (source (current-buffer)))
      (when (msgpack-mod--session-p session)
        (msgpack-mod--cancel-timer session)
        (setf (msgpack-mod--session-pending-source session) source)
        (msgpack-mod--set-status session "Waiting for valid input")
        (when msgpack-mod-sync-delay
          (setf (msgpack-mod--session-timer session)
                (run-with-idle-timer
                 (max 0 msgpack-mod-sync-delay) nil
                 #'msgpack-mod--idle-sync session source)))))))

(defun msgpack-mod--require-session ()
  "Return the current live MessagePack session or signal a user error."
  (unless (and (msgpack-mod--session-p msgpack-mod--session)
               (buffer-live-p
                (msgpack-mod--session-owner msgpack-mod--session)))
    (user-error "This buffer is not attached to a live MessagePack file"))
  msgpack-mod--session)

;;;###autoload
(defun msgpack-mod-apply-json (&optional force)
  "Encode the session's JSON view and update the raw MessagePack bytes.

With prefix argument FORCE, discard simultaneous edits in the hex view."
  (interactive "P")
  (let* ((session (msgpack-mod--require-session))
         (json-buffer (msgpack-mod--session-json session)))
    (unless (buffer-live-p json-buffer)
      (user-error "The JSON view was closed; use `msgpack-mod-open-view'"))
    (setf (msgpack-mod--session-pending-source session) json-buffer)
    (msgpack-mod--sync-source session json-buffer nil force)))

;;;###autoload
(defun msgpack-mod-refresh-json (&optional force)
  "Apply the session's raw hex bytes and regenerate its JSON view.

With prefix argument FORCE, discard simultaneous edits in the JSON view."
  (interactive "P")
  (let* ((session (msgpack-mod--require-session))
         (hex-buffer (msgpack-mod--session-hex session)))
    (unless (buffer-live-p hex-buffer)
      (user-error "The hex view was closed; use `msgpack-mod-open-view'"))
    (setf (msgpack-mod--session-pending-source session) hex-buffer)
    (msgpack-mod--sync-source session hex-buffer nil force)))

(defun msgpack-mod--read-hex-byte ()
  "Read one hexadecimal byte from the minibuffer."
  (let ((text (read-string "Byte (00-ff): ")))
    (unless (string-match-p "\\`[[:xdigit:]]\\{1,2\\}\\'" text)
      (user-error "Enter one hexadecimal byte between 00 and ff"))
    (string-to-number text 16)))

;;;###autoload
(defun msgpack-mod-hex-insert-byte (byte)
  "Insert BYTE before point in the MessagePack hex view.

Unlike ordinary `hexl-mode' overstrike editing, this command can change the
length of the MessagePack file."
  (interactive (list (msgpack-mod--read-hex-byte)))
  (let* ((session (msgpack-mod--require-session))
         (hex-buffer (msgpack-mod--session-hex session)))
    (unless (eq (current-buffer) hex-buffer)
      (user-error "Use this command in the MessagePack hex view"))
    (let* ((bytes (msgpack-mod--dehexlify-current-buffer))
           (address (if (string-empty-p bytes)
                        0
                      (min (hexl-current-address) (length bytes))))
           (updated (concat (substring bytes 0 address)
                            (unibyte-string byte)
                            (substring bytes address))))
      (msgpack-mod--replace-hex session updated)
      (when (> (length updated) 0)
        (hexl-goto-address address))
      (set-buffer-modified-p t)
      (msgpack-mod--after-change))))

;;;###autoload
(defun msgpack-mod-hex-delete-byte ()
  "Delete the byte at point in the MessagePack hex view."
  (interactive)
  (let* ((session (msgpack-mod--require-session))
         (hex-buffer (msgpack-mod--session-hex session)))
    (unless (eq (current-buffer) hex-buffer)
      (user-error "Use this command in the MessagePack hex view"))
    (let ((bytes (msgpack-mod--dehexlify-current-buffer)))
      (when (string-empty-p bytes)
        (user-error "The MessagePack byte buffer is already empty"))
      (let* ((address (min (hexl-current-address) (1- (length bytes))))
             (updated (concat (substring bytes 0 address)
                              (substring bytes (1+ address)))))
        (msgpack-mod--replace-hex session updated)
        (when (> (length updated) 0)
          (hexl-goto-address (min address (1- (length updated)))))
        (set-buffer-modified-p t)
        (msgpack-mod--after-change)))))

(defun msgpack-mod--sync-pending (session)
  "Synchronize the pending source in SESSION, if any."
  (let* ((companions (list (msgpack-mod--session-json session)
                           (msgpack-mod--session-hex session)))
         (modified
          (cl-remove-if-not
           (lambda (buffer)
             (and (buffer-live-p buffer) (buffer-modified-p buffer)))
           companions))
         (pending (msgpack-mod--session-pending-source session))
         ;; Derive the source from actual buffer state as well as the pointer.
         ;; A killed pane or an undo can otherwise leave PENDING stale.
         (source (cond
                  ((= (length modified) 1) (car modified))
                  ((> (length modified) 1)
                   (if (memq pending modified) pending (car modified))))))
    (when source
      (setf (msgpack-mod--session-pending-source session) source)
      (msgpack-mod--sync-source session source))))

;;;###autoload
(defun msgpack-mod-save ()
  "Synchronize the active MessagePack session and save its binary file."
  (interactive)
  (let* ((session (msgpack-mod--require-session))
         (owner (msgpack-mod--session-owner session)))
    (msgpack-mod--sync-pending session)
    (with-current-buffer owner
      (save-buffer))))

(defun msgpack-mod--owner-before-save ()
  "Synchronize a pending companion edit before saving the owner buffer."
  (when (msgpack-mod--session-p msgpack-mod--session)
    (msgpack-mod--sync-pending msgpack-mod--session)))

(defun msgpack-mod--owner-after-save ()
  "Update companion state after the MessagePack owner buffer is saved."
  (when (msgpack-mod--session-p msgpack-mod--session)
    (dolist (buffer (list (msgpack-mod--session-json msgpack-mod--session)
                          (msgpack-mod--session-hex msgpack-mod--session)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (set-buffer-modified-p nil))))
    (msgpack-mod--set-status msgpack-mod--session "Saved MessagePack file")))

(defun msgpack-mod--reload-session (session)
  "Reload SESSION's owner from disk and rebuild both views."
  (let* ((owner (msgpack-mod--session-owner session))
         (filename (and (buffer-live-p owner)
                        (buffer-file-name owner))))
    (unless (and filename (file-readable-p filename))
      (user-error "The MessagePack file is not readable"))
    (msgpack-mod--cancel-timer session)
    (setf (msgpack-mod--session-pending-source session) nil)
    (with-current-buffer owner
      (let ((inhibit-read-only t)
            (coding-system-for-read 'no-conversion)
            (msgpack-mod--syncing t))
        (erase-buffer)
        (insert-file-contents-literally filename)
        (set-buffer-modified-p nil)
        (set-visited-file-modtime)))
    (let ((bytes (msgpack-mod--owner-bytes session)))
      (msgpack-mod--replace-hex session bytes)
      (let ((error-message
             (msgpack-mod--replace-json-from-bytes session bytes)))
        (msgpack-mod--set-status
         session
         (if error-message
             (format "Reloaded raw bytes; JSON unavailable: %s" error-message)
           "Reloaded MessagePack file"))))))

;;;###autoload
(defun msgpack-mod-revert (&optional no-confirm)
  "Reload the MessagePack session from disk.

With optional NO-CONFIRM non-nil, do not ask before discarding changes."
  (interactive "P")
  (let ((session (msgpack-mod--require-session)))
    (when (or no-confirm
              (yes-or-no-p "Discard MessagePack edits and reload from disk? "))
      (msgpack-mod--reload-session session))))

(defun msgpack-mod--revert-buffer (_ignore-auto no-confirm)
  "Revert the owner buffer, skipping confirmation when NO-CONFIRM is non-nil."
  (when (or no-confirm
            (yes-or-no-p "Discard MessagePack edits and reload from disk? "))
    (msgpack-mod--reload-session (msgpack-mod--require-session))))

(defun msgpack-mod--json-header ()
  "Return the current JSON view's header line."
  (if (msgpack-mod--session-p msgpack-mod--session)
      (format " MessagePack JSON — %s"
              (or (msgpack-mod--session-status msgpack-mod--session)
                  "ready"))
    " Detached MessagePack JSON view"))

(defun msgpack-mod--hex-mode-line-status ()
  "Return a compact status string for the hex view's mode line."
  (when (msgpack-mod--session-p msgpack-mod--session)
    (let ((owner (msgpack-mod--session-owner msgpack-mod--session)))
      (cond
       ((not (buffer-live-p owner)) " [detached]")
       ((buffer-modified-p owner) " [file modified]")
       (t " [file saved]")))))

(defvar msgpack-mod-json-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'msgpack-mod-apply-json)
    (define-key map (kbd "C-c C-j") #'msgpack-mod-select-json)
    (define-key map (kbd "C-c C-h") #'msgpack-mod-select-hex)
    (define-key map (kbd "C-c C-r") #'msgpack-mod-revert)
    (define-key map (kbd "C-x C-s") #'msgpack-mod-save)
    map)
  "Keymap for `msgpack-mod-json-mode'.")

(defvar msgpack-mod-hex-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map hexl-mode-map)
    (define-key map (kbd "C-c C-c") #'msgpack-mod-refresh-json)
    (define-key map (kbd "C-c C-j") #'msgpack-mod-select-json)
    (define-key map (kbd "C-c C-h") #'msgpack-mod-select-hex)
    (define-key map (kbd "C-c C-r") #'msgpack-mod-revert)
    (define-key map (kbd "C-c C-i") #'msgpack-mod-hex-insert-byte)
    (define-key map (kbd "C-c C-d") #'msgpack-mod-hex-delete-byte)
    (define-key map (kbd "C-x C-s") #'msgpack-mod-save)
    map)
  "Keymap layered over `hexl-mode-map' in MessagePack hex views.")

(defvar msgpack-mod-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-v") #'msgpack-mod-open-view)
    (define-key map (kbd "C-c C-j") #'msgpack-mod-select-json)
    (define-key map (kbd "C-c C-h") #'msgpack-mod-select-hex)
    (define-key map (kbd "C-c C-r") #'msgpack-mod-revert)
    (define-key map (kbd "C-x C-s") #'msgpack-mod-save)
    map)
  "Keymap for the binary owner buffer used by `msgpack-mod'.")

(define-derived-mode msgpack-mod-json-mode js-json-mode "MessagePack-JSON"
  "Major mode for the editable JSON side of a MessagePack session."
  (setq-local header-line-format '(:eval (msgpack-mod--json-header))))

(defun msgpack-mod--companion-killed ()
  "Detach a killed JSON or hex companion from its session."
  (let ((session msgpack-mod--session)
        (buffer (current-buffer)))
    (when (and (msgpack-mod--session-p session)
               (not (msgpack-mod--session-closing session)))
      (when (eq buffer (msgpack-mod--session-pending-source session))
        (msgpack-mod--cancel-timer session)
        (setf (msgpack-mod--session-pending-source session) nil))
      (cond
       ((eq buffer (msgpack-mod--session-json session))
        (setf (msgpack-mod--session-json session) nil))
       ((eq buffer (msgpack-mod--session-hex session))
        (setf (msgpack-mod--session-hex session) nil))))))

(defun msgpack-mod--companion-kill-query ()
  "Ask before discarding an unsynchronized companion-buffer edit."
  (or msgpack-mod--syncing
      (not (msgpack-mod--session-p msgpack-mod--session))
      (msgpack-mod--session-closing msgpack-mod--session)
      (not (buffer-modified-p))
      (yes-or-no-p "Discard this unsynchronized MessagePack view edit? ")))

(defun msgpack-mod--companion-changing-mode ()
  "Protect an unsynchronized edit before changing a companion's mode."
  (unless (or msgpack-mod--syncing
              (not (msgpack-mod--session-p msgpack-mod--session))
              (msgpack-mod--session-closing msgpack-mod--session)
              (not (buffer-modified-p))
              (yes-or-no-p
               "Discard this edit and detach the MessagePack view? "))
    (user-error "Mode change canceled"))
  (msgpack-mod--companion-killed))

(defun msgpack-mod--companion-write-contents ()
  "Save the MessagePack owner instead of writing a companion as text."
  (let ((session (msgpack-mod--require-session)))
    (when (buffer-modified-p)
      (setf (msgpack-mod--session-pending-source session) (current-buffer)))
    (msgpack-mod-save)
    t))

(defun msgpack-mod--configure-companion (buffer session)
  "Attach BUFFER to SESSION and install common lifecycle hooks."
  (with-current-buffer buffer
    (setq-local msgpack-mod--session session)
    (setq-local buffer-offer-save 'always)
    (add-hook 'after-change-functions #'msgpack-mod--after-change nil t)
    (add-hook 'change-major-mode-hook
              #'msgpack-mod--companion-changing-mode nil t)
    (add-hook 'kill-buffer-query-functions
              #'msgpack-mod--companion-kill-query nil t)
    (add-hook 'write-contents-functions
              #'msgpack-mod--companion-write-contents nil t)
    (add-hook 'kill-buffer-hook #'msgpack-mod--companion-killed nil t)))

(defun msgpack-mod--make-json-buffer (session bytes)
  "Create and return SESSION's JSON companion initialized from BYTES."
  (let* ((owner (msgpack-mod--session-owner session))
         (buffer (generate-new-buffer
                  (format "*MessagePack JSON: %s*" (buffer-name owner)))))
    (with-current-buffer buffer
      (msgpack-mod-json-mode))
    (setf (msgpack-mod--session-json session) buffer)
    (msgpack-mod--configure-companion buffer session)
    (with-current-buffer buffer (buffer-disable-undo))
    (unwind-protect
        (let ((error-message
               (msgpack-mod--replace-json-from-bytes session bytes)))
          (when error-message
            (msgpack-mod--set-status
             session (format "JSON unavailable: %s" error-message))))
      (with-current-buffer buffer (buffer-enable-undo)))
    buffer))

(defun msgpack-mod--make-hex-buffer (session bytes)
  "Create and return SESSION's `hexl-mode' companion from BYTES."
  (let* ((owner (msgpack-mod--session-owner session))
         (buffer (generate-new-buffer
                  (format "*MessagePack Hex: %s*" (buffer-name owner)))))
    (with-current-buffer buffer
      (set-buffer-multibyte nil)
      (setq-local buffer-file-coding-system 'no-conversion)
      (insert bytes)
      (set-buffer-modified-p nil)
      ;; Prevent `hexl-mode' from asking to discard the temporary binary
      ;; insertion's undo record, then start a clean undo history for edits
      ;; to the actual hex display.
      (setq buffer-undo-list t)
      (hexl-mode)
      (setq buffer-undo-list nil)
      (setq hexl-max-address (1- (length bytes)))
      (use-local-map msgpack-mod-hex-mode-map)
      (setq-local mode-name "MessagePack-Hex")
      (setq-local mode-line-process '(:eval (msgpack-mod--hex-mode-line-status)))
      ;; The companion is deliberately not a file-visiting hexl buffer.
      (remove-hook 'write-contents-functions #'hexl-save-buffer t))
    (setf (msgpack-mod--session-hex session) buffer)
    (msgpack-mod--configure-companion buffer session)
    buffer))

(defun msgpack-mod--ensure-companions (session)
  "Ensure SESSION has live JSON and hex companions."
  (let ((bytes (msgpack-mod--owner-bytes session)))
    (unless (buffer-live-p (msgpack-mod--session-json session))
      (msgpack-mod--make-json-buffer session bytes))
    (unless (buffer-live-p (msgpack-mod--session-hex session))
      (msgpack-mod--make-hex-buffer session bytes))))

;;;###autoload
(defun msgpack-mod-open-view ()
  "Open the current MessagePack session as JSON-left and hex-right."
  (interactive)
  (let* ((session (msgpack-mod--require-session))
         (owner (msgpack-mod--session-owner session)))
    (msgpack-mod--ensure-companions session)
    (let* ((json-buffer (msgpack-mod--session-json session))
           (hex-buffer (msgpack-mod--session-hex session))
           (json-window (get-buffer-window json-buffer (selected-frame)))
           (hex-window (get-buffer-window hex-buffer (selected-frame))))
      (cond
       ((and (window-live-p json-window) (window-live-p hex-window))
        (select-window json-window))
       (t
        (let* ((base-window
                (or json-window hex-window
                    (get-buffer-window owner (selected-frame))
                    (selected-window)))
               (right-window
                (condition-case nil
                    (split-window base-window nil 'right)
                  (error
                   (display-buffer
                    hex-buffer
                    '((display-buffer-pop-up-window)
                      (inhibit-same-window . t)))))))
          (set-window-buffer base-window json-buffer)
          (when (window-live-p right-window)
            (set-window-buffer right-window hex-buffer))
          (select-window base-window)))))))

(defun msgpack-mod--open-view-when-displayed (session)
  "Open SESSION after its owner becomes the selected window's buffer."
  (setf (msgpack-mod--session-display-timer session) nil)
  (let ((owner (msgpack-mod--session-owner session)))
    ;; `find-file' chooses the major mode in a not-yet-displayed buffer and
    ;; only shows it afterward.  A zero timer reaches this point after that
    ;; display step.  The selected-buffer check keeps `find-file-noselect'
    ;; from splitting an unrelated window.
    (when (and (buffer-live-p owner)
               (eq (window-buffer (selected-window)) owner))
      (with-current-buffer owner
        (msgpack-mod-open-view)))))

(defun msgpack-mod--defer-open-view (session)
  "Arrange to open SESSION once the current command has displayed it."
  (msgpack-mod--cancel-display-timer session)
  (setf (msgpack-mod--session-display-timer session)
        (run-at-time 0 nil #'msgpack-mod--open-view-when-displayed session)))

;;;###autoload
(defun msgpack-mod-select-json ()
  "Select the JSON view for the current MessagePack session."
  (interactive)
  (let ((session (msgpack-mod--require-session)))
    (msgpack-mod--ensure-companions session)
    (pop-to-buffer (msgpack-mod--session-json session))))

;;;###autoload
(defun msgpack-mod-select-hex ()
  "Select the raw hex view for the current MessagePack session."
  (interactive)
  (let ((session (msgpack-mod--require-session)))
    (msgpack-mod--ensure-companions session)
    (pop-to-buffer (msgpack-mod--session-hex session))))

(defun msgpack-mod--owner-kill-query ()
  "Ask before killing an owner that has an unsynchronized companion edit."
  (let ((companions
         (and (msgpack-mod--session-p msgpack-mod--session)
              (list (msgpack-mod--session-json msgpack-mod--session)
                    (msgpack-mod--session-hex msgpack-mod--session)))))
    (or (not (cl-some (lambda (buffer)
                        (and (buffer-live-p buffer)
                             (buffer-modified-p buffer)))
                      companions))
        (yes-or-no-p "Discard the unsynchronized MessagePack view edit? "))))

(defun msgpack-mod--owner-killed ()
  "Cancel timers and close companion buffers with their owner."
  (let ((session msgpack-mod--session))
    (when (msgpack-mod--session-p session)
      (msgpack-mod--cancel-timer session)
      (msgpack-mod--cancel-display-timer session)
      (setf (msgpack-mod--session-closing session) t)
      (dolist (buffer (list (msgpack-mod--session-json session)
                            (msgpack-mod--session-hex session)))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (setf (msgpack-mod--session-json session) nil
            (msgpack-mod--session-hex session) nil
            (msgpack-mod--session-owner session) nil))))

(defun msgpack-mod--owner-changing-mode ()
  "Protect pending companion edits before leaving `msgpack-mod'."
  (let* ((session msgpack-mod--session)
         (companions
          (and (msgpack-mod--session-p session)
               (list (msgpack-mod--session-json session)
                     (msgpack-mod--session-hex session)))))
    (when (and (cl-some (lambda (buffer)
                          (and (buffer-live-p buffer)
                               (buffer-modified-p buffer)))
                        companions)
               (not (yes-or-no-p
                     "Discard unsynchronized edits and leave msgpack-mod? ")))
      (user-error "Mode change canceled"))
    (msgpack-mod--owner-killed)))

(defun msgpack-mod--make-owner-unibyte ()
  "Make the current MessagePack owner buffer store literal bytes."
  (when enable-multibyte-characters
    (let ((contents (buffer-substring-no-properties (point-min) (point-max)))
          (filename buffer-file-name)
          (modified (buffer-modified-p))
          (inhibit-read-only t))
      (erase-buffer)
      (set-buffer-multibyte nil)
      (if (and filename (not modified) (file-readable-p filename))
          ;; The coding-system association should already have made this
          ;; unnecessary, but a literal re-read also protects manual mode
          ;; activation after a file was decoded as text.
          (insert-file-contents-literally filename)
        (insert (msgpack-mod--unibyte contents)))
      (set-buffer-modified-p modified))))

;;;###autoload
(define-derived-mode msgpack-mod fundamental-mode "MessagePack"
  "Major mode owning a binary MessagePack file and its paired editor.

The file buffer remains the authoritative byte store.  `msgpack-mod' creates
an editable JSON companion on the left and an editable `hexl-mode' companion
on the right.  Use `msgpack-mod-open-view' to restore that layout if either
view has been closed.

\\{msgpack-mod-map}"
  (msgpack-mod--make-owner-unibyte)
  (setq-local buffer-file-coding-system 'no-conversion)
  (setq-local require-final-newline nil)
  (setq-local revert-buffer-function #'msgpack-mod--revert-buffer)
  (let ((session (msgpack-mod--make-session (current-buffer))))
    (setq-local msgpack-mod--session session)
    (add-hook 'before-save-hook #'msgpack-mod--owner-before-save nil t)
    (add-hook 'after-save-hook #'msgpack-mod--owner-after-save nil t)
    (add-hook 'kill-buffer-query-functions #'msgpack-mod--owner-kill-query nil t)
    (add-hook 'change-major-mode-hook #'msgpack-mod--owner-changing-mode nil t)
    (add-hook 'kill-buffer-hook #'msgpack-mod--owner-killed nil t)
    (setq buffer-read-only t)
    (msgpack-mod--ensure-companions session)
    (unless (msgpack-mod--session-status session)
      (msgpack-mod--set-status session "Ready"))
    (if (get-buffer-window (current-buffer) (selected-frame))
        (msgpack-mod-open-view)
      (msgpack-mod--defer-open-view session))))

(defconst msgpack-mod--file-regexp
  "\\.\\(?:msgpack\\|mpack\\|mpk\\)\\'"
  "File-name regexp handled by `msgpack-mod'.")

;;;###autoload
(modify-coding-system-alist
 'file msgpack-mod--file-regexp '(no-conversion . no-conversion))

;;;###autoload
(add-to-list 'auto-mode-alist (cons msgpack-mod--file-regexp #'msgpack-mod))

(provide 'msgpack-mod)
;;; msgpack-mod.el ends here
