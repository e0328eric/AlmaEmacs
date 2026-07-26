;;; msgpack-mod-tests.el --- Tests for msgpack-mod -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'msgpack-mod)

(defun msgpack-mod-test--hex (text)
  "Convert hexadecimal TEXT to bytes."
  (msgpack-mod--parse-hex text))

(defun msgpack-mod-test--hex-of (bytes)
  "Convert BYTES to hexadecimal text."
  (msgpack-mod--hex-string bytes))

(ert-deftest msgpack-mod-codec-primitives ()
  (dolist (case `((,msgpack-mod--null . "c0")
                  (,msgpack-mod--false . "c2")
                  (t . "c3")
                  (0 . "00")
                  (127 . "7f")
                  (-1 . "ff")
                  (-32 . "e0")
                  (128 . "cc80")
                  (-33 . "d0df")
                  (65536 . "ce00010000")
                  (-32769 . "d2ffff7fff")
                  (18446744073709551615 . "cfffffffffffffffff")
                  (-9223372036854775808 . "d38000000000000000")))
    (let ((value (car case))
          (hex (cdr case)))
      (should (equal (msgpack-mod-test--hex-of
                      (msgpack-mod-encode value))
                     hex))
      (should (equal (msgpack-mod-decode (msgpack-mod-test--hex hex))
                     value)))))

(ert-deftest msgpack-mod-codec-collections-and-utf8 ()
  (let* ((value
          (msgpack-mod--make-map
           `(("text" . "한")
             ("array" . [1 ,msgpack-mod--false ,msgpack-mod--null])
             ("emptyObject" . ,(msgpack-mod--make-map nil))
             ("emptyArray" . []))))
         (round-trip (msgpack-mod-decode (msgpack-mod-encode value))))
    (should (equal round-trip value))
    (should-not (multibyte-string-p (msgpack-mod-encode value))))
  (should (equal (msgpack-mod-test--hex-of (msgpack-mod-encode "한"))
                 "a3ed959c")))

(ert-deftest msgpack-mod-codec-floats ()
  (should (equal (msgpack-mod-test--hex-of (msgpack-mod-encode 1.0))
                 "cb3ff0000000000000"))
  (should (= (msgpack-mod-decode
              (msgpack-mod-test--hex "ca3f800000"))
             1.0))
  (let* ((negative-zero
          (msgpack-mod-decode
           (msgpack-mod-test--hex "cb8000000000000000")))
         (subnormal
          (msgpack-mod-decode
           (msgpack-mod-test--hex "cb0000000000000001"))))
    (should (zerop negative-zero))
    (should (< (copysign 1.0 negative-zero) 0.0))
    (should (equal (msgpack-mod-test--hex-of
                    (msgpack-mod-encode negative-zero))
                   "cb8000000000000000"))
    (should (= subnormal (ldexp 1.0 -1074)))
    (should (equal (msgpack-mod-test--hex-of
                    (msgpack-mod-encode subnormal))
                   "cb0000000000000001")))
  (dolist (hex '("ca7fc01234" "cb7ff0000000000000"
                 "cbfff0000000000000"))
    (let ((value (msgpack-mod-decode (msgpack-mod-test--hex hex))))
      (should (msgpack-mod--nonfinite-p value))
      (should (equal (msgpack-mod-test--hex-of
                      (msgpack-mod-encode value))
                     hex)))))

(ert-deftest msgpack-mod-codec-binary-extension-and-arbitrary-map ()
  (let* ((value
          (msgpack-mod--make-map
           (list
            (cons 1 (msgpack-mod--make-binary
                     (msgpack-mod-test--hex "00ff")))
            (cons "duplicate" 1)
            (cons "duplicate" 2)
            (cons "$msgpack"
                  (msgpack-mod--make-extension
                   -1 (msgpack-mod-test--hex "01020304"))))))
         (encoded (msgpack-mod-encode value))
         (decoded (msgpack-mod-decode encoded))
         (json (msgpack-mod--json-string decoded))
         reparsed)
    (with-temp-buffer
      (insert json)
      (setq reparsed (msgpack-mod--parse-json-buffer)))
    (should (equal reparsed value))
    (should (string-match-p "\"type\": \"map\"" json))
    (should (string-match-p "\"type\": \"binary\"" json))
    (should (string-match-p "\"type\": \"extension\"" json))))

