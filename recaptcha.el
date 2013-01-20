;;; recaptcha.el --- an Emacs Lisp interface to reCAPTCHA
;;
;; Copyright (c) 2013 Frederico Munoz
;;
;; Author: Frederico Munoz <fsmunoz@gmail.com>
;; Created: Jan 2013
;; Keywords: lisp, http, captcha
;;
;; This file is NOT part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;; 
;; This file contains an elisp interface to Google's reCAPTCHA
;; service; two different areas are covered:
;;
;; 1) reCAPTCHA: verifies that the user as correctly introduced the CAPTCHA
;; 2) reCAPTCHA mailhide: used to encrypt email addresses in webpages, and decrypt them after a successful CAPTCHA
;;
;; The main entry points are:
;;
;; recaptcha-html: outputs the HTML code that needs to be included in a webpage to display the CAPTCHA
;; recaptcha-verify: takes as input the challenge (i.e. what the user wrote) and validates the CAPTCHA
;; recaptcha-mailhide-html: outputs the HTML to show an email address.
;;
;; Several supporting functions exist that deal with specific tasks;
;; the ones considered private adhere to the practice of being
;; prefixed with recaptcha-- .
;;
;; The following code can be used to quickly test the code, it is
;; based on elnode (and thus requires it of course). After evaluating
;; it http://localhost:8009/recaptcha and http://localhost:8009/mailhide/
;; are listening, each testing a particular functionality.
;;
;; (defun root-handler (httpcon)
;;   (elnode-hostpath-dispatcher httpcon '(("^.*//recaptcha/\\(.*\\)" . recaptcha-handler)
;; 					("^.*//mailhide/\\(.*\\)" . mailhide-handler))))
;;
;; (elnode-start 'root-handler :port 8009)
;;
;; (defun recaptcha-handler (httpcon)
;;   "Demonstration function"
;;   (elnode-http-start httpcon 200 '("Content-type" . "text/html"))
;;   (when (elnode-http-param httpcon "recaptcha_response_field")
;;     ;; Test reCAPTCHA
;;     (if (recaptcha-verify
;; 	 (process-contact httpcon :host)
;; 	 (elnode-http-param httpcon "recaptcha_challenge_field")
;; 	 (elnode-http-param httpcon "recaptcha_response_field"))
;; 	(elnode-http-return httpcon "OK!")
;;       (elnode-http-return httpcon (recaptcha-html))))
;;   (elnode-http-return httpcon (recaptcha-html)))
;;
;; (defun mailhide-handler (httpcon)
;;   "Demonstration function"
;;   (elnode-http-start httpcon 200 '("Content-type" . "text/html"))
;;   (elnode-http-return httpcon (recaptcha-mailhide-html "bart@example.com" "Bartolomeu Dias")))

(require 'url) ;; used to issue the POST request to the webservice
(require 'aes) ;; for the reCAPTCHA mailhide functionality

(defgroup recaptcha nil
  "An interface to Google's reCAPTCHA service."
  :prefix "recaptcha-"
  :group 'comm)

(defcustom recaptcha-verification-url "http://www.google.com/recaptcha/api/verify"
  "The verification webservice URL."
  :group 'recaptcha
  :type 'string)


(defcustom recaptcha-private-key ""
  "The reCAPTCHA private key, part of the pair of keys that can be obtained in the reCAPTCHA site."
  :group 'recaptcha
  :type 'string)

(defcustom recaptcha-public-key ""
  "The reCAPTCHA public key, part of the pair of keys that can be
obtained in the reCAPTCHA site."
  :group 'recaptcha
  :type 'string)

(defcustom recaptcha-mailhide-decoder-url "http://www.google.com/recaptcha/mailhide/d"
  "The decoder URL for reCAPTCHA mailhide"
  :group 'recaptcha
  :type 'string)

(defcustom recaptcha-mailhide-private-key ""
  "The reCAPTCHA mailhide private key, part of the pair of keys that can be obtained in the reCAPTCHA site.
NB: this keys are different from the regular reCAPTCHA ones and
are solely uses for the mailhide functionality."
  :group 'recaptcha
  :type 'string)

(defcustom recaptcha-mailhide-public-key ""
  "The reCAPTCHA mailhide public key, part of the pair of keys that can be obtained in the reCAPTCHA site.
NB: this keys are different from the regular reCAPTCHA ones and
are solely uses for the mailhide functionality."
  :group 'recaptcha
  :type 'string)

(defcustom recaptcha-html-code "<form action=\"\" method=\"post\">
  <script type=\"text/javascript\"
          src=\"http://www.google.com/recaptcha/api/challenge?k=%s\">
  </script>
  <noscript>
    <iframe src=\"http://www.google.com/recaptcha/api/noscript?k=%s\"
            height=\"300\" width=\"500\" frameborder=\"0\"></iframe><br>
    <textarea name=\"recaptcha_challenge_field\" rows=\"3\" cols=\"40\">
    </textarea>
    <input type=\"hidden\" name=\"recaptcha_response_field\"
           value=\"manual_challenge\">
  </noscript>
</form>"
  "The HTML code that will be used to insert the reCAPTCHA code in
the page; the formatting functions expect two string parameters
to fill with the public key (one for Javascript, the other for
the iframe). The form values are, by default, the ones used in
Google's reference documentation."
  :group 'recaptcha
  :type 'string)

(defcustom recaptcha-html-values '(recaptcha-public-key recaptcha-public-key)
  "Aa list containing elements that will be used for replacing
the escape codes in recaptcha-html-code. Each element of the list
will be evaluated prior to replacement, so both variables,
strings, integers or any other applicable Lisp object can be
used. The number of elements must match in number and type the
format control strings specified in recaptcha-html-code"
  :group 'recaptcha
  :type 'sexp)

;;;###autoload
(defun recaptcha-html (&optional html-template html-values)
"Returns, as a string, the HTML code that adds reCAPTCHA
functionality in a webpage.  HTML-TEMPLATE and HTML-VALUES are
optional arguments; the global custom variables
RECAPTCHA-HTML-CODE and RECAPTCHA-HTML-VALUES are used in their
absence. The former is a string, the later a list containing Lisp
objects that are evaluated before replacement."
(let ((html-template (or html-template recaptcha-html-code))
      (html-values (or html-values recaptcha-html-values)))
  (apply 'format html-template (mapcar 'eval html-values))))

;;;###autoload
(defun recaptcha-verify (remoteip challenge response &optional verify-url private-key)
  "Validates reCAPTCHA by submitting to VERIFICATION-URL
the mandatory data: PRIVATE-KEY (reCAPTCHA private key),
REMOTEIP (the client IP address), CHALLENGE (normally the value
of recaptcha_challenge_field sent via a form) and
RESPONSE (normally the value of recaptcha_response_field sent via
a form).

The RECAP-VERIFICATION-URL and PRIVATE-KEY values are optional,
and the global values with the same name are used if they are not
provided.

Returns t if valid, nil otherwise."
  (let* ((verify-url  (or verify-url recaptcha-verification-url))
	 (private-key (or private-key recaptcha-private-key))
	 (url-request-method "POST")
	 (url-request-extra-headers `(("Content-Type" . "application/x-www-form-urlencoded")))
	 (url-request-data (format "privatekey=%s&remoteip=%s&challenge=%s&response=%s" private-key remoteip challenge response)))
    (with-current-buffer (url-retrieve-synchronously verify-url)
	   (setq fsm (buffer-string))
	   (goto-char (point-min))
	   (search-forward-regexp "^\n\\([a-z]+\\)*\n\\(.*\\)" nil t)
	   (let ((result (match-string 1 nil))
		 (additional-information (match-string 1 nil)))
	     (if (equal result "true") t nil)))))

;; reCAPTCHA mailhide functions ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun recaptcha--string-to-hex (string)
  "Convert STRING into the hexadecimal representation of each byte"
  (loop for i from 0 upto (- (length string) 2) by 2 collect (string-to-number (substring string i (+ i 2)) 16) into res finally return (concat res)))

(defun recaptcha--base64-safe-encode-string (string &optional no-line-break)
  "Like base64-encode-string, but replacing + with - and / with _."
  (replace-regexp-in-string "[+/]" (lambda (match)
				     (case (string-to-char match)
				       (?+ "-")
				       (?/ "_")))
			    (base64-encode-string string no-line-break)))

(defun recaptcha-mailhide-encrypt (email &optional private-key)
  "Encrypt the EMAIL address using PRIVATE-KEY (or,if absent,
RECAPTCHA-MAILHIDE-PRIVATE-KEY); return the encrypted data in
base64 encoding"
  (let ((private-key (or private-key recaptcha-mailhide-private-key)))
    (flet ((aes-enlarge-to-multiple (v bs)
  "Enlarge unibyte string V to a multiple of number BS and pad it.
Padding is done according to RFC 5652 section 6.3.
Return a new unibyte string containing the result.  V is not changed"
  (let* ((padpre (mod (- (string-bytes v)) bs))
         (pad (if (= padpre 0) 16 padpre)))
    (concat v (make-string pad pad)))))
      (recaptcha--base64-safe-encode-string
       (aes-cbc-encrypt email	
			(make-string 16 0)
			(aes-KeyExpansion (aes-str-to-b (recaptcha--string-to-hex private-key)) 4) 4) t))))

;;;###autoload
(defun recaptcha-mailhide-encrypt (email &optional private-key)
  "Encrypt the EMAIL address using PRIVATE-KEY (or,if absent,
RECAPTCHA-MAILHIDE-PRIVATE-KEY); return the encrypted data in
base64 encoding. The AES CBC encryption uses PKCS#7 padding."
  (let ((private-key (or private-key recaptcha-mailhide-private-key)))
      (recaptcha--base64-safe-encode-string
       (aes-cbc-encrypt email	
			(make-string 16 0)
			(aes-KeyExpansion (aes-str-to-b (recaptcha--string-to-hex private-key)) 4) 4 "PKCS#7") t)))

;;;###autoload
(defun recaptcha-mailhide-create-url (email &optional private-key public-key)
  "Returns the URL that should be used to verify EMAIL;
PRIVATE-KEY and PUBLIC-KEY are optional arguments, if absent
RECAPTCHA-MAILHIDE-PUBLIC-KEY and RECAPTCHA-MAILHIDE-PRIVATE-KEY
are used by default."
  (let ((private-key (or private-key recaptcha-mailhide-private-key))
	(public-key (or public-key recaptcha-mailhide-public-key)))
  (format "%sk=%s&c=%s" recaptcha-mailhide-decoder-url public-key (recaptcha-mailhide-encrypt email private-key))))

;;;###autoload
(defun recaptcha-mailhide-html (email &optional name label private-key public-key)
 "Return html code for revealing an EMAIL address using Google's reCAPTCH mailhide"
 (let* ((private-key (or private-key recaptcha-mailhide-private-key))
	(public-key (or public-key recaptcha-mailhide-public-key))
	(label (or label "Reveal this e-mail address"))
	(name (or name "..."))
	(url (recaptcha-mailhide-create-url email private-key public-key)))
    (format "<a href=\"%s\" onclick=\"window.open('%s', '','toolbar=0,scrollbars=0,location=0,statusbar=0,menubar=0,resizable=0,width=500,height=300');return false;\" title=\"%s\">%s</a>"
	    url url label name)))


(provide 'recaptcha)
