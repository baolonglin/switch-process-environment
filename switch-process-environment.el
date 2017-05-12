;;; switch-process-environment.el --- Switch process environment based on different environments shell configuration.

;; Copyright (C) 2017- Baolong Lin

;; Author: Baolong Lin <lbl52001@gmail.com>
;; Keywords: environment
;; URL: https://github.com/baolonglin/switch-process-environment
;; Package-Version: 0
;; Package-Requires: ((emacs "25"))

;; This file is not part of GNU Emacs.

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This library allows the user to set Emacs' `process-environment'
;; from the shell configuration.  It makes user switch different
;; space quit easy.

;; Installation:

;; Place this file on a directory in your `load-path', and explicitly
;; require it.

;; Usage:
;;
;;     (require 'switch-process-environment)
;;     (switch-process-environment-setup)
;;     (switch-process-environment-switch)
;;
;; Customize `switch-process-environment-variables' to modify the list of
;; variables imported.
;;

;;; Code:

(require 'comint)

(defgroup switch-process-environment nil
  "Make Emacs switch process environment."
  :prefix "switch-process-environment-"
  :group 'environment)

(defcustom switch-process-environment-variables
  nil
  "All environments to be loaded during setup."
  :type '(alist :value-type (file :must-match t))
  :group 'switch-process-environment)

(defvar switch-process-environment-new-line "\n")
(defvar switch-process-environment-shell-patten ".*>")

(defvar switch-process-environment-runtime-environments nil)
(defvar switch-process-environment-current-environment nil)

(defun switch-process-environment-shell-output-to-buffer (proc string)
  "Output PROC output STRING to buffer."
  (with-current-buffer (get-buffer-create "*switch-process-environment-shell-tmp*")
    (let ((shell-prompt-pattern switch-process-environment-shell-patten))
      (insert string)
      (goto-char (point-max))
      (when (string-match (concat shell-prompt-pattern "$") (thing-at-point 'line))
        (advice-remove (process-filter proc) #'switch-process-environment-shell-output-to-buffer)
        )
      )
    ))

(defun switch-process-environment-shell-simple-send (proc string)
  "Send to PROC with STRING through comint."
  (comint-send-string proc string)
  (if comint-input-sender-no-newline
      (if (not (string-equal string ""))
          (process-send-eof))
    (comint-send-string proc switch-process-environment-new-line)))

(defun switch-process-environment-shell-execute (command command-result-handler)
  "Execute COMMAND through shell, use COMMAND-RESULT-HANDLER to handle the output result."
  (save-excursion
    (let* ((name "*switch-process-environment-shell*")
           (buffer (get-buffer name))
           (proc (get-buffer-process buffer)))
      (when (and buffer proc)
        (set-buffer name)
        (with-current-buffer (get-buffer-create "*switch-process-environment-shell-tmp*")
          (erase-buffer)
          )
        (advice-add (process-filter proc) :before #'switch-process-environment-shell-output-to-buffer)
        (switch-process-environment-shell-simple-send proc command)
        (while (advice-member-p #'switch-process-environment-shell-output-to-buffer (process-filter proc))
          (sleep-for 0 100)
          )
        (with-current-buffer (get-buffer "*switch-process-environment-shell-tmp*")
          (delete-trailing-whitespace (point-min) (point-max))
          (funcall command-result-handler (butlast (cdr (split-string (buffer-string) "\n" t))))
          )
        )
      )
    )
  )

(defun switch-process-environment-get-parent-directory (f)
  "Get parent directory of F."
  (unless (equal "/" f)
    (file-name-directory (directory-file-name f)))
  )

(defun switch-process-environment-execute-commands-expected (cmds)
  "Execute CMDS with expectation."
  (catch 'failcmd
    (mapc
     (lambda (x)
       (let ((cmd (plist-get x 'cmd))
             (handler (plist-get x 'handler)))
         (switch-process-environment-shell-execute cmd
                                                   (lambda (output)
                                                     (when (and handler (not (funcall handler output)))
                                                       (message (format "failed to execute %s" cmd) )
                                                       (throw 'failcmd x))
                                                     ))
         )
       )
     cmds)
    nil
    )
  )

(defun switch-process-environment-fetch-env-for-file (f)
  "Fetch environment for config file F."
  (let* ((ret nil)
         (dir (switch-process-environment-get-parent-directory f))
         (shellBufferName "*switch-process-environment-shell*")
         (cmds (list
                (list 'cmd "cd" 'handler nil)
                (list 'cmd (format "cd %s" dir) 'handler nil)
                (list 'cmd (format "source %s" (file-name-nondirectory f))
                      'handler nil)
                (list 'cmd "env"
                      'handler (lambda (output) (setq ret output)))
                )))
    (setq kill-buffer-query-functions (delq 'process-kill-buffer-query-function kill-buffer-query-functions))
    (when (get-buffer shellBufferName)
      (kill-buffer shellBufferName)
      )
    (shell shellBufferName)
    ;;(pop-to-buffer "*switch-process-environment-shell*")
    (switch-process-environment-execute-commands-expected cmds)
    (kill-buffer shellBufferName)
    (kill-buffer "*switch-process-environment-shell-tmp*")
    (add-to-list 'kill-buffer-query-functions 'process-kill-buffer-query-function)
    ret
    )
  )


(defun switch-process-environment-setup ()
  "Setup process environment according the customed variables."
  (interactive)
  (setq switch-process-environment-runtime-environments `((default . ,initial-environment)))
  (setq switch-process-environment-runtime-environments
        (append switch-process-environment-runtime-environments
                (mapcar (lambda (x)
                          (progn
                            (message "Start setup environment %S" (car x))
                            (cons (car x) (switch-process-environment-fetch-env-for-file (cdr x)))
                            )
                          )
                        switch-process-environment-variables)))
  (message "Setup environment done")
  )

(defun switch-process-environment-switch (env)
  "Swtich environment to be ENV."
  (interactive (list (completing-read (format "Current env (%s), Choose new env: "
                                              (if switch-process-environment-current-environment
                                                  switch-process-environment-current-environment
                                                "nil"
                                                )) (mapcar (lambda (x) (car x)) switch-process-environment-runtime-environments))))
  (when env
    (setq process-environment (alist-get (intern env) switch-process-environment-runtime-environments))
    (setq exec-path (split-string (getenv "PATH") ":"))
    (setq switch-process-environment-current-environment env)
    )
  )

(defun switch-process-environment-save (env)
  "Save current environment as ENV."
  (interactive (list
                (read-string "Enter environment name: ")))
  (if (assoc (intern env) switch-process-environment-runtime-environments)
      (message "Environment name %s already exists" env)
    (add-to-list 'switch-process-environment-runtime-environments
                 (cons (intern env) process-environment))
    (setq switch-process-environment-current-environment env)
    )
  )

(provide 'switch-process-environment)
