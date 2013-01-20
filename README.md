recaptcha
=========

![alt text][logo]
![logo]: https://raw.github.com/fsmunoz/recaptcha/master/recaptcha-el.png "Logo"

Emacs Lisp interface to reCAPTCHA.

This file contains an elisp interface to Google's reCAPTCHA
service; two different areas are covered:

1) reCAPTCHA: verifies that the user as correctly introduced the CAPTCHA

2) reCAPTCHA mailhide: used to encrypt email addresses in webpages, and decrypt them after a successful CAPTCHA

The main entry points are:

* recaptcha-html: outputs the HTML code that needs to be included in a webpage to display the CAPTCHA
* recaptcha-verify: takes as input the challenge (i.e. what the user wrote) and validates the CAPTCHA
* recaptcha-mailhide-html: outputs the HTML to show an email address.

NB: it uses the github version of Markus Sauermann's aes.ek available here: https://github.com/gaddhi/aes .
