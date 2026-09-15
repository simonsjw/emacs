;;; lang-python-format.el --- Ruff / Apheleia formatting for Python. -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Simon Watson
;; SPDX-License-Identifier: MIT

;; Author: Simon Watson

;;; Commentary:

;; Piece of `lang-python': Ruff format/isort via Apheleia.  Buffer-local
;; forms run from `my-lang-python/format-setup', called by the loader
;; hook.  Do not enable `apheleia-mode' at `require'.
;;
;; Map:
;;   Feature:    lang-python-format
;;   Load-after: path-support logging-config
;;   Load-phase: lang
;;   Keymaps:    none
;;   Docs:       docs/lang-python-format.org
;;   OS:         ruff

;;; Code:

(require 'path-support)
(require 'logging-config)
(log/debug :fn 'lang-python-format
           :msg "Starting load of the lang-python-format module."
           :obj t)

(declare-function my-in-buffer-tools/comment-align-buffer "system-buffer-tools")
(declare-function apheleia-format-buffer "apheleia")
(defvar apheleia-formatters)

(defun my-lang-python/organize-imports ()
  "Organise imports in the current buffer using ruff-isort via Apheleia.
This runs only the import organisation formatter, preserving the buffer's
point and avoiding full reformatting."
  (interactive)
  (unless (derived-mode-p 'python-ts-mode 'python-mode)
    (user-error "Not in a Python mode"))
  (apheleia-format-buffer 'ruff-isort))

(defun my-lang-python/format-buffer ()
  "Format the entire buffer using ruff via Apheleia.
This applies Ruff's code style formatter, preserving point."
  (interactive)
  (unless (derived-mode-p 'python-ts-mode 'python-mode)
    (user-error "Not in a Python mode"))
  (apheleia-format-buffer
   '(ruff-isort ruff)
   (lambda ()
     (my-in-buffer-tools/comment-align-buffer (point-min) (point-max))))
  )

(defun my-lang-python/format-region (START END)
  "Format the active region with `ruff format --range'.
START and END are the region bounds.  Uses the whole buffer as
context so the snippet does not have to be a valid module."
  (interactive "r")
  (unless (derived-mode-p 'python-ts-mode 'python-mode)
    (user-error "Not in a Python mode"))
  (unless (use-region-p)
    (user-error "No region active; use `my-lang-python/format-buffer'"))
  (let* ((range (format "%d:%d-%d:%d"
                        (line-number-at-pos START t)
                        (1+ (save-excursion (goto-char START) (current-column)))
                        (line-number-at-pos END t)
                        (1+ (save-excursion (goto-char END) (current-column)))))
         (file (or buffer-file-name "region.py"))
         (out (get-buffer-create " *ruff-format-region*")))
    (unwind-protect
        (let ((code (apply #'call-process-region
                           (point-min) (point-max)
                           "ruff" nil out nil
                           "format" "--silent"
                           "--stdin-filename" file
                           "--range" range
                           "-")))
          (if (eq code 0)
              (let ((formatted (with-current-buffer out (buffer-string))))
                (replace-buffer-contents out)
                (when (fboundp 'my-in-buffer-tools/comment-align-buffer)
                  (my-in-buffer-tools/comment-align-buffer START END)))
            (user-error "ruff format --range failed (%s): %s"
                        code
                        (with-current-buffer out (buffer-string)))))
      (kill-buffer out))))

(defun my-lang-python/align-comments-before-save ()
  "Align existing inline comments before save, if in Python mode.
Operates on the whole buffer to match Apheleia's scope.  Runs after formatting."
  (when (and (derived-mode-p 'python-ts-mode 'python-mode)
             (fboundp 'my-in-buffer-tools/comment-align-buffer))
    (save-excursion
      (my-in-buffer-tools/comment-align-buffer (point-min) (point-max)))))

(defun my-lang-python/format-setup ()
  "Enable Apheleia and buffer-local format-on-save for `python-ts-mode'.
Do not call this at `require'; the loader hook invokes it."
  (require 'apheleia)
  (apheleia-mode 1)
  ;; Stock Apheleia names: ruff = `ruff format --silent`, ruff-isort = I-rules fix.
  (setf (alist-get 'python-ts-mode apheleia-mode-alist) '(ruff-isort ruff))
  (setf (alist-get 'python-mode    apheleia-mode-alist) '(ruff-isort ruff))
  (add-hook 'before-save-hook
            #'my-lang-python/align-comments-before-save nil t))

(log/debug :fn 'lang-python-format
           :msg "Finishing load of the lang-python-format module."
           :obj t)

(provide 'lang-python-format)
;;; lang-python-format.el ends here