(ert-deftest msgpack-mod-json-distinguishes-empty-values-null-and-false ()
  (let* ((value
          (msgpack-mod--make-map
           `(("object" . ,(msgpack-mod--make-map nil))
             ("array" . [])
             ("null" . ,msgpack-mod--null)
             ("false" . ,msgpack-mod--false))))
         (text (msgpack-mod--json-string value))
         parsed)
    (with-temp-buffer
      (insert text)
      (setq parsed (msgpack-mod--parse-json-buffer)))
    (should (equal parsed value))))

(ert-deftest msgpack-mod-json-nonfinite-wrapper-preserves-bits ()
  (let* ((value (msgpack-mod-decode
                 (msgpack-mod-test--hex "ca7fc01234")))
         (text (msgpack-mod--json-string value))
         parsed)
    (with-temp-buffer
      (insert text)
      (setq parsed (msgpack-mod--parse-json-buffer)))
    (should (equal parsed value))))

(ert-deftest msgpack-mod-json-parser-preserves-point ()
  (with-temp-buffer
    (insert "{\"answer\": 42}")
    (goto-char 3)
    (let ((value (msgpack-mod--parse-json-buffer)))
      (should (equal (msgpack-mod--map-entries value)
                     '(("answer" . 42)))))
    (should (= (point) 3))
    (erase-buffer)
    (insert "{\"answer\":")
    (goto-char 3)
    (should-error (msgpack-mod--parse-json-buffer) :type 'json-error)
    (should (= (point) 3))))

(ert-deftest msgpack-mod-codec-rejects-malformed-input ()
  (dolist (hex '("" "c1" "d9" "d901ff" "81a161" "00ff" "0001"))
    (should-error (msgpack-mod-decode (msgpack-mod-test--hex hex))
                  :type 'msgpack-mod-error)))

(ert-deftest msgpack-mod-json-formatting-only-edit-preserves-original-bytes ()
  (let* ((original (msgpack-mod-test--hex "ca3f800000"))
         (owner (generate-new-buffer " *msgpack-owner*"))
         session json hex)
    (unwind-protect
        (with-current-buffer owner
          (set-buffer-multibyte nil)
          (insert original)
          (set-buffer-modified-p nil)
          (msgpack-mod)
          (setq session msgpack-mod--session
                json (msgpack-mod--session-json session)
                hex (msgpack-mod--session-hex session))
          (with-current-buffer json
            (goto-char (point-max))
            (insert "   \n")
            (msgpack-mod-apply-json))
          (should (equal (msgpack-mod--owner-bytes session) original)))
      (when (buffer-live-p owner)
        (when (msgpack-mod--session-p session)
          (msgpack-mod--cancel-timer session)
          (setf (msgpack-mod--session-pending-source session) nil))
        (with-current-buffer owner (set-buffer-modified-p nil))
        (kill-buffer owner))
      (dolist (buffer (list json hex))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer))))))

(ert-deftest msgpack-mod-idle-sync-waits-for-valid-json ()
  (let* ((msgpack-mod-sync-delay nil)
         (original (msgpack-mod-test--hex "81a6616e737765722a"))
         (updated (msgpack-mod-test--hex "81a6616e737765722b"))
         (owner (generate-new-buffer " *msgpack-idle-json-owner*"))
         session json hex)
    (unwind-protect
        (with-current-buffer owner
          (set-buffer-multibyte nil)
          (insert original)
          (set-buffer-modified-p nil)
          (msgpack-mod)
          (setq session msgpack-mod--session
                json (msgpack-mod--session-json session)
                hex (msgpack-mod--session-hex session))
          (msgpack-mod--cancel-display-timer session)
          (with-current-buffer json
            (erase-buffer)
            (insert "{\"answer\":")
            (goto-char 3))
          (let ((original-set-owner
                 (symbol-function 'msgpack-mod--set-owner-bytes))
                (owner-write-count 0)
                messages)
            (cl-letf (((symbol-function 'msgpack-mod--set-owner-bytes)
                       (lambda (active-session bytes)
                         (setq owner-write-count (1+ owner-write-count))
                         (funcall original-set-owner active-session bytes)))
                      ((symbol-function 'message)
                       (lambda (format-string &rest arguments)
                         (push (apply #'format-message
                                      format-string arguments)
                               messages))))
              ;; Incomplete JSON is an ordinary editing state.  Automatic
              ;; synchronization must leave both data and cursor untouched.
              (with-current-buffer json
                (should-not (msgpack-mod--idle-sync session json))
                (should (= (point) 3))
                (should (buffer-modified-p)))
              (should-not messages)
              (should (= owner-write-count 0))
              (should (equal (msgpack-mod--owner-bytes session) original))
              (with-current-buffer hex
                (should (equal (msgpack-mod--dehexlify-current-buffer)
                               original))
                (should-not (buffer-modified-p)))
              (should (eq (msgpack-mod--session-pending-source session) json))
              (should (equal (msgpack-mod--session-status session)
                             "Waiting for valid JSON"))

              ;; Explicit application still reports the detailed input error,
              ;; but it must preserve point as well.
              (with-current-buffer json
                (should-error (msgpack-mod-apply-json) :type 'json-error)
                (should (= (point) 3)))
              (should (= owner-write-count 0))

              ;; The next valid edit synchronizes once, without moving point.
              (with-current-buffer json
                (goto-char (point-max))
                (insert "43}\n")
                (goto-char 3)
                (should (msgpack-mod--idle-sync session json))
                (should (= (point) 3))
                (should-not (buffer-modified-p)))
              (should (= owner-write-count 1))
              (should (equal (msgpack-mod--owner-bytes session) updated))
              (with-current-buffer hex
                (should (equal (msgpack-mod--dehexlify-current-buffer)
                               updated))
                (should-not (buffer-modified-p)))
              (should-not (msgpack-mod--session-pending-source session))
              (should (string-prefix-p
                       "JSON applied" (msgpack-mod--session-status session)))
              (should-not (msgpack-mod--idle-sync session json))
              (should (= owner-write-count 1))
              (should-not messages))))
      (when (msgpack-mod--session-p session)
        (msgpack-mod--cancel-timer session)
        (msgpack-mod--cancel-display-timer session)
        (setf (msgpack-mod--session-pending-source session) nil))
      (dolist (buffer (list json hex owner))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer))))))

(ert-deftest msgpack-mod-session-json-raw-and-save-workflow ()
  (let* ((filename (make-temp-file "msgpack-mod-" nil ".msgpack"))
         (initial (msgpack-mod-test--hex "81a6616e737765722a"))
         owner session json hex)
    (unwind-protect
        (progn
          (let ((coding-system-for-write 'no-conversion))
            (write-region initial nil filename nil 'silent))
          (setq owner (find-file-noselect filename))
          (with-current-buffer owner
            (should (eq major-mode 'msgpack-mod))
            (should-not enable-multibyte-characters)
            (should (eq (key-binding (kbd "C-c C-v"))
                        #'msgpack-mod-open-view))
            (setq session msgpack-mod--session
                  json (msgpack-mod--session-json session)
                  hex (msgpack-mod--session-hex session)))
          (should (buffer-live-p json))
          (should (buffer-live-p hex))
          (should-not (buffer-local-value 'buffer-undo-list json))
          (should (eq (buffer-local-value 'major-mode hex) 'hexl-mode))
          (with-current-buffer json
            (erase-buffer)
            (insert "{\"answer\": 43}\n")
            ;; `save-buffer' in a companion delegates to the binary owner, so
            ;; exit/save-some-buffers cannot write JSON by mistake.
            (save-buffer))
          (should (equal (msgpack-mod--owner-bytes session)
                         (msgpack-mod-test--hex "81a6616e737765722b")))
          (with-temp-buffer
            (set-buffer-multibyte nil)
            (insert-file-contents-literally filename)
            (should (equal (buffer-string)
                           (msgpack-mod-test--hex
                            "81a6616e737765722b"))))
          (with-current-buffer hex
            (hexl-goto-address 0)
            (msgpack-mod-hex-insert-byte #x00)
            (should (= (length (msgpack-mod--dehexlify-current-buffer)) 10))
            (msgpack-mod-hex-delete-byte)
            (should (equal (msgpack-mod--dehexlify-current-buffer)
                           (msgpack-mod-test--hex
                            "81a6616e737765722b")))
            (hexl-goto-address 8)
            (hexl-insert-char 44 1)
            (msgpack-mod-refresh-json)
            (msgpack-mod-save))
          (with-temp-buffer
            (set-buffer-multibyte nil)
            (insert-file-contents-literally filename)
            (should (equal (buffer-string)
                           (msgpack-mod-test--hex "81a6616e737765722c"))))
          (with-current-buffer json
            (should (string-match-p "44" (buffer-string)))))
      (when (buffer-live-p owner)
        (when (msgpack-mod--session-p session)
          (msgpack-mod--cancel-timer session)
          (setf (msgpack-mod--session-pending-source session) nil))
        (with-current-buffer owner (set-buffer-modified-p nil))
        (kill-buffer owner))
      (dolist (buffer (list json hex))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (when (file-exists-p filename)
        (delete-file filename)))))

(ert-deftest msgpack-mod-session-detects-edits-in-both-views ()
  (let* ((owner (generate-new-buffer " *msgpack-conflict-owner*"))
         session json hex)
    (unwind-protect
        (with-current-buffer owner
          (set-buffer-multibyte nil)
          (insert (msgpack-mod-test--hex "01"))
          (set-buffer-modified-p nil)
          (msgpack-mod)
          (setq session msgpack-mod--session
                json (msgpack-mod--session-json session)
                hex (msgpack-mod--session-hex session))
          (let ((msgpack-mod-sync-delay nil))
            (with-current-buffer json
              (goto-char (point-max))
              (insert " "))
            (with-current-buffer hex
              (hexl-goto-address 0)
              (hexl-insert-char 2 1)
              (should-error (msgpack-mod-refresh-json) :type 'user-error)
              (msgpack-mod-refresh-json t))
            (should (equal (msgpack-mod--owner-bytes session)
                           (msgpack-mod-test--hex "02")))
            (should-not (buffer-modified-p json))
            (should-not (buffer-modified-p hex))
            ;; The symmetric force path must discard raw bytes even when the
            ;; JSON edit is only whitespace and equals the current owner.
            (with-current-buffer json
              (goto-char (point-max))
              (insert " "))
            (with-current-buffer hex
              (hexl-goto-address 0)
              (hexl-insert-char 3 1))
            (with-current-buffer json
              (msgpack-mod-apply-json t))
            (should (equal (msgpack-mod--owner-bytes session)
                           (msgpack-mod-test--hex "02")))
            (with-current-buffer hex
              (should (equal (msgpack-mod--dehexlify-current-buffer)
                             (msgpack-mod-test--hex "02")))
              (should-not (buffer-modified-p)))))
      (when (msgpack-mod--session-p session)
        (msgpack-mod--cancel-timer session)
        (setf (msgpack-mod--session-pending-source session) nil))
      (dolist (buffer (list json hex owner))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer))))))

(ert-deftest msgpack-mod-protects-unsynchronized-companion-edits ()
  (let* ((owner (generate-new-buffer " *msgpack-lifecycle-owner*"))
         session json hex)
    (unwind-protect
        (with-current-buffer owner
          (set-buffer-multibyte nil)
          (insert (msgpack-mod-test--hex "01"))
          (set-buffer-modified-p nil)
          (msgpack-mod)
          (setq session msgpack-mod--session
                json (msgpack-mod--session-json session)
                hex (msgpack-mod--session-hex session))
          (should (eq (buffer-local-value 'buffer-offer-save json) 'always))
          (should (eq (buffer-local-value 'buffer-offer-save hex) 'always))
          (let ((msgpack-mod-sync-delay nil))
            (with-current-buffer json
              (goto-char (point-max))
              (insert " ")))
          (should (memq json (files--buffers-needing-to-be-saved t)))
          ;; The pending pointer can name a clean pane after edit/undo.  The
          ;; owner guard must still inspect the actually modified JSON pane.
          (setf (msgpack-mod--session-pending-source session) hex)
          (cl-letf (((symbol-function 'yes-or-no-p)
                     (lambda (&rest _) nil)))
            (should-not (kill-buffer json))
            (should (buffer-live-p json))
            (with-current-buffer json
              (should-error (fundamental-mode) :type 'user-error)
              (should (eq major-mode 'msgpack-mod-json-mode)))
            (should-not (kill-buffer owner))
            (should (buffer-live-p owner))
            (with-current-buffer owner
              (should-error (fundamental-mode) :type 'user-error)
              (should (eq major-mode 'msgpack-mod))))
          ;; If the latest pane is killed intentionally, saving must discover
          ;; an older remaining modified pane instead of trusting a stale
          ;; pending-source pointer.
          (let ((msgpack-mod-sync-delay nil))
            (with-current-buffer json
              (erase-buffer)
              (insert "2"))
            (with-current-buffer hex
              (hexl-goto-address 0)
              (hexl-insert-char 3 1)))
          (cl-letf (((symbol-function 'yes-or-no-p)
                     (lambda (&rest _) t)))
            (should (kill-buffer hex)))
          (should-not (msgpack-mod--session-pending-source session))
          (msgpack-mod--sync-pending session)
          (should (equal (msgpack-mod--owner-bytes session)
                         (msgpack-mod-test--hex "02"))))
      (when (msgpack-mod--session-p session)
        (msgpack-mod--cancel-timer session)
        (msgpack-mod--cancel-display-timer session)
        (setf (msgpack-mod--session-pending-source session) nil))
      (dolist (buffer (list json hex owner))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer))))))

(ert-deftest msgpack-mod-find-file-opens-json-left-and-hex-right ()
  (let ((filename (make-temp-file "msgpack-mod-layout-" nil ".msgpack"))
        owner session json hex)
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (let ((coding-system-for-write 'no-conversion))
            (write-region (msgpack-mod-test--hex "01") nil
                          filename nil 'silent))
          (find-file filename)
          ;; `msgpack-mod' defers layout until `find-file' has displayed the
          ;; newly selected buffer.
          (sit-for 0.05)
          (setq session msgpack-mod--session
                owner (msgpack-mod--session-owner session)
                json (msgpack-mod--session-json session)
                hex (msgpack-mod--session-hex session))
          (should (= (length (window-list)) 2))
          (let ((json-window (get-buffer-window json))
                (hex-window (get-buffer-window hex)))
            (should (window-live-p json-window))
            (should (window-live-p hex-window))
            (should (< (car (window-edges json-window))
                       (car (window-edges hex-window))))
            (should (eq (window-buffer (selected-window)) json))))
      (when (msgpack-mod--session-p session)
        (msgpack-mod--cancel-timer session)
        (msgpack-mod--cancel-display-timer session)
        (setf (msgpack-mod--session-pending-source session) nil))
      (when (buffer-live-p owner)
        (with-current-buffer owner (set-buffer-modified-p nil))
        (kill-buffer owner))
      (dolist (buffer (list json hex))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (when (file-exists-p filename)
        (delete-file filename)))))

(provide 'msgpack-mod-tests)
;;; msgpack-mod-tests.el ends here
