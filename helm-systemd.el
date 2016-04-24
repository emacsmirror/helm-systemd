;;; helm-systemd.el --- helm's systemd interface        -*- lexical-binding: t; -*-

;; Copyright (C) 2016

;; Author:  <lompik@oriontabArch>
;; Package-Version: 0.0.1
;; Package-Requires: ((emacs "24.4") (helm "1.9.2") (with-editor "2.5.0"))
;; Keywords: convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'cl-lib)
(require 'helm)
(require 'with-editor)
(require 'subr-x)

(defvar helm-systemd-command-types '("service" "timer" "mount" "target" "socket" "scope" "device"))
(defvar helm-systemd-list-all nil)
(defvar helm-systemd-list-not-loaded nil)
(defvar helm-systemd-buffer-name "*Helm systemd log*")
(defvar helm-systemd-status-mode-hook nil )

(defvar helm-systemd-status-font-lock-keywords
  `(("\\(Loaded\\|Active\\|Status\\|Docs\\|Process\\|Main PID\\|Tasks\\|CGroup\\):" (1 'helm-bookmark-gnus) )
    ("active (running)" 0 'hi-green)
    ("inactive (dead)" 0 'helm-bookmark-info)
    ("active (exited)" 0 'helm-bookmark-info)

    ("[fF]ailed" 0 'diredp-executable-tag)

    ("─\\([0-9]+\\)"  (1 'helm-bookmark-info))     ; PIDs
    ("[●🔜] .*"  0 'helm-buffer-file) ; command lines ●🔜
    "Default expressions to highlight in `helm systemd log'."))

(define-derived-mode helm-systemd-status-mode fundamental-mode "Systemd-log"
  "Major mode for viewing systemd status logs.
\\{helm-systemd-status-mode-map}"
  (setq-local font-lock-defaults '(helm-systemd-status-font-lock-keywords))
  (font-lock-mode t))

(add-to-list 'auto-mode-alist `(, (concat (regexp-quote helm-systemd-buffer-name) "\\'") . helm-systemd-status-mode))

(defun helm-systemd-command-line-option ()
  (concat "--no-pager --no-legend -t " (car helm-systemd-command-types) (if helm-systemd-list-all " --all")))

(defvar helm-systemd-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "<C-return>")    'helm-cr-empty-string)
    (define-key map (kbd "<M-RET>")       'helm-cr-empty-string)
    (define-key map (kbd "C-]")           'helm-systemd-next-type)
    (define-key map (kbd "C-[")           'helm-systemd-prev-type)

    (delq nil map))
  "Keymap for `helm-systemd'.")

(defun helm-systemd-concatspace (word-list)
  "Concatenate list of string with spaces as separator"
  (mapconcat 'identity
             (delq nil word-list)
             " "))

(defun helm-systemd-systemctl-command (&rest args)
  "Construct string with: 'systemctl default-args' ARGS"
  (helm-systemd-concatspace (push (concat "systemctl " (helm-systemd-command-line-option))
                                  args) ))

(defun helm-systemd-get-canditates (sysd-options)
  "Return a list of systemd service unit"
  (let* ((result ())
         (leftcolumnwidth
          (number-to-string 25))
         (hash (make-hash-table
                :test 'equal))
         (sysd-lu (shell-command-to-string
                   (helm-systemd-systemctl-command " list-units " sysd-options)))
         (sysd-lu (delete ""
                          (split-string sysd-lu
                                        "\n"))))
    (mapc (lambda (line)
            (puthash (car (split-string line)) line hash))
          sysd-lu)
    (if helm-systemd-list-not-loaded
        (let* ((sysd-luf (shell-command-to-string
                          (helm-systemd-systemctl-command " list-unit-files " sysd-options)))
               (sysd-luf (delete ""
                                 (split-string sysd-luf "\n"))))
          (mapc (lambda (line-luf)
                  (let ((unit (car
                               (split-string line-luf))))
                    (unless (gethash unit hash nil)
                      (puthash unit line-luf hash)))) sysd-luf)))

    (let ((maxunitlength
           (string-to-number leftcolumnwidth)))
      (maphash (lambda (unit descr)
                 (setq maxunitlength
                       (max maxunitlength (length unit)))) hash)
      (setq leftcolumnwidth
            (number-to-string maxunitlength)))
    (maphash (lambda (unit descr)
               (let* ((unit_misc
                       (string-trim-left
                        (substring descr (length unit) (length descr))))
                      (formatted_output
                       (format
                        (concat "%-" leftcolumnwidth "s %s")
                        unit unit_misc)))
                 (push formatted_output result)) ) hash)

    result ))

(defun  helm-systemd-display (unit-command unit &optional isuser nodisplay)
  (with-current-buffer (get-buffer-create helm-systemd-buffer-name)
    (helm-systemd-status-mode)
    (let ((command
           (helm-systemd-systemctl-command (if isuser "--user") unit-command  unit)))
      (insert "\n🔜 " command "\n")
      (if (or isuser (string= unit-command "status"))
          (insert  (shell-command-to-string command))
        (with-temp-buffer
          (cd "/sudo::/")
          (setq command (shell-command-to-string (concat "sudo " command))))
        (insert command)
        )
      (insert "\n"))
    ;;    (propertise-sysd-buffer )
    (unless nodisplay
      (display-buffer (current-buffer)))))

(defun helm-systemd-next-type ()
  (interactive)
  (setq helm-systemd-command-types
        (append (cdr helm-systemd-command-types)
                (list (car helm-systemd-command-types))))
  (with-helm-alive-p
    (helm-force-update )))

(defun helm-systemd-prev-type ()
  (interactive)
  (setq helm-systemd-command-types
        (append (last helm-systemd-command-types)
                (remove (car (last helm-systemd-command-types))
                        helm-systemd-command-types)))
  (with-helm-alive-p
    (helm-force-update )))

(defun helm-system-persis-action (line &optional isuser)
  "Show unit status"
  (let ((unit (car (split-string line))))
    (helm-systemd-display "status" unit isuser )))

(defun helm-systemd-transformer (candidates source)
  (let ((res candidates))
    (unless (string= (car helm-systemd-command-types) "device")

      (setq res (cl-loop for i in candidates
                         for split = (split-string i)
                         for unit = (car split)
                         for loaded = (nth 1 split)
                         for active = (nth 2 split)
                         for running = (nth 3 split)
                         for description = (if running (helm-systemd-concatspace (subseq split 4)))
                         collect (let ((line i))
                                   (unless (and unit loaded active running description)
                                     line)
                                   (if (and loaded (not (string= (car helm-systemd-command-types) "mount")))
                                       (let* ((isenabled (car (split-string
                                                               (shell-command-to-string
                                                                (helm-systemd-concatspace `("systemctl" "is-enabled "
                                                                                            ,(if (string-match "User"
                                                                                                               (cdr (assoc 'name source)))
                                                                                                 "--user")
                                                                                            ,unit))))))
                                              (propena (cond ((string= isenabled "enabled") 'helm-bookmark-info)
                                                             ((string= isenabled "static") 'helm-bookmark-gnus)
                                                             (t 'helm-bookmark-gnus)))
                                              (isenabled (format "%8s" isenabled) ))
                                         (setq line (replace-regexp-in-string loaded (concat (propertize isenabled 'face propena) " " loaded " ") line ))))
                                   (if (string=  running "running")
                                       (setq line
                                             (replace-regexp-in-string running
                                                                       (propertize
                                                                        running
                                                                        'face
                                                                        'helm-ff-directory) line )))
                                   (if (string= running "exited")
                                       (setq line
                                             (replace-regexp-in-string running
                                                                       (propertize
                                                                        running
                                                                        'face
                                                                        'helm-bookmark-info) line )))
                                   (if (string= running "failed")
                                       (setq line
                                             (replace-regexp-in-string running
                                                                       (propertize
                                                                        running
                                                                        'face
                                                                        'diredp-executable-tag) line )))
                                   (if description
                                       (setq line
                                             (replace-regexp-in-string
                                              (regexp-quote description) (propertize
                                                                          description
                                                                          'face
                                                                          'helm-buffer-process) line t)))
                                   line ))))
    res))

(defun helm-systemd-build-source ()
  (helm-build-sync-source "systemd"
    :candidates (lambda ()
                  (reverse (helm-systemd-get-canditates "") ))
    :action (helm-make-actions
             "Print"   (lambda (candidate)
                         (helm-systemd-display "status" (car (split-string candidate)) nil t))
             "Restart" (lambda (candidate)
                         (helm-systemd-display "restart" (car (split-string candidate)) nil t))
             "Stop"    (lambda (candidate)
                         (helm-systemd-display "stop" (car (split-string candidate)) nil t))
             "Start"   (lambda (candidate)
                         (helm-systemd-display "start" (car (split-string candidate)) nil t)))
    :persistent-action #'helm-system-persis-action
    :persistent-help "Show unit status"
    :keymap helm-systemd-map
    :filtered-candidate-transformer #'helm-systemd-transformer))

(defun helm-systemd-build-source-user ()
  (helm-build-sync-source "Systemd User"
    :candidates   (lambda ()
                    (reverse (helm-systemd-get-canditates "--user")))
    :action (helm-make-actions
             "Print"   (lambda (candidate)
                         (helm-systemd-display "status" (car (split-string candidate)) t t))
             "Restart" (lambda (candidate)
                         (helm-systemd-display "restart" (car (split-string candidate)) t t))
             "Stop"    (lambda (candidate)
                         (helm-systemd-display "stop" (car (split-string candidate)) t t))
             "Start"   (lambda (candidate)
                         (helm-systemd-display "start" (car (split-string candidate)) t t))
             "Edit with Emacs"   (lambda (candidate)
                                   (add-to-list 'with-editor-envvars "SYSTEMD_EDITOR" t)
                                   (add-to-list 'auto-mode-alist '("\\.#.*\\.service.*\\'" . systemd-mode))
                                   (with-editor-async-shell-command (concat "systemctl --user --full edit " (car (split-string candidate))) )))
    :persistent-action (lambda (line) (funcall #'helm-system-persis-action line t))
    :persistent-help "Show unit status"
    :keymap helm-systemd-map

    :filtered-candidate-transformer #'helm-systemd-transformer))

;;;###autoload
(defun helm-systemd ()
  (interactive)
  (helm
   :sources (mapcar (lambda (func)
                      (funcall func))
                    '(helm-systemd-build-source helm-systemd-build-source-user))
   :buffer
   (concat "*helm systemd*")) )

(provide 'helm-systemd)
;;; helm-systemd.el ends here
